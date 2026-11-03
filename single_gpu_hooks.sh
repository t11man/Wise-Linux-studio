#!/bin/bash
# Wise Linux - Complete Safe Single-GPU Passthrough Hook Installer
set -euo pipefail

# Block if primary display is driven by Integrated GPU on root bus 0000:00:02.0
if [ -e "/sys/bus/pci/devices/0000:00:02.0/boot_vga" ] && [ "$(cat /sys/bus/pci/devices/0000:00:02.0/boot_vga)" = "1" ]; then
    echo "[!] SAFETY BLOCK: Primary display is driven by Integrated GPU (0000:00:02.0)."
    echo "[!] Single-GPU passthrough requires a dedicated discrete GPU!"
    exit 1
fi

mkdir -p /etc/libvirt/hooks

cat << 'EOF' > /etc/libvirt/hooks/qemu
#!/bin/bash
GUEST_NAME="$1"
HOOK_NAME="$2"

recover_host_display() {
    modprobe -r vfio-pci 2>/dev/null || true
    modprobe nvidia_drm nvidia_modeset nvidia amdgpu i915 xe 2>/dev/null || true
    echo 1 > /sys/class/vtconsole/vtcon0/bind 2>/dev/null || true
    echo 1 > /sys/class/vtconsole/vtcon1/bind 2>/dev/null || true
    echo efi-framebuffer.0 > /sys/bus/platform/drivers/efi-framebuffer/bind 2>/dev/null || true
    systemctl start display-manager.service 2>/dev/null || true
}

if [ "$GUEST_NAME" = "WiseGhost_Win11" ]; then
    if [ "$HOOK_NAME" = "prepare" ]; then
        trap recover_host_display ERR
        systemctl stop display-manager.service
        echo 0 > /sys/class/vtconsole/vtcon0/bind 2>/dev/null || true
        echo 0 > /sys/class/vtconsole/vtcon1/bind 2>/dev/null || true
        echo efi-framebuffer.0 > /sys/bus/platform/drivers/efi-framebuffer/unbind 2>/dev/null || true
        sleep 2
        modprobe -r nvidia_drm nvidia_modeset nvidia_uvm nvidia amdgpu nouveau i915 xe 2>/dev/null || true
        modprobe vfio-pci
    elif [ "$HOOK_NAME" = "release" ]; then
        recover_host_display
    fi
fi
EOF

chmod +x /etc/libvirt/hooks/qemu
systemctl restart libvirtd

echo "[+] SUCCESS: Single-GPU dynamic hooks installed safely!"