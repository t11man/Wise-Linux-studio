#!/bin/bash
# Wise Linux - Add IOMMU Kernel Parameters Only (Fedora BLS & GRUB Hardened)
set -euo pipefail

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

# Temporary snapshot for immediate rollback if this run fails
RUN_BACKUP="/tmp/wise_grub_iommu.run.bak.$$"
cp -pf "$GRUB_FILE" "$RUN_BACKUP"

rollback() {
    echo "[!] Error detected during IOMMU configuration! Rolling back..."
    if [[ -f "$RUN_BACKUP" ]]; then
        cp -pf "$RUN_BACKUP" "$GRUB_FILE"
        rm -f "$RUN_BACKUP"
    fi
    if command -v grubby >/dev/null 2>&1; then
        grubby --update-kernel=ALL --remove-args="intel_iommu=on amd_iommu=on iommu=pt" >/dev/null 2>&1 || true
    fi
    grub2-mkconfig -o "$GRUB_CFG" >/dev/null 2>&1 || true
    exit 1
}
trap rollback ERR

# Clean existing IOMMU flags to prevent duplicates
sed -i 's/ intel_iommu=on//g; s/ amd_iommu=on//g; s/ iommu=pt//g' "$GRUB_FILE"

# Inject IOMMU flag and iommu=pt into /etc/default/grub
ARGS="${IOMMU_FLAG} iommu=pt"
sed -i "s/GRUB_CMDLINE_LINUX=\"/GRUB_CMDLINE_LINUX=\"${ARGS} /" "$GRUB_FILE"

if ! grep -q "$IOMMU_FLAG" "$GRUB_FILE"; then
    echo "[!] Verification failed: $IOMMU_FLAG was not written to $GRUB_FILE."
    false
fi

# Update Fedora BLS entries directly via grubby (guarantees active boot entries get updated)
if command -v grubby >/dev/null 2>&1; then
    echo "[*] Updating Fedora BLS boot entries via grubby..."
    grubby --update-kernel=ALL --remove-args="intel_iommu=on amd_iommu=on iommu=pt"
    grubby --update-kernel=ALL --args="${ARGS}"
fi

echo "[*] Generating updated GRUB configuration at $GRUB_CFG..."
grub2-mkconfig -o "$GRUB_CFG"

# Verify active bootloader configuration contains the flag
VERIFIED=0
if command -v grubby >/dev/null 2>&1 && grubby --info=DEFAULT 2>/dev/null | grep -q "$IOMMU_FLAG"; then
    VERIFIED=1
elif [[ -d /boot/loader/entries ]] && grep -rq "$IOMMU_FLAG" /boot/loader/entries/ 2>/dev/null; then
    VERIFIED=1
elif grep -q "$IOMMU_FLAG" "$GRUB_CFG" 2>/dev/null; then
    VERIFIED=1
fi

if [[ "$VERIFIED" -ne 1 ]]; then
    echo "[!] Verification failed: Active boot entries do not contain $IOMMU_FLAG."
    false
fi

rm -f "$RUN_BACKUP"
echo "[+] SUCCESS: IOMMU kernel parameter enabled ($IOMMU_FLAG). Please REBOOT your system."