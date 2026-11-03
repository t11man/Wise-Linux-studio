#!/bin/bash
# Wise Linux - Complete Hardened VM Builder (Supports Auto & Manual RAM/Disk)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
WIN_ISO="${1:-}"
MODE="${2:---build}"        # "--dry-run" or "--build"
USER_RAM_GB="${3:-auto}"    # "auto" or integer GB
USER_DISK_GB="${4:-auto}"   # "auto" or integer GB

if [ -z "$WIN_ISO" ] || [ ! -f "$WIN_ISO" ]; then
    echo "[!] Error: Valid Windows ISO file path is required as argument 1."
    exit 1
fi

VIRTIO_ISO="${SCRIPT_DIR}/virtio-win.iso"
DEBLOAT_ISO="${SCRIPT_DIR}/wise_debloat.iso"
VM_NAME="WiseGhost_Win11"
DISK_PATH="/var/lib/libvirt/images/${VM_NAME}.qcow2"
SAFE_ISO_DIR="/var/lib/libvirt/wise_isos"
VM_BUILD_STARTED=0

cleanup_on_error() {
    echo "[!] Error detected! Checking rollback state..."
    if [ "$VM_BUILD_STARTED" -eq 1 ]; then
        echo "[*] Rolling back partially created VM from this run..."
        virsh destroy "$VM_NAME" 2>/dev/null || true
        virsh undefine "$VM_NAME" --nvram 2>/dev/null || true
        rm -f "$DISK_PATH" 2>/dev/null || true
    fi
    exit 1
}
trap cleanup_on_error ERR

# 1. Generate Zero-Touch ISO
"${SCRIPT_DIR}/create_debloat_iso.sh"

# 2. Check Host Hardware Resources
TOTAL_RAM_MB=$(free -m | awk '/^Mem:/{print $2}')
FREE_DISK_GB=$(df -BG /var/lib/libvirt/images 2>/dev/null | awk 'NR==2 {gsub("G","",$4); print $4}' || df -BG / | awk 'NR==2 {gsub("G","",$4); print $4}')

if [ "$USER_RAM_GB" = "auto" ]; then
    VM_RAM_MB=$(( TOTAL_RAM_MB * 50 / 100 ))
else
    if ! [[ "$USER_RAM_GB" =~ ^[0-9]+$ ]] || [ "$USER_RAM_GB" -lt 4 ]; then
        echo "[!] Invalid RAM value (${USER_RAM_GB}GB). Minimum for Windows 11 is 4GB."
        exit 1
    fi
    VM_RAM_MB=$(( USER_RAM_GB * 1024 ))
fi

if [ "$USER_DISK_GB" = "auto" ]; then
    DISK_SIZE="60"
else
    if ! [[ "$USER_DISK_GB" =~ ^[0-9]+$ ]] || [ "$USER_DISK_GB" -lt 40 ]; then
        echo "[!] Invalid Disk size (${USER_DISK_GB}GB). Minimum is 40GB."
        exit 1
    fi
    DISK_SIZE="$USER_DISK_GB"
fi

echo "[*] Host Status : ${TOTAL_RAM_MB}MB Total RAM | ${FREE_DISK_GB}GB Free Disk"
echo "[*] VM Target   : ${VM_RAM_MB}MB RAM | ${DISK_SIZE}GB Thin-Provisioned Disk (sparse=yes)"

if [ "$MODE" = "--dry-run" ]; then
    echo "[+] DEV MODE: Scripts, ISOs, and Custom/Auto Resource logic verified safely!"
    exit 0
fi

# 3. Hardened Host Safety Guards
if [ "$TOTAL_RAM_MB" -lt 11500 ]; then
    echo "[!] SAFETY BLOCK: Host has less than 12GB RAM (${TOTAL_RAM_MB}MB)."
    echo "[!] Blocking VM launch to protect Fedora from freezing on this laptop!"
    exit 1
fi

