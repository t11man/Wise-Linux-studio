#!/bin/bash
# Wise Linux - Single-GPU Passthrough Helper
set -euo pipefail

VM_NAME="WiseGhost_Win11"
STATE_DIR="/var/lib/wise-linux"
CONF_FILE="${STATE_DIR}/single_gpu.conf"
STATE_FILE="${STATE_DIR}/single_gpu.state"
ARMED_FILE="${STATE_DIR}/single_gpu.armed"
HOOK_DIR="/etc/libvirt/hooks"
HOOK_FILE="${HOOK_DIR}/qemu"
MARKER="# WISE-LINUX-SINGLE-GPU-HOOK"

detect_display_manager() {
    local unit="" cand
    if [[ -L /etc/systemd/system/display-manager.service ]]; then
        unit=$(basename "$(readlink -f /etc/systemd/system/display-manager.service)")
    fi
    if [[ -z "$unit" ]]; then
        for cand in sddm.service gdm.service lightdm.service; do
            if systemctl is-active --quiet "$cand" 2>/dev/null; then
                unit="$cand"
                break
            fi
        done
    fi
    echo "$unit"
}

run_check() {
    local total=0 gpu_bdf="" dev cls

    for dev in /sys/bus/pci/devices/*; do
        [[ -e "$dev/class" ]] || continue
        cls=$(cat "$dev/class")
        if [[ "$cls" =~ ^0x030[02] ]]; then
            total=$((total + 1))
            gpu_bdf=$(basename "$dev")
        fi
    done

    if (( total != 1 )); then
        echo "[!] Single-GPU mode needs exactly one GPU in the system (found $total)."
        echo "[!] With an integrated GPU plus a dedicated GPU, use the Dual-GPU buttons (1-3) instead."
        return 1
    fi

    local dev_path="/sys/bus/pci/devices/${gpu_bdf}"
    local boot_vga
    boot_vga=$(cat "$dev_path/boot_vga" 2>/dev/null || echo "0")
    if [[ "$boot_vga" != "1" ]]; then
        echo "[!] The GPU ($gpu_bdf) is not the boot display GPU. Refusing."
        return 1
    fi

    if [[ ! -e "$dev_path/iommu_group" ]]; then
        echo "[!] IOMMU is not active for $gpu_bdf. Enable VT-d / AMD-Vi in BIOS and use '2a. Enable IOMMU' first."
        return 1
    fi

    # Only a DEDICATED (discrete) GPU is allowed. When in doubt, refuse.
    local vendor desc bus discrete=0
    vendor=$(cat "$dev_path/vendor")
    desc=$(lspci -s "$gpu_bdf" -nn 2>/dev/null | cut -d' ' -f2- || true)
    bus=$(echo "$gpu_bdf" | cut -d: -f2)

    local amd_discrete='Navi|Radeon RX|Radeon PRO|Radeon Pro|Radeon VII|Polaris|Ellesmere|Baffin|Lexa|Hawaii|Tonga|Fiji'
    local amd_integrated='Raphael|Phoenix|Rembrandt|Renoir|Cezanne|Barcelo|Lucienne|Picasso|Raven|Mendocino|Hawk|Strix|Granite|Radeon Graphics|Vega [0-9]+ Graphics'
    local intel_discrete='Arc|DG1|DG2|Battlemage|Alchemist'

    case "$vendor" in
        0x10de)
            discrete=1
            ;;
        0x8086)
            if [[ "$bus" != "00" ]] && [[ "$desc" =~ $intel_discrete ]]; then
                discrete=1
            fi
            ;;
        0x1002)
            if [[ "$desc" =~ $amd_discrete ]] && ! [[ "$desc" =~ $amd_integrated ]]; then
                discrete=1
            fi
            local vram_file="$dev_path/mem_info_vram_total" vram=0
            if (( discrete == 1 )) && [[ -r "$vram_file" ]]; then
                vram=$(cat "$vram_file" 2>/dev/null || echo "0")
                if (( vram > 0 && vram < 2147483648 )); then
                    discrete=0
                fi
            fi
            ;;
    esac

    if (( discrete != 1 )); then
        echo "[!] This GPU does not look like a dedicated (discrete) GPU: $desc"
        echo "[!] Integrated GPUs are never passed through. Refusing."
        return 1
    fi

    # Every PCI function in the GPU slot must have an active IOMMU group containing only this slot's functions and PCI bridges.
    local slot_prefix="${gpu_bdf%.*}" f g gb gc
    for f in /sys/bus/pci/devices/"${slot_prefix}".*; do
        [[ -e "$f" ]] || continue
        if [[ ! -e "$f/iommu_group" ]]; then
            echo "[!] IOMMU is not active for PCI function $(basename "$f"). Refusing."
            return 1
        fi
        for g in "$f/iommu_group/devices"/*; do
            [[ -e "$g" ]] || continue
            gb=$(basename "$g")
            if [[ "$gb" == "${slot_prefix}."* ]]; then
                continue
            fi
            gc=$(cat "$g/class" 2>/dev/null || echo "0x000000")
            if [[ "$gc" == 0x0604* ]]; then
                continue
            fi
            echo "[!] The GPU's IOMMU group also contains another device ($gb). Passing it through is unsafe. Refusing."
            return 1
        done
    done

    local dm
    dm=$(detect_display_manager)
    if [[ -z "$dm" ]]; then
        echo "[!] Could not detect your display manager (sddm/gdm/lightdm). Refusing."
        return 1
    fi

    echo "[+] Single-GPU mode available: $desc ($gpu_bdf), display manager: $dm"
    echo "SINGLE_GPU_OK BDF=${gpu_bdf} DM=${dm}"
    return 0
}

do_install() {
    local bdf="${1:-}" dm="${2:-}" launcher="${3:-}"

    if [[ $EUID -ne 0 ]]; then
        echo "[!] Root privileges required."
        return 1
    fi
    if ! [[ "$bdf" =~ ^[0-9a-f]{4}:[0-9a-f]{2}:[0-9a-f]{2}\.[0-7]$ ]]; then
        echo "[!] Invalid PCI address: $bdf"
        return 1
    fi
    if ! [[ "$dm" =~ ^[A-Za-z0-9@._-]+\.service$ ]]; then
        echo "[!] Invalid display manager unit: $dm"
        return 1
    fi
    if ! [[ "$launcher" =~ ^[A-Za-z0-9_./@+-]+$ ]]; then
        echo "[!] Invalid launcher path characters."
        return 1
    fi
    if [[ ! -x "$launcher" ]]; then
        echo "[!] Launcher script is not executable: $launcher"
        return 1
    fi

    local check_out safe_bdf safe_dm
    if ! check_out=$(run_check); then
        echo "$check_out"
        return 1
    fi

    safe_bdf=$(echo "$check_out" | sed -n 's/^SINGLE_GPU_OK BDF=\([^ ]*\) DM=.*/\1/p')
    safe_dm=$(echo "$check_out" | sed -n 's/^SINGLE_GPU_OK BDF=[^ ]* DM=\(.*\)$/\1/p')

    if [[ "$safe_bdf" != "$bdf" ]] || [[ "$safe_dm" != "$dm" ]]; then
        echo "[!] Security mismatch. Requested BDF/DM does not match safe topology."
        return 1
    fi

    local funcs=() f
    for f in /sys/bus/pci/devices/"${bdf%.*}".*; do
        if [[ -e "$f" ]] && [[ -e "$f/iommu_group" ]]; then
            funcs+=("$(basename "$f")")
        fi
    done
    if (( ${#funcs[@]} == 0 )); then
        echo "[!] No PCI functions found for $bdf"
        return 1
    fi

    if [[ -e "$HOOK_FILE" ]] && ! grep -q "$MARKER" "$HOOK_FILE"; then
        echo "[!] Another libvirt qemu hook already exists at $HOOK_FILE and was not created by Wise Linux."
        echo "[!] Refusing to overwrite it."
        return 1
    fi

    mkdir -p "$STATE_DIR" "$HOOK_DIR"
    chmod 700 "$STATE_DIR"

    cat > "$CONF_FILE" << EOF
VM_NAME="$VM_NAME"
GPU_FUNCS="${funcs[*]}"
DM_SERVICE="$dm"
LAUNCHER="$launcher"
EOF
    chmod 600 "$CONF_FILE"

    cat > "$HOOK_FILE" << 'HOOKEOF'
#!/bin/bash
# WISE-LINUX-SINGLE-GPU-HOOK
# libvirt qemu hook installed by Wise Linux Studio.
# It acts only on the Wise VM and only while "armed" by the launcher.
GUEST="${1:-}"
OPERATION="${2:-}"
SUBOP="${3:-}"

STATE_DIR="/var/lib/wise-linux"
CONF_FILE="${STATE_DIR}/single_gpu.conf"
STATE_FILE="${STATE_DIR}/single_gpu.state"
ARMED_FILE="${STATE_DIR}/single_gpu.armed"
LOG_FILE="/var/log/wise-single-gpu.log"

[ -f "$CONF_FILE" ] || exit 0
. "$CONF_FILE"
[ "$GUEST" = "$VM_NAME" ] || exit 0
[ -f "$ARMED_FILE" ] || exit 0

if [ -f "$LOG_FILE" ] && [ "$(stat -c%s "$LOG_FILE" 2>/dev/null || echo 0)" -gt 1048576 ]; then
    tail -n 1000 "$LOG_FILE" > "${LOG_FILE}.tmp" && mv "${LOG_FILE}.tmp" "$LOG_FILE"
fi

VIRSH="virsh --connect qemu:///system"

log() {
    echo "$(date '+%F %T') $*" >> "$LOG_FILE"
}

gpu_driver() {
    local first="${GPU_FUNCS%% *}" link
    link=$(readlink "/sys/bus/pci/devices/${first}/driver" 2>/dev/null) || return 1
    basename "$link"
}

modules_for_driver() {
    case "$1" in
        nvidia)  echo "nvidia_drm nvidia_modeset nvidia_uvm nvidia" ;;
        nouveau) echo "nouveau" ;;
        amdgpu)  echo "amdgpu" ;;
        i915)    echo "i915" ;;
        xe)      echo "xe" ;;
        *)       echo "" ;;
    esac
}

prepare_gpu() {
    local drv mods m f dev vt

    drv=$(gpu_driver) || drv=""
    if [ "$drv" = "vfio-pci" ] || [ "$drv" = "vfio_pci" ] || [ "$drv" = "vfio" ]; then
        log "GPU is already bound to vfio ($drv). Aborting to prevent host driver loss."
        return 1
    fi

    mods=$(modules_for_driver "$drv")
    if [ -z "$mods" ]; then
        log "unsupported or unknown host GPU driver: '$drv'"
        return 2
    fi
    echo "$drv" > "$STATE_FILE"

    log "stopping $DM_SERVICE (driver: $drv)"
    systemctl stop "$DM_SERVICE" || { log "could not stop $DM_SERVICE"; return 1; }
    for _ in $(seq 1 20); do
        systemctl is-active --quiet "$DM_SERVICE" || break
        sleep 0.5
    done
    sleep 2

    systemctl stop nvidia-persistenced 2>/dev/null || true

    for vt in /sys/class/vtconsole/vtcon*; do
        [ -e "$vt/bind" ] || continue
        if grep -q "frame buffer" "$vt/name" 2>/dev/null; then
            echo 0 > "$vt/bind" 2>/dev/null || true
        fi
    done

    if [ -e "/sys/bus/platform/drivers/efi-framebuffer/efi-framebuffer.0" ]; then
        echo efi-framebuffer.0 > /sys/bus/platform/drivers/efi-framebuffer/unbind 2>/dev/null || true
    fi
    if [ -e "/sys/bus/platform/drivers/simple-framebuffer/simple-framebuffer.0" ]; then
        echo simple-framebuffer.0 > /sys/bus/platform/drivers/simple-framebuffer/unbind 2>/dev/null || true
    fi

    for m in $mods; do
        if lsmod | grep -q "^${m} "; then
            modprobe -r "$m" >> "$LOG_FILE" 2>&1 || { log "could not unload module $m"; return 1; }
        fi
    done

    modprobe vfio-pci >> "$LOG_FILE" 2>&1 || { log "could not load vfio-pci"; return 1; }
    modprobe vfio_iommu_type1 >> "$LOG_FILE" 2>&1 || { log "could not load vfio_iommu_type1"; return 1; }

    for f in $GPU_FUNCS; do
        dev="pci_$(echo "$f" | tr ':.' '__')"
        timeout 30 $VIRSH nodedev-detach "$dev" >> "$LOG_FILE" 2>&1 || { log "could not detach $dev"; return 1; }
    done
    log "GPU released to VFIO"
    return 0
}

restore_gpu() {
    local drv f dev vt cur_drv first
    local reattach_failed=0

    drv=$(cat "$STATE_FILE" 2>/dev/null || echo "")
    case "$drv" in
        nvidia|nouveau|amdgpu|i915|xe) ;;
        *)
            log "CRITICAL: missing or invalid original host driver in STATE_FILE ('$drv')"
            return 1
            ;;
    esac
    log "restoring GPU to the host (driver: $drv)"

    for f in $GPU_FUNCS; do
        cur_drv=""
        if [ -L "/sys/bus/pci/devices/${f}/driver" ]; then
            cur_drv=$(basename "$(readlink "/sys/bus/pci/devices/${f}/driver" 2>/dev/null)" 2>/dev/null || echo "")
        fi
        if [ "$cur_drv" = "vfio-pci" ] || [ "$cur_drv" = "vfio_pci" ] || [ -z "$cur_drv" ]; then
            dev="pci_$(echo "$f" | tr ':.' '__')"
            if ! timeout 30 $VIRSH nodedev-reattach "$dev" >> "$LOG_FILE" 2>&1; then
                log "CRITICAL: could not reattach $dev"
                reattach_failed=1
            fi
        fi
        cur_drv=""
        if [ -L "/sys/bus/pci/devices/${f}/driver" ]; then
            cur_drv=$(basename "$(readlink "/sys/bus/pci/devices/${f}/driver" 2>/dev/null)" 2>/dev/null || echo "")
        fi
        if [ "$cur_drv" = "vfio-pci" ] || [ "$cur_drv" = "vfio_pci" ]; then
            log "CRITICAL: $f is still bound to $cur_drv after reattach"
            reattach_failed=1
        fi
    done

    if [ "$reattach_failed" -eq 1 ]; then
        log "FATAL: GPU reattach failed. Aborting display manager startup to prevent crash loop."
        return 1
    fi

    case "$drv" in
        nvidia)
            modprobe nvidia >> "$LOG_FILE" 2>&1 || { log "CRITICAL: could not load module nvidia"; return 1; }
            modprobe nvidia_modeset >> "$LOG_FILE" 2>&1 || { log "CRITICAL: could not load module nvidia_modeset"; return 1; }
            modprobe nvidia_drm >> "$LOG_FILE" 2>&1 || { log "CRITICAL: could not load module nvidia_drm"; return 1; }
            modprobe nvidia_uvm >> "$LOG_FILE" 2>&1 || true
            ;;
        *)
            modprobe "$drv" >> "$LOG_FILE" 2>&1 || { log "CRITICAL: could not load module $drv"; return 1; }
            ;;
    esac

    first="${GPU_FUNCS%% *}"
    for f in $GPU_FUNCS; do
        if [ ! -L "/sys/bus/pci/devices/${f}/driver" ]; then
            echo "$f" > /sys/bus/pci/drivers_probe 2>/dev/null || true
        fi
    done

    cur_drv=$(gpu_driver) || cur_drv=""
    if [ "$cur_drv" != "$drv" ]; then
        log "CRITICAL: primary GPU $first did not bind to expected host driver '$drv' (current: '$cur_drv')"
        return 1
    fi

    for vt in /sys/class/vtconsole/vtcon*; do
        [ -e "$vt/bind" ] || continue
        echo 1 > "$vt/bind" 2>/dev/null || true
    done

    if [ -e "/sys/bus/platform/devices/efi-framebuffer.0" ] && [ ! -e "/sys/bus/platform/drivers/efi-framebuffer/efi-framebuffer.0" ]; then
        echo efi-framebuffer.0 > /sys/bus/platform/drivers/efi-framebuffer/bind 2>/dev/null || true
    fi
    if [ -e "/sys/bus/platform/devices/simple-framebuffer.0" ] && [ ! -e "/sys/bus/platform/drivers/simple-framebuffer/simple-framebuffer.0" ]; then
        echo simple-framebuffer.0 > /sys/bus/platform/drivers/simple-framebuffer/bind 2>/dev/null || true
    fi

    if ! systemctl start "$DM_SERVICE" >> "$LOG_FILE" 2>&1; then
        log "CRITICAL: could not start $DM_SERVICE"
        return 1
    fi
    sleep 2
    if ! systemctl is-active --quiet "$DM_SERVICE" 2>/dev/null; then
        log "CRITICAL: $DM_SERVICE did not remain active after startup"
        return 1
    fi
    log "host display restored"
    return 0
}

case "${OPERATION}/${SUBOP}" in
    prepare/begin)
        log "=== prepare/begin for $GUEST ==="
        prep_rc=0
        prepare_gpu || prep_rc=$?
        if [ "$prep_rc" -ne 0 ]; then
            if [ "$prep_rc" -eq 2 ]; then
                log "prepare aborted before modifying host state; clearing ARMED_FILE"
                rm -f "$ARMED_FILE"
                exit 1
            fi
            log "prepare failed: restoring host and aborting the VM start"
            if restore_gpu; then
                rm -f "$ARMED_FILE" "$STATE_FILE"
            else
                log "restore_gpu failed after prepare failure, keeping ARMED_FILE and preserving state"
            fi
            exit 1
        fi
        ;;
    release/end)
        log "=== release/end for $GUEST ==="
        if restore_gpu; then
            rm -f "$ARMED_FILE" "$STATE_FILE"
            if [ -x "$LAUNCHER" ]; then
                systemd-run --no-block --collect "$LAUNCHER" --revert-wait >> "$LOG_FILE" 2>&1 || true
            fi
        else
            log "restore_gpu failed, keeping ARMED_FILE and preserving state"
        fi
        ;;
esac
exit 0
HOOKEOF
    chmod 755 "$HOOK_FILE"
    restorecon "$HOOK_FILE" 2>/dev/null || true

    echo "[+] Single-GPU hook installed for $bdf (display manager: $dm)."
    return 0
}

do_uninstall() {
    if [[ $EUID -ne 0 ]]; then
        echo "[!] Root privileges required to remove the single-GPU hook."
        return 1
    fi
    if [[ -f "$HOOK_FILE" ]] && grep -q "$MARKER" "$HOOK_FILE"; then
        rm -f "$HOOK_FILE"
        echo "[*] Removed the Wise Linux libvirt hook."
    fi
    rm -f "$CONF_FILE" "$STATE_FILE" "$ARMED_FILE"
    return 0
}

usage() {
    echo "Usage: $0 --check | --install BDF DM LAUNCHER | --uninstall"
}

case "${1:-}" in
    --check)     run_check ;;
    --install)   shift; do_install "$@" ;;
    --uninstall) do_uninstall ;;
    *)           usage; exit 1 ;;
esac