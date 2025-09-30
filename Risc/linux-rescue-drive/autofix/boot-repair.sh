#!/bin/bash
#
# Boot Repair Utility
# Comprehensive GRUB and boot loader repair tool
#

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
BOLD='\033[1m'
NC='\033[0m'

log_message() {
    local level=$1
    local message=$2
    
    case $level in
        "INFO") echo -e "${BLUE}[INFO]${NC} $message" ;;
        "SUCCESS") echo -e "${GREEN}[SUCCESS]${NC} $message" ;;
        "WARNING") echo -e "${YELLOW}[WARNING]${NC} $message" ;;
        "ERROR") echo -e "${RED}[ERROR]${NC} $message" ;;
    esac
}

detect_boot_environment() {
    log_message "INFO" "Detecting boot environment..."
    
    # Check if we're booting in UEFI or BIOS mode
    if [ -d /sys/firmware/efi ]; then
        echo "UEFI"
        log_message "INFO" "UEFI boot environment detected"
    else
        echo "BIOS"
        log_message "INFO" "BIOS boot environment detected"
    fi
}

find_linux_installations() {
    log_message "INFO" "Scanning for Linux installations..."
    
    local installations=()
    
    # Scan all block devices
    for device in $(lsblk -dpno NAME | grep -E '/dev/sd|/dev/nvme|/dev/hd'); do
        # Check each partition on the device
        for partition in $(lsblk -pno NAME "$device" | tail -n +2); do
            # Check if it's a Linux filesystem
            local fstype=$(lsblk -no FSTYPE "$partition" 2>/dev/null || echo "")
            if [[ "$fstype" =~ ^(ext[234]|xfs|btrfs)$ ]]; then
                # Try to mount and check for Linux installation
                local mount_point="/tmp/mount_$( basename "$partition" )"
                mkdir -p "$mount_point"
                
                if sudo mount "$partition" "$mount_point" 2>/dev/null; then
                    if [ -f "$mount_point/etc/fstab" ] && [ -d "$mount_point/boot" ]; then
                        log_message "SUCCESS" "Found Linux installation on $partition"
                        installations+=("$partition:$mount_point")
                        
                        # Don't unmount yet, we'll use it
                        continue
                    fi
                    sudo umount "$mount_point" 2>/dev/null || true
                fi
                rmdir "$mount_point" 2>/dev/null || true
            fi
        done
    done
    
    printf '%s\n' "${installations[@]}"
}

repair_grub_installation() {
    local target_partition=$1
    local mount_point=$2
    local boot_mode=$3
    
    log_message "INFO" "Repairing GRUB on $target_partition..."
    
    # Prepare chroot environment
    sudo mount --bind /dev "$mount_point/dev"
    sudo mount --bind /proc "$mount_point/proc"
    sudo mount --bind /sys "$mount_point/sys"
    sudo mount --bind /run "$mount_point/run"
    
    # Copy DNS resolution
    sudo cp /etc/resolv.conf "$mount_point/etc/" 2>/dev/null || true
    
    # Find the disk device (remove partition number)
    local disk_device=$(echo "$target_partition" | sed 's/[0-9]*$//')
    
    # Mount EFI partition if UEFI
    local efi_partition=""
    if [ "$boot_mode" = "UEFI" ]; then
        efi_partition=$(lsblk -no NAME,FSTYPE,MOUNTPOINT | grep -E 'vfat.*(/boot/efi|$)' | head -1 | awk '{print "/dev/"$1}')
        if [ -z "$efi_partition" ]; then
            # Look for EFI system partition
            efi_partition=$(gdisk -l "$disk_device" 2>/dev/null | grep "EF00" | head -1 | awk '{print $1}' || true)
            if [ -n "$efi_partition" ]; then
                efi_partition="${disk_device}${efi_partition}"
            fi
        fi
        
        if [ -n "$efi_partition" ] && [ -b "$efi_partition" ]; then
            log_message "INFO" "Mounting EFI partition $efi_partition"
            sudo mkdir -p "$mount_point/boot/efi"
            sudo mount "$efi_partition" "$mount_point/boot/efi" 2>/dev/null || true
        fi
    fi
    
    # Install GRUB
    local grub_install_cmd=""
    if [ "$boot_mode" = "UEFI" ]; then
        grub_install_cmd="grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=ubuntu --recheck --no-floppy"
    else
        grub_install_cmd="grub-install --target=i386-pc --recheck --no-floppy $disk_device"
    fi
    
    log_message "INFO" "Installing GRUB with command: $grub_install_cmd"
    
    sudo chroot "$mount_point" /bin/bash -c "
        export DEBIAN_FRONTEND=noninteractive
        $grub_install_cmd
        update-grub
    " 2>/dev/null
    
    local grub_status=$?
    
    # Cleanup mounts
    sudo umount "$mount_point/boot/efi" 2>/dev/null || true
    sudo umount "$mount_point/dev" 2>/dev/null || true
    sudo umount "$mount_point/proc" 2>/dev/null || true
    sudo umount "$mount_point/sys" 2>/dev/null || true
    sudo umount "$mount_point/run" 2>/dev/null || true
    
    if [ $grub_status -eq 0 ]; then
        log_message "SUCCESS" "GRUB installation completed successfully"
        return 0
    else
        log_message "ERROR" "GRUB installation failed"
        return 1
    fi
}

