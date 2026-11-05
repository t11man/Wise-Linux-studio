#!/bin/bash
# Wise Linux - Hardened Initramfs VFIO Builder with Self-Verification & Rollback
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
EXPECTED_BDF="${1:-}"
EXPECTED_IDS="${2:-}"

echo "[*] Re-verifying GPU topology before writing modprobe/dracut rules..."
SCAN_OUT=$("$SCRIPT_DIR/gpu_detect.sh")

CANDIDATE_LINE=""
while IFS= read -r line; do
    if [[ "$line" == CANDIDATE_BDF=* ]]; then
        CANDIDATE_LINE="$line"
    fi
done <<< "$SCAN_OUT"

if [[ -z "$CANDIDATE_LINE" ]]; then
    echo "[!] SAFETY BLOCK: Internal re-scan found no valid isolatable GPU. Aborting initramfs setup."
    exit 1
fi

DETECTED_BDF=$(echo "$CANDIDATE_LINE" | sed -n 's/.*CANDIDATE_BDF=\([^ ]*\).*/\1/p')
DETECTED_IDS=$(echo "$CANDIDATE_LINE" | sed -n 's/.*CANDIDATE_IDS=\([^ ]*\).*/\1/p')

if [[ -z "$DETECTED_BDF" ]] || [[ -z "$DETECTED_IDS" ]]; then
    echo "[!] ERROR: Could not parse verified GPU IDs. Aborting."
    exit 1
fi

if ! [[ "$DETECTED_IDS" =~ ^[0-9a-fA-F:,]+$ ]]; then
    echo "[!] ERROR: Unexpected characters in the detected PCI IDs. Aborting."
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

if ! command -v dracut >/dev/null 2>&1; then
    echo "[!] ERROR: dracut was not found. This step supports Fedora (dracut) only."
    exit 1
fi

MODPROBE_CONF="/etc/modprobe.d/wise_linux_vfio.conf"
DRACUT_CONF="/etc/dracut.conf.d/wise_linux_vfio.conf"
BACKUP_DIR=$(mktemp -d /tmp/wise_initramfs.XXXXXX)
HAD_MODPROBE=0
HAD_DRACUT=0
DRACUT_RAN=0

cleanup() {
    rm -rf "$BACKUP_DIR"
}
trap cleanup EXIT

if [[ -f "$MODPROBE_CONF" ]]; then
    cp -pf "$MODPROBE_CONF" "$BACKUP_DIR/modprobe.conf"
    HAD_MODPROBE=1
fi
if [[ -f "$DRACUT_CONF" ]]; then
    cp -pf "$DRACUT_CONF" "$BACKUP_DIR/dracut.conf"
    HAD_DRACUT=1
fi

rollback() {
    trap - ERR
    echo "[!] Error during initramfs setup! Rolling back configuration changes..."
    if [[ "$HAD_MODPROBE" -eq 1 ]]; then
        cp -pf "$BACKUP_DIR/modprobe.conf" "$MODPROBE_CONF"
    else
        rm -f "$MODPROBE_CONF"
    fi
    if [[ "$HAD_DRACUT" -eq 1 ]]; then
        cp -pf "$BACKUP_DIR/dracut.conf" "$DRACUT_CONF"
    else
        rm -f "$DRACUT_CONF"
    fi
    if [[ "$DRACUT_RAN" -eq 1 ]]; then
        echo "[*] Rebuilding the initramfs without the Wise Linux changes..."
        dracut -f >/dev/null 2>&1 || true
    fi
    exit 1
}
trap rollback ERR

mkdir -p "$(dirname "$MODPROBE_CONF")" "$(dirname "$DRACUT_CONF")"

# 1. Tell vfio-pci which devices to claim
echo "options vfio-pci ids=${DETECTED_IDS}" > "$MODPROBE_CONF"
chmod 644 "$MODPROBE_CONF"

# 2. Make sure the VFIO drivers are INSIDE the initramfs (otherwise the GPU driver may grab the card first)
echo 'add_drivers+=" vfio vfio_iommu_type1 vfio_pci "' > "$DRACUT_CONF"
chmod 644 "$DRACUT_CONF"

if ! grep -q "^options vfio-pci ids=${DETECTED_IDS}$" "$MODPROBE_CONF"; then
    echo "[!] Verification failed: $MODPROBE_CONF content mismatch."
    false
fi
if ! grep -q 'vfio_pci' "$DRACUT_CONF"; then
    echo "[!] Verification failed: $DRACUT_CONF content mismatch."
    false
fi

echo "[*] Rebuilding initramfs via dracut (this may take a moment)..."
DRACUT_RAN=1
dracut -f

# 3. Verify the new initramfs really contains the VFIO modules
MODULE_PATH=$(modinfo -F filename vfio-pci 2>/dev/null || true)
if [[ "$MODULE_PATH" == "(builtin)" ]]; then
    echo "[*] vfio-pci is built into this kernel; no module check needed."
else
    INITRD_LIST=$(lsinitrd 2>/dev/null || true)
    if [[ -z "$INITRD_LIST" ]]; then
        echo "[!] WARNING: Could not read the initramfs contents, so the VFIO modules could not be verified."
    elif ! grep -qE 'vfio[-_]pci\.ko' <<< "$INITRD_LIST"; then
        echo "[!] Verification failed: the new initramfs does not contain the vfio-pci module."
        false
    else
        echo "[+] Verified: the initramfs contains the VFIO modules."
    fi
fi

echo "[+] SUCCESS: initramfs rebuilt for $DETECTED_BDF ($DETECTED_IDS)."
echo "[!] Reboot is required. Only the CURRENT kernel's initramfs was rebuilt: if the PC does not boot properly, pick an older kernel in the GRUB menu."