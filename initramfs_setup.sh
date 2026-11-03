#!/bin/bash
# Wise Linux - Hardened Initramfs VFIO Builder with Self-Verification & Rollback
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
EXPECTED_BDF="${1:-}"
EXPECTED_IDS="${2:-}"

echo "[*] Re-verifying GPU topology before writing modprobe rules..."
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

if [[ -n "$EXPECTED_BDF" ]] && [[ "$EXPECTED_BDF" != "$DETECTED_BDF" ]]; then
    echo "[!] SAFETY BLOCK: Candidate BDF changed since GUI scan ($EXPECTED_BDF != $DETECTED_BDF)! Aborting."
    exit 1
fi

if [[ -n "$EXPECTED_IDS" ]] && [[ "$EXPECTED_IDS" != "$DETECTED_IDS" ]]; then
    echo "[!] SAFETY BLOCK: Candidate PCI IDs changed since GUI scan ($EXPECTED_IDS != $DETECTED_IDS)! Aborting."
    exit 1
fi

DEST_CONF="/etc/modprobe.d/wise_linux_vfio.conf"
BACKUP_CONF="/tmp/wise_modprobe.bak.$$"
HAD_PREVIOUS=0

if [[ -f "$DEST_CONF" ]]; then
    cp -pf "$DEST_CONF" "$BACKUP_CONF"
    HAD_PREVIOUS=1
fi

rollback() {
    echo "[!] Error during initramfs build! Rolling back /etc/modprobe.d changes..."
    if [[ "$HAD_PREVIOUS" -eq 1 ]] && [[ -f "$BACKUP_CONF" ]]; then
        cp -pf "$BACKUP_CONF" "$DEST_CONF"
        rm -f "$BACKUP_CONF"
    else
        rm -f "$DEST_CONF"
    fi
    exit 1
}
trap rollback ERR

echo "options vfio-pci ids=${DETECTED_IDS}" > "$DEST_CONF"
chmod 644 "$DEST_CONF"

# Verify written content
if ! grep -q "^options vfio-pci ids=${DETECTED_IDS}$" "$DEST_CONF"; then
    echo "[!] Verification failed: $DEST_CONF content mismatch."
    false
fi

echo "[*] Rebuilding initramfs via dracut (this may take a moment)..."
dracut -f

rm -f "$BACKUP_CONF"
echo "[+] SUCCESS: $DEST_CONF written and initramfs rebuilt for $DETECTED_BDF ($DETECTED_IDS)."