#!/bin/bash
# Wise Linux - Hardened GRUB & Fedora BLS VFIO Configurator with Self-Verification
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
EXPECTED_BDF="${1:-}"
EXPECTED_IDS="${2:-}"

echo "[*] Re-verifying GPU topology before touching GRUB/BLS..."
SCAN_OUT=$("$SCRIPT_DIR/gpu_detect.sh")

CANDIDATE_LINE=""
while IFS= read -r line; do
    if [[ "$line" == CANDIDATE_BDF=* ]]; then
        CANDIDATE_LINE="$line"
    fi
done <<< "$SCAN_OUT"

if [[ -z "$CANDIDATE_LINE" ]]; then
    echo "[!] SAFETY BLOCK: Internal re-scan found no valid isolatable GPU. Aborting GRUB setup."
    exit 1
fi

DETECTED_BDF=$(echo "$CANDIDATE_LINE" | sed -n 's/.*CANDIDATE_BDF=\([^ ]*\).*/\1/p')
DETECTED_IDS=$(echo "$CANDIDATE_LINE" | sed -n 's/.*CANDIDATE_IDS=\([^ ]*\).*/\1/p')

if [[ -z "$DETECTED_BDF" ]] || [[ -z "$DETECTED_IDS" ]]; then
    echo "[!] ERROR: Could not parse verified GPU IDs. Aborting."
    exit 1
fi

if [[ -n "$EXPECTED_BDF" ]] && [[ "$EXPECTED_BDF" != "$DETECTED_BDF" ]]; then
    echo "[!] SAFETY BLOCK: Candidate BDF changed since GUI scan ($EXPECTED_BDF != $DETECTED_BDF)! Aborting."
    exit 1
fi

if [[ -n "$EXPECTED_IDS" ]] && [[ "$EXPECTED_IDS" != "$DETECTED_IDS" ]]; then
    echo "[!] SAFETY BLOCK: Candidate PCI IDs changed since GUI scan ($EXPECTED_IDS != $DETECTED_IDS)! Aborting."
    exit 1
fi

CPU_VENDOR=$(awk -F: '/vendor_id/ {print $2; exit}' /proc/cpuinfo | tr -d ' ')
if [[ "$CPU_VENDOR" == "GenuineIntel" ]]; then
    IOMMU_FLAG="intel_iommu=on"
elif [[ "$CPU_VENDOR" == "AuthenticAMD" ]]; then
    IOMMU_FLAG="amd_iommu=on"
else
    echo "[!] ERROR: Unknown CPU vendor ($CPU_VENDOR). Cannot determine IOMMU parameter."
    exit 1
fi

GRUB_FILE="/etc/default/grub"
if [[ ! -f "$GRUB_FILE" ]]; then
    echo "[!] ERROR: $GRUB_FILE not found."
    exit 1
fi

detect_grub_cfg() {
    if [[ -f /boot/grub2/grub.cfg ]]; then
        echo "/boot/grub2/grub.cfg"
    elif [[ -f /boot/efi/EFI/fedora/grub.cfg ]]; then
        echo "/boot/efi/EFI/fedora/grub.cfg"
    else
        echo ""
    fi
}

GRUB_CFG=$(detect_grub_cfg)
if [[ -z "$GRUB_CFG" ]]; then
    echo "[!] ERROR: Could not locate active grub.cfg."
    exit 1
fi

# 1. Persistent original backup (never overwritten if it exists)
STATE_DIR="/var/lib/wise-linux"
ORIG_BACKUP="${STATE_DIR}/grub.default.orig"
mkdir -p "$STATE_DIR"
chmod 700 "$STATE_DIR"

if [[ ! -f "$ORIG_BACKUP" ]]; then
    cp -pf "$GRUB_FILE" "$ORIG_BACKUP"
    echo "[*] Saved pristine original GRUB config to $ORIG_BACKUP"
fi

RUN_BACKUP="/tmp/wise_grub.run.bak.$$"
cp -pf "$GRUB_FILE" "$RUN_BACKUP"

rollback() {
    echo "[!] Error detected during GRUB configuration! Rolling back..."
    if [[ -f "$RUN_BACKUP" ]]; then
        cp -pf "$RUN_BACKUP" "$GRUB_FILE"
        rm -f "$RUN_BACKUP"
    fi
    if command -v grubby >/dev/null 2>&1; then
        grubby --update-kernel=ALL --remove-args="rd.driver.pre=vfio-pci vfio-pci.ids=${DETECTED_IDS}" >/dev/null 2>&1 || true
    fi
    grub2-mkconfig -o "$GRUB_CFG" >/dev/null 2>&1 || true
    exit 1
}
trap rollback ERR

# Clean old VFIO flags from /etc/default/grub to prevent duplicates
sed -i 's/ intel_iommu=on//g; s/ amd_iommu=on//g; s/ iommu=pt//g; s/ rd.driver.pre=vfio-pci//g' "$GRUB_FILE"
sed -i 's/ vfio-pci\.ids=[0-9a-fA-F:,]*//g' "$GRUB_FILE"

VFIO_ARGS="${IOMMU_FLAG} iommu=pt rd.driver.pre=vfio-pci vfio-pci.ids=${DETECTED_IDS}"
sed -i "s/GRUB_CMDLINE_LINUX=\"/GRUB_CMDLINE_LINUX=\"${VFIO_ARGS} /" "$GRUB_FILE"

if ! grep -q "vfio-pci.ids=${DETECTED_IDS}" "$GRUB_FILE"; then
    echo "[!] Verification failed: vfio-pci.ids was not written to $GRUB_FILE."
    false
fi

# Update Fedora BLS entries directly via grubby
if command -v grubby >/dev/null 2>&1; then
    echo "[*] Updating Fedora BLS boot entries via grubby..."
    OLD_VFIO_ARG=$(grubby --info=DEFAULT 2>/dev/null | tr ' "' '\n' | grep "^vfio-pci.ids=" || true)
    if [[ -n "$OLD_VFIO_ARG" ]]; then
        grubby --update-kernel=ALL --remove-args="$OLD_VFIO_ARG"
    fi
    grubby --update-kernel=ALL --remove-args="intel_iommu=on amd_iommu=on iommu=pt rd.driver.pre=vfio-pci"
    grubby --update-kernel=ALL --args="${VFIO_ARGS}"
fi

echo "[*] Generating updated GRUB configuration at $GRUB_CFG..."
grub2-mkconfig -o "$GRUB_CFG"

# Verify active bootloader configuration contains vfio-pci.ids
VERIFIED_OUTPUT=0
if command -v grubby >/dev/null 2>&1 && grubby --info=DEFAULT 2>/dev/null | grep -q "vfio-pci.ids=${DETECTED_IDS}"; then
    VERIFIED_OUTPUT=1
elif [[ -d /boot/loader/entries ]] && grep -rq "vfio-pci.ids=${DETECTED_IDS}" /boot/loader/entries/ 2>/dev/null; then
    VERIFIED_OUTPUT=1
elif grep -q "vfio-pci.ids=${DETECTED_IDS}" "$GRUB_CFG" 2>/dev/null; then
    VERIFIED_OUTPUT=1
fi

if [[ "$VERIFIED_OUTPUT" -ne 1 ]]; then
    echo "[!] Verification failed: Boot entries do not contain vfio-pci.ids=${DETECTED_IDS}."
    false
fi

rm -f "$RUN_BACKUP"
echo "[+] SUCCESS: GRUB & BLS configured and verified for GPU $DETECTED_BDF ($DETECTED_IDS)."