restore_mbr() {
    local device=$1
    
    log_message "INFO" "Restoring MBR on $device..."
    
    # Install GRUB to MBR
    if sudo grub-install --target=i386-pc --boot-directory=/boot "$device" 2>/dev/null; then
        log_message "SUCCESS" "MBR restored successfully"
        return 0
    else
        log_message "ERROR" "Failed to restore MBR"
        return 1
    fi
}

repair_boot_menu() {
    local mount_point=$1
    
    log_message "INFO" "Regenerating boot menu..."
    
    # Update GRUB configuration
    sudo chroot "$mount_point" /bin/bash -c "
        update-grub 2>/dev/null
        os-prober 2>/dev/null
        update-grub 2>/dev/null
    " 2>/dev/null
    
    if [ $? -eq 0 ]; then
        log_message "SUCCESS" "Boot menu updated successfully"
    else
        log_message "WARNING" "Boot menu update completed with warnings"
    fi
}

check_boot_flags() {
    log_message "INFO" "Checking boot flags on all disks..."
    
    for disk in $(lsblk -dpno NAME | grep -E '/dev/sd|/dev/nvme|/dev/hd'); do
        log_message "INFO" "Checking $disk..."
        
        # Check for boot flag on MBR partitions
        local boot_partition=$(parted "$disk" print 2>/dev/null | grep boot | head -1 | awk '{print $1}')
        if [ -n "$boot_partition" ]; then
            log_message "SUCCESS" "Boot flag found on ${disk}${boot_partition}"
        else
            log_message "WARNING" "No boot flag found on $disk"
            
            # Find the first Linux partition and set boot flag
            local linux_partition=$(parted "$disk" print 2>/dev/null | grep -E 'ext[234]|xfs|btrfs' | head -1 | awk '{print $1}')
            if [ -n "$linux_partition" ]; then
                log_message "INFO" "Setting boot flag on ${disk}${linux_partition}"
                sudo parted "$disk" set "$linux_partition" boot on 2>/dev/null || true
            fi
        fi
    done
}

interactive_repair() {
    echo -e "${BOLD}Boot Repair Utility${NC}"
    echo
    
    local boot_mode=$(detect_boot_environment)
    local installations=($(find_linux_installations))
    
    if [ ${#installations[@]} -eq 0 ]; then
        log_message "ERROR" "No Linux installations found"
        return 1
    fi
    
    echo "Found Linux installations:"
    for i in "${!installations[@]}"; do
        local partition=$(echo "${installations[i]}" | cut -d':' -f1)
        echo "$((i+1))) $partition"
    done
    echo
    
    echo "Repair options:"
    echo "1) Automatic repair (recommended)"
    echo "2) Reinstall GRUB only"
    echo "3) Restore MBR only"
    echo "4) Regenerate boot menu only"
    echo "5) Check and fix boot flags"
    echo "6) Custom repair"
    echo
    
    read -p "Select repair option: " repair_choice
    read -p "Select installation (1-${#installations[@]}): " install_choice
    
    if [ "$install_choice" -lt 1 ] || [ "$install_choice" -gt ${#installations[@]} ]; then
        log_message "ERROR" "Invalid installation selection"
        return 1
    fi
    
    local selected_install="${installations[$((install_choice-1))]}"
    local partition=$(echo "$selected_install" | cut -d':' -f1)
    local mount_point=$(echo "$selected_install" | cut -d':' -f2)
    
    case $repair_choice in
        1)
            log_message "INFO" "Starting automatic repair..."
            repair_grub_installation "$partition" "$mount_point" "$boot_mode"
            repair_boot_menu "$mount_point"
            check_boot_flags
            ;;
        2)
            repair_grub_installation "$partition" "$mount_point" "$boot_mode"
            ;;
        3)
            local disk_device=$(echo "$partition" | sed 's/[0-9]*$//')
            restore_mbr "$disk_device"
            ;;
        4)
            repair_boot_menu "$mount_point"
            ;;
        5)
            check_boot_flags
            ;;
        6)
            echo "Custom repair options:"
            echo "Enter commands to run in chroot environment (type 'exit' to finish):"
            sudo chroot "$mount_point" /bin/bash
            ;;
        *)
            log_message "ERROR" "Invalid repair option"
            return 1
            ;;
    esac
    
    # Cleanup
    for install in "${installations[@]}"; do
        local mount_pt=$(echo "$install" | cut -d':' -f2)
        sudo umount "$mount_pt" 2>/dev/null || true
        rmdir "$mount_pt" 2>/dev/null || true
    done
    
    log_message "SUCCESS" "Boot repair completed"
}

main() {
    # Check if running as root is needed
    if [ "$EUID" -ne 0 ]; then
        echo "This script requires root privileges for some operations."
        echo "It will use sudo when needed."
        echo
    fi
    
    interactive_repair
}

main "$@"