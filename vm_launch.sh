#!/bin/bash
# Wise Linux - VM Launcher
#   --normal        Start the VM with the virtual display (default)
#   --single-gpu    EXPERIMENTAL: close the Linux desktop and give your only (dedicated) GPU to Windows
#   --revert        Restore the normal VM configuration after a single-GPU session (always exits 0)
#   --revert-wait   Same, but waits until the VM has shut down first (used by the hook)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
HOOKS="${SCRIPT_DIR}/single_gpu_hooks.sh"
VM_NAME="WiseGhost_Win11"
STATE_DIR="/var/lib/wise-linux"
NORMAL_XML="${STATE_DIR}/${VM_NAME}.normal.xml"
ARMED_FILE="${STATE_DIR}/single_gpu.armed"
MODE="${1:---normal}"

if [[ $EUID -ne 0 ]]; then
    echo "[!] Root privileges required."
    exit 1
fi

virsh_cmd() {
    virsh --connect qemu:///system "$@"
}

domain_state() {
    virsh_cmd domstate "$VM_NAME" 2>/dev/null | head -n 1 || echo "missing"
}

# Put the VM definition back to its normal (virtual display) form
revert_config() {
    [[ -f "$NORMAL_XML" ]] || return 0
    local state
    state=$(domain_state)
    if [[ -z "$state" ]]; then
        state="missing"
    fi
    case "$state" in
        running|paused|"in shutdown")
            echo "[!] The VM is still running; cannot restore its normal configuration yet."
            return 1
            ;;
        missing)
            rm -f "$NORMAL_XML"
            return 0
            ;;
    esac
    echo "[*] Restoring the normal VM configuration (virtual display)..."
    virsh_cmd define "$NORMAL_XML" > /dev/null
    rm -f "$NORMAL_XML"
    return 0
}

# Create a single-GPU version of the VM XML: no virtual display, real GPU attached.
transform_xml() {
    local src="$1" dst="$2"
    shift 2
    python3 - "$src" "$dst" "$@" << 'PYEOF'
import sys
import xml.etree.ElementTree as ET

ET.register_namespace("qemu", "http://libvirt.org/schemas/domain/qemu/1.0")
ET.register_namespace("libosinfo", "http://libosinfo.org/xmlns/libvirt/domain/1.0")

src, dst, funcs = sys.argv[1], sys.argv[2], sys.argv[3:]
tree = ET.parse(src)
root = tree.getroot()
devices = root.find("devices")
if devices is None:
    sys.exit("No <devices> section in the VM XML")

for tag in ("graphics", "video"):
    for el in list(devices.findall(tag)):
        devices.remove(el)
for el in list(devices.findall("channel")):
    if el.get("type") == "spicevmc":
        devices.remove(el)
for el in list(devices.findall("redirdev")):
    if el.get("type") == "spicevmc":
        devices.remove(el)
for el in devices.findall("audio"):
    if el.get("type") == "spice":
        el.set("type", "none")

video = ET.SubElement(devices, "video")
ET.SubElement(video, "model", type="none")

existing = set()
for hd in devices.findall("hostdev"):
    addr = hd.find("./source/address")
    if hd.get("type") == "pci" and addr is not None:
        existing.add((addr.get("domain"), addr.get("bus"), addr.get("slot"), addr.get("function")))

for f in funcs:
    dom, bus, rest = f.split(":")
    slot, fn = rest.split(".")
    key = ("0x" + dom, "0x" + bus, "0x" + slot, "0x" + fn)
    if key in existing:
        continue
    hd = ET.SubElement(devices, "hostdev", mode="subsystem", type="pci", managed="yes")
    source = ET.SubElement(hd, "source")
    ET.SubElement(source, "address", domain=key[0], bus=key[1], slot=key[2], function=key[3])

tree.write(dst, encoding="unicode")
PYEOF
}

single_prepare() {
    local state check_out bdf dm funcs=() f tmp_xml

    state=$(domain_state)
    if [[ "$state" == "missing" || -z "$state" ]]; then
        echo "[!] The VM does not exist. Build it first with '5. Build Ghost VM'."
        return 1
    fi
    if [[ "$state" != "shut off" ]]; then
        echo "[!] The VM must be shut off before starting single-GPU mode (state: $state)."
        return 1
    fi

    if ! check_out=$("$HOOKS" --check); then
        echo "$check_out"
        return 1
    fi
    echo "$check_out" | grep -v '^SINGLE_GPU_OK' || true
    bdf=$(echo "$check_out" | sed -n 's/^SINGLE_GPU_OK BDF=\([^ ]*\) DM=.*/\1/p')
    dm=$(echo "$check_out" | sed -n 's/^SINGLE_GPU_OK BDF=[^ ]* DM=\(.*\)$/\1/p')
    if [[ -z "$bdf" || -z "$dm" ]]; then
        echo "[!] Could not read the single-GPU check result."
        return 1
    fi

    mkdir -p "$STATE_DIR"
    chmod 700 "$STATE_DIR"

    # Keep the normal definition so it can be restored; never overwrite an existing backup
    if [[ ! -f "$NORMAL_XML" ]]; then
        virsh_cmd dumpxml --inactive "$VM_NAME" > "$NORMAL_XML"
        chmod 600 "$NORMAL_XML"
    fi

    for f in /sys/bus/pci/devices/"${bdf%.*}".*; do
        if [[ -e "$f" ]]; then
            funcs+=("$(basename "$f")")
        fi
    done

    tmp_xml=$(mktemp /tmp/wise_single_gpu.XXXXXX.xml)
    if ! transform_xml "$NORMAL_XML" "$tmp_xml" "${funcs[@]}"; then
        rm -f "$tmp_xml"
        echo "[!] Could not prepare the single-GPU VM configuration."
        return 1
    fi
    virsh_cmd define "$tmp_xml" > /dev/null
    rm -f "$tmp_xml"

    "$HOOKS" --install "$bdf" "$dm" "${SCRIPT_DIR}/vm_launch.sh"
    touch "$ARMED_FILE"
    chmod 600 "$ARMED_FILE"

    # The hook is only picked up after the libvirt daemon restarts
    systemctl restart libvirtd 2>/dev/null || systemctl restart virtqemud 2>/dev/null || true
    return 0
}

case "$MODE" in
    --revert)
        revert_config || true
        exit 0
        ;;
    --revert-wait)
        for _ in $(seq 1 60); do
            state=$(domain_state)
            case "$state" in
                running|paused|"in shutdown") sleep 2 ;;
                *) break ;;
            esac
        done
        revert_config || true
        exit 0
        ;;
    --normal)
        state=$(domain_state)
        if [[ "$state" == "running" ]]; then
            echo "[*] The VM is already running."
            exit 0
        fi
        # Make sure a leftover single-GPU hook can never stop the desktop during a normal start
        "$HOOKS" --uninstall || true
        if ! revert_config; then
            exit 1
        fi
        echo "[*] Starting $VM_NAME..."
        virsh_cmd start "$VM_NAME"
        echo "[+] VM started."
        exit 0
        ;;
    --single-gpu)
        rm -f "$ARMED_FILE"
        if ! single_prepare; then
            echo "[!] Single-GPU preparation failed. Restoring the normal configuration..."
            "$HOOKS" --uninstall || true
            revert_config || true
            exit 1
        fi
        echo "[!] Your Linux desktop will close in a few seconds and the screen will go dark."
        echo "[!] Windows will use your GPU. Shut Windows down normally to return to Linux."
        systemd-run --no-block --collect --unit=wise-single-gpu-start \
            /bin/sh -c "sleep 4; virsh --connect qemu:///system start ${VM_NAME}" > /dev/null
        exit 0
        ;;
    *)
        echo "Usage: $0 [--normal | --single-gpu | --revert | --revert-wait]"
        exit 1
        ;;
esac