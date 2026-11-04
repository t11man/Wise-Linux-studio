#!/bin/bash
# Wise Linux - Ultimate System Rescue & Restore Shield
set -euo pipefail

VM_NAME="WiseGhost_Win11"
STATE_DIR="/var/lib/wise-linux"
ORIG_BACKUP="${STATE_DIR}/grub.default.orig"
BEFORE_RESTORE="${STATE_DIR}/grub.default.before-restore"
GRUB_FILE="/etc/default/grub"
HOOK_FILE="/etc/libvirt/hooks/qemu"

REAL_USER="${PKEXEC_UID:+$(id -nu "$PKEXEC_UID")}"
REAL_USER="${REAL_USER:-${SUDO_USER:-${USER:-root}}}"
USER_HOME=$(getent passwd "$REAL_USER" | cut -d: -f6 || true)

# --- Helpers -----------------------------------------------------------------
# Arguments Wise Linux may add to the kernel command line (plain text and regex forms)
PLAIN_TOKENS=('intel_iommu=on' 'amd_iommu=on' 'iommu=pt' 'rd.driver.pre=vfio-pci')
REGEX_TOKENS=('intel_iommu=on' 'amd_iommu=on' 'iommu=pt' 'rd\.driver\.pre=vfio-pci')
IDS_REGEX='vfio-pci\.ids=[0-9a-fA-F:,]+'

# True if the ORIGINAL (pre-Wise) GRUB config already contained this argument.
# Such arguments belong to the user and are never removed.
orig_has() {
    [[ -f "$ORIG_BACKUP" ]] && grep -qE "([\" ])$1([\" ])" "$ORIG_BACKUP"
}

# Remove only the arguments that Wise Linux added (two passes also catch duplicates)
clean_flags() {
    local file="$1" pass i
    for pass in 1 2; do
        for i in "${!REGEX_TOKENS[@]}"; do
            if ! orig_has "${REGEX_TOKENS[$i]}"; then
                sed -i -E "s/([\" ])${REGEX_TOKENS[$i]}([\" ])/\1\2/g" "$file"
            fi
        done
        if ! orig_has "$IDS_REGEX"; then
            sed -i -E "s/([\" ])${IDS_REGEX}([\" ])/\1\2/g" "$file"
        fi
    done
}
# --- end helpers ---------------------------------------------------------------

echo "[*] Wise Shield: Initiating full system safety check & restoration..."

# 1. Stop the VM cleanly (a forced power-off is only the last resort)
vm_state() {
    virsh --connect qemu:///system domstate "$VM_NAME" 2>/dev/null | head -n 1 || true
}

state=$(vm_state)
if [[ "$state" == "paused" ]]; then
    virsh --connect qemu:///system resume "$VM_NAME" >/dev/null 2>&1 || true
    state=$(vm_state)
fi
if [[ "$state" == "running" || "$state" == "in shutdown" ]]; then
    echo "[*] Asking Windows to shut down cleanly (waiting up to 60 seconds)..."
    virsh --connect qemu:///system shutdown "$VM_NAME" >/dev/null 2>&1 || true
    for _ in $(seq 1 30); do
        state=$(vm_state)
        if [[ "$state" == "shut off" ]]; then
            break
        fi
        sleep 2
    done
    if [[ "$state" != "shut off" ]]; then
        echo "[!] Windows did not shut down in time. Forcing power off."
        virsh --connect qemu:///system destroy "$VM_NAME" >/dev/null 2>&1 || true
    fi
fi

# 2. Remove only the ACL entry that could have been granted to the qemu user
if [[ -n "$USER_HOME" && -d "$USER_HOME" && "$REAL_USER" != "root" ]]; then
    setfacl -x u:qemu "$USER_HOME" 2>/dev/null || true
fi

# 3. Remove GPU isolation configs and hooks
echo "[*] Removing any GPU isolation configs and hooks..."
rm -f /tmp/wise_vfio.conf
rm -f /etc/modprobe.d/wise_linux_vfio.conf
rm -f /etc/dracut.conf.d/wise_linux_vfio.conf
if [[ -f "$HOOK_FILE" ]]; then
    if grep -qi "wise" "$HOOK_FILE"; then
        rm -f "$HOOK_FILE"
        echo "[*] Removed the Wise Linux libvirt hook."
    else
        echo "[*] Found a libvirt hook that does not belong to Wise Linux. Leaving it untouched."
    fi
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
GRUB_CHANGED=0

# 4. Clean /etc/default/grub (keeps every other setting, including later changes by the user)
if [[ -f "$GRUB_FILE" ]]; then
    if grep -qE 'vfio-pci|iommu' "$GRUB_FILE"; then
        mkdir -p "$STATE_DIR"
        chmod 700 "$STATE_DIR"
        cp -pf "$GRUB_FILE" "$BEFORE_RESTORE"
        echo "[*] Removing Wise Linux arguments from $GRUB_FILE (a copy was saved to $BEFORE_RESTORE)..."
        clean_flags "$GRUB_FILE"
        GRUB_CHANGED=1
    fi
elif [[ -f "$ORIG_BACKUP" ]]; then
    echo "[*] $GRUB_FILE is missing. Restoring it from the original backup ($ORIG_BACKUP)..."
    cp -pf "$ORIG_BACKUP" "$GRUB_FILE"
    GRUB_CHANGED=1
fi

# 5. Clean Fedora BLS kernel args via grubby (never touches arguments that existed before Wise Linux)
if command -v grubby >/dev/null 2>&1; then
    echo "[*] Cleaning VFIO and IOMMU parameters from Fedora BLS entries..."
    remove_list=()
    for i in "${!PLAIN_TOKENS[@]}"; do
        if ! orig_has "${REGEX_TOKENS[$i]}"; then
            remove_list+=("${PLAIN_TOKENS[$i]}")
        fi
    done
    if (( ${#remove_list[@]} > 0 )); then
        grubby --update-kernel=ALL --remove-args="${remove_list[*]}" || true
    fi
    if ! orig_has "$IDS_REGEX"; then
        for vfio_arg in $(grubby --info=ALL 2>/dev/null | tr ' "' '\n' | grep "^vfio-pci.ids=" | sort -u || true); do
            grubby --update-kernel=ALL --remove-args="$vfio_arg" || true
        done
    fi
fi

# 6. Regenerate GRUB and verify
if [[ "$GRUB_CHANGED" -eq 1 ]] && [[ -n "$GRUB_CFG" ]]; then
    echo "[*] Regenerating clean GRUB configuration at $GRUB_CFG..."
    grub2-mkconfig -o "$GRUB_CFG"
    if ! orig_has "$IDS_REGEX" && grep -q "vfio-pci.ids=" "$GRUB_CFG" 2>/dev/null; then
        echo "[!] WARNING: vfio-pci.ids still detected in $GRUB_CFG after regeneration!"
        exit 1
    fi
fi

echo "[*] Rebuilding clean initramfs..."
dracut -f

echo "[+] Restore finished. Wise Linux configuration was removed."
echo "[!] REBOOT NOW to release the GPU (it stays reserved for the VM until you restart) and finish the restore."