MAX_SAFE_VM_RAM=$(( TOTAL_RAM_MB - 4500 ))
if [ "$VM_RAM_MB" -gt "$MAX_SAFE_VM_RAM" ]; then
    echo "[!] SAFETY BLOCK: Requested ${VM_RAM_MB}MB RAM leaves less than 4.5GB for Fedora Host!"
    echo "[!] Maximum safe VM RAM on this machine is $(( MAX_SAFE_VM_RAM / 1024 ))GB."
    exit 1
fi

if [ "$FREE_DISK_GB" -lt 25 ]; then
    echo "[!] SAFETY BLOCK: Less than 25GB free physical disk space (${FREE_DISK_GB}GB)."
    exit 1
fi

# 4. Safe ISO Staging
echo "[*] Preparing safe ISO links in $SAFE_ISO_DIR..."
mkdir -p "$SAFE_ISO_DIR"
cp -f "$VIRTIO_ISO" "$SAFE_ISO_DIR/virtio-win.iso"
cp -f "$DEBLOAT_ISO" "$SAFE_ISO_DIR/wise_debloat.iso"
ln -sf "$WIN_ISO" "$SAFE_ISO_DIR/win11.iso"
chown -R qemu:qemu "$SAFE_ISO_DIR" 2>/dev/null || true
chcon -R -t virt_content_t "$SAFE_ISO_DIR" 2>/dev/null || true

# 5. Host SMBIOS Identity
HOST_VENDOR=$(cat /sys/class/dmi/id/sys_vendor 2>/dev/null | tr -cd '[:alnum:] ._-' || echo "ASUS")
HOST_PRODUCT=$(cat /sys/class/dmi/id/product_name 2>/dev/null | tr -cd '[:alnum:] ._-' || echo "System")
HOST_BIOS_VENDOR=$(cat /sys/class/dmi/id/bios_vendor 2>/dev/null | tr -cd '[:alnum:] ._-' || echo "AMI")
HOST_BIOS_VERSION=$(cat /sys/class/dmi/id/bios_version 2>/dev/null | tr -cd '[:alnum:] ._-' || echo "1.0")

TOTAL_CORES=$(nproc)
VM_CORES=$(( TOTAL_CORES * 50 / 100 ))
[ "$VM_CORES" -lt 2 ] && VM_CORES=2

systemctl start libvirtd

VM_BUILD_STARTED=1
if virsh dominfo "$VM_NAME" >/dev/null 2>&1; then
    virsh destroy "$VM_NAME" 2>/dev/null || true
    virsh undefine "$VM_NAME" --nvram 2>/dev/null || true
fi

# 6. Build VM
echo "[*] Building $VM_NAME..."
virt-install \
    --name "$VM_NAME" \
    --ram "$VM_RAM_MB" \
    --vcpus "$VM_CORES" \
    --cpu host-passthrough,kvm_hidden=on,feature.hypervisor.policy=disable \
    --sysinfo bios.vendor="$HOST_BIOS_VENDOR",bios.version="$HOST_BIOS_VERSION",system.manufacturer="$HOST_VENDOR",system.product="$HOST_PRODUCT" \
    --os-variant win11 \
    --machine q35 \
    --boot uefi,cdrom,hd,bootmenu.enable=no,firmware.feature0.name=secure-boot,firmware.feature0.enabled=yes \
    --tpm backend.type=emulator,backend.version=2.0,model=tpm-tis \
    --disk path="$DISK_PATH",size="$DISK_SIZE",bus=virtio,format=qcow2,cache=none,sparse=yes \
    --cdrom "$SAFE_ISO_DIR/win11.iso" \
    --disk path="$SAFE_ISO_DIR/virtio-win.iso",device=cdrom \
    --disk path="$SAFE_ISO_DIR/wise_debloat.iso",device=cdrom \
    --network network=default,model=virtio \
    --graphics spice \
    --video qxl \
    --events on_reboot=restart \
    --noautoconsole

echo "[+] SUCCESS: $VM_NAME built safely!"