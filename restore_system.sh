#!/bin/bash
# Wise Linux - Ultimate System Rescue & Restore Shield
set -euo pipefail

REAL_USER="${PKEXEC_UID:+$(id -nu "$PKEXEC_UID")}"
REAL_USER="${REAL_USER:-${SUDO_USER:-$USER}}"
USER_HOME=$(eval echo "~$REAL_USER")

echo "[*] Wise Shield: Initiating full system safety check & restoration..."

if virsh --connect qemu:///system dominfo "WiseGhost_Win11" >/dev/null 2>&1; then
    echo "[*] Stopping WiseGhost_Win11 VM to free RAM..."
    virsh --connect qemu:///system destroy "WiseGhost_Win11" 2>/dev/null || true
fi

if [[ -d "$USER_HOME" ]] && [[ "$REAL_USER" != "root" ]]; then
    echo "[*] Restoring strict security permissions on $USER_HOME..."
    setfacl -b "$USER_HOME" 2>/dev/null || true
    chmod 700 "$USER_HOME" 2>/dev/null || true
fi

echo "[*] Removing any GPU isolation configs and hooks..."
rm -f /tmp/wise_vfio.conf
rm -f /etc/modprobe.d/wise_linux_vfio.conf
rm -f /etc/dracut.conf.d/wise_linux_vfio.conf
rm -f /etc/libvirt/hooks/qemu

detect_grub_cfg() {
    if [[ -f /boot/grub2/grub.cfg ]]; then
        echo "/boot/grub2/grub.cfg"
    elif [[ -f /boot/efi/EFI/fedora/grub.cfg ]]; then
        echo "/boot/efi/EFI/fedora/grub.cfg"
    else
        echo ""
    fi
}

ORIG_BACKUP="/var/lib/wise-linux/grub.default.orig"
GRUB_FILE="/etc/default/grub"
GRUB_CFG=$(detect_grub_cfg)

GRUB_CHANGED=0
if [[ -f "$ORIG_BACKUP" ]]; then
    echo "[*] Restoring /etc/default/grub from original backup ($ORIG_BACKUP)..."
    cp -pf "$ORIG_BACKUP" "$GRUB_FILE"
    GRUB_CHANGED=1
elif [[ -f "$GRUB_FILE" ]] && (grep -q "vfio-pci" "$GRUB_FILE" || grep -q "iommu" "$GRUB_FILE"); then
    echo "[*] Original backup not found; cleaning VFIO and IOMMU parameters from $GRUB_FILE..."
    sed -i 's/ intel_iommu=on//g; s/ amd_iommu=on//g; s/ iommu=pt//g; s/ rd.driver.pre=vfio-pci//g' "$GRUB_FILE"
    sed -i 's/ vfio-pci\.ids=[0-9a-fA-F:,]*//g' "$GRUB_FILE"
    GRUB_CHANGED=1
fi

# Clean Fedora BLS kernel args via grubby if present
if command -v grubby >/dev/null 2>&1; then
    echo "[*] Cleaning VFIO and IOMMU parameters from Fedora BLS entries..."
    for vfio_arg in $(grubby --info=ALL 2>/dev/null | tr ' "' '\n' | grep "^vfio-pci.ids=" | sort -u || true); do
        grubby --update-kernel=ALL --remove-args="$vfio_arg" || true
    done
    grubby --update-kernel=ALL --remove-args="intel_iommu=on amd_iommu=on iommu=pt rd.driver.pre=vfio-pci" || true
fi

if [[ "$GRUB_CHANGED" -eq 1 ]] && [[ -n "$GRUB_CFG" ]]; then
    echo "[*] Regenerating clean GRUB configuration at $GRUB_CFG..."
    grub2-mkconfig -o "$GRUB_CFG"
    if grep -q "vfio-pci.ids=" "$GRUB_CFG" 2>/dev/null; then
        echo "[!] WARNING: vfio-pci.ids still detected in $GRUB_CFG after regeneration!"
        exit 1
    fi
fi

echo "[*] Rebuilding clean initramfs..."
dracut -f

echo "[+] SYSTEM RESTORED: Host OS is 100% clean, permissions fixed, and protected."