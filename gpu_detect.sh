#!/bin/bash
# Wise Linux - Pure Read-Only GPU & IOMMU Topology Scanner
set -euo pipefail

echo "[*] Scanning PCI bus for GPUs and mapping IOMMU groups..."
echo ""

printf "%-12s | %-8s | %-6s | %-9s | %-34s | %-s\n" "PCI Slot" "boot_vga" "IOMMU" "Candidate" "Device Info" "Status / Warnings"
printf "%s\n" "----------------------------------------------------------------------------------------------------------------------------"

CANDIDATE_BDF=""
TOTAL_GPUS=0
CANDIDATE_COUNT=0

for dev in /sys/bus/pci/devices/*; do
    [[ -e "$dev/class" ]] || continue
    dev_class=$(cat "$dev/class")

    # Match VGA (0x0300xx) or 3D Controller (0x0302xx)
    if [[ "$dev_class" =~ ^0x030[02] ]]; then
        TOTAL_GPUS=$((TOTAL_GPUS + 1))
        bdf=$(basename "$dev")
        boot_vga=$(cat "$dev/boot_vga" 2>/dev/null || echo "0")

        iommu_group="N/A"
        if [[ -e "$dev/iommu_group" ]]; then
            target_link=$(readlink "$dev/iommu_group" 2>/dev/null || true)
            if [[ -n "$target_link" ]]; then
                iommu_group=$(basename "$target_link")
            fi
        fi

        desc=$(lspci -s "$bdf" -nn | cut -d' ' -f2-)

        is_candidate="NO"
        status_msg="Host Display (Protected)"

        if [[ "$boot_vga" != "1" ]]; then
            if [[ "$iommu_group" == "N/A" ]]; then
                status_msg="WARNING: IOMMU Disabled (Cannot Isolate)"
            else
                is_candidate="YES"
                status_msg="Isolatable Secondary GPU"
                CANDIDATE_BDF="$bdf"
                CANDIDATE_COUNT=$((CANDIDATE_COUNT + 1))
            fi
        fi

        warning_flag=""
        if [[ "$is_candidate" == "YES" ]] && [[ "$iommu_group" != "N/A" ]]; then
            slot_prefix="${bdf%.*}"
            foreign_devices=0

            for group_dev in /sys/kernel/iommu_groups/"$iommu_group"/devices/*; do
                [[ -e "$group_dev" ]] || continue
                group_bdf=$(basename "$group_dev")
                if [[ "$group_bdf" != "$slot_prefix"* ]]; then
                    foreign_devices=$((foreign_devices + 1))
                fi
            done

            if (( foreign_devices > 0 )); then
                warning_flag=" [WARNING: Shares IOMMU group $iommu_group with $foreign_devices non-GPU device(s)]"
            fi
        fi

        printf "%-12s | %-8s | %-6s | %-9s | %-34.34s | %-s\n" "$bdf" "$boot_vga" "$iommu_group" "$is_candidate" "$desc" "${status_msg}${warning_flag}"
    fi
done

printf "%s\n" "----------------------------------------------------------------------------------------------------------------------------"

if (( TOTAL_GPUS <= 1 )) || (( CANDIDATE_COUNT == 0 )); then
    echo "[!] SAFETY LOCK: No isolatable secondary non-boot GPU found (or IOMMU is disabled in BIOS/Kernel)."
    echo "[*] Read-only scan complete. Nothing written to disk."
    exit 0
fi

if (( CANDIDATE_COUNT > 1 )); then
    echo "[!] SAFETY LOCK: Multiple ($CANDIDATE_COUNT) non-boot GPUs detected. Refusing automatic selection."
    echo "[*] Read-only scan complete. Nothing written to disk."
    exit 0
fi

# Extract all PCI IDs in the candidate GPU slot (Video + Audio functions)
SLOT_PREFIX="${CANDIDATE_BDF%.*}"
ID_LIST=""
for func in /sys/bus/pci/devices/"${SLOT_PREFIX}".*; do
    [[ -e "$func/vendor" ]] || continue
    v=$(sed 's/^0x//' "$func/vendor")
    d=$(sed 's/^0x//' "$func/device")
    ID_LIST="${ID_LIST:+${ID_LIST},}${v}:${d}"
done

if [[ -z "$ID_LIST" ]]; then
    echo "[!] SAFETY LOCK: Failed to read PCI vendor/device IDs for $CANDIDATE_BDF."
    exit 0
fi

echo "[+] Single valid isolation candidate verified (Read-only mode)."
echo "CANDIDATE_BDF=${CANDIDATE_BDF} CANDIDATE_IDS=${ID_LIST}"