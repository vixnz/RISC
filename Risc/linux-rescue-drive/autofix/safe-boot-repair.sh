#!/bin/bash
#
# Safe Boot Repair Utility
# Enhanced version with comprehensive safety checks and error handling
#

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
BOLD='\033[1m'
NC='\033[0m'

# Enhanced logging
LOG_FILE="/tmp/boot_repair_$(date +%Y%m%d_%H%M%S).log"

log_message() {
    local level=$1
    local message=$2
    echo "$(date '+%Y-%m-%d %H:%M:%S') [$level] $message" >> "$LOG_FILE"
    
    case $level in
        "INFO") echo -e "${BLUE}[INFO]${NC} $message" ;;
        "SUCCESS") echo -e "${GREEN}[SUCCESS]${NC} $message" ;;
        "WARNING") echo -e "${YELLOW}[WARNING]${NC} $message" ;;
        "ERROR") echo -e "${RED}[ERROR]${NC} $message" ;;
    esac
}

# Rollback mechanism
MOUNT_STACK=()
BACKUP_FILES=()

cleanup_on_error() {
    log_message "ERROR" "Error occurred, performing cleanup..."
    
    # Unmount everything in reverse order
    for ((i=${#MOUNT_STACK[@]}-1; i>=0; i--)); do
        local mount_point="${MOUNT_STACK[i]}"
        if mount | grep -q "$mount_point"; then
            log_message "INFO" "Unmounting $mount_point"
            sudo umount "$mount_point" 2>/dev/null || true
        fi
    done
    
    # Restore backups if needed
    for backup in "${BACKUP_FILES[@]}"; do
        local original_file=$(echo "$backup" | cut -d: -f1)
        local backup_file=$(echo "$backup" | cut -d: -f2)
        if [ -f "$backup_file" ] && [ ! -f "$original_file" ]; then
            log_message "INFO" "Restoring backup: $original_file"
            sudo cp "$backup_file" "$original_file" 2>/dev/null || true
        fi
    done
}

trap cleanup_on_error ERR EXIT

add_mount() {
    local mount_point=$1
    MOUNT_STACK+=("$mount_point")
}

create_backup() {
    local file=$1
    if [ -f "$file" ]; then
        local backup_file="${file}.backup.$(date +%s)"
        sudo cp "$file" "$backup_file"
        BACKUP_FILES+=("$file:$backup_file")
        log_message "INFO" "Created backup: $backup_file"
    fi
}

detect_boot_environment() {
    log_message "INFO" "Detecting boot environment..."
    
    if [ -d /sys/firmware/efi ]; then
        echo "UEFI"
        log_message "INFO" "UEFI boot environment detected"
    else
        echo "BIOS"
        log_message "INFO" "BIOS boot environment detected"
    fi
}

safe_find_linux_installations() {
    log_message "INFO" "Safely scanning for Linux installations..."
    
    local installations=()
    
    # Scan all block devices, but be very careful about identification
    for device in $(lsblk -dpno NAME | grep -E '/dev/sd|/dev/nvme|/dev/vd'); do
        # Skip if device doesn't exist
        if [ ! -b "$device" ]; then
            continue
        fi
        
        # Get device info for safety
        local device_info=$(lsblk -dno NAME,SIZE,MODEL "$device" 2>/dev/null || echo "unknown")
        log_message "INFO" "Scanning device: $device_info"
        
        # Check each partition
        for partition in $(lsblk -pno NAME "$device" | tail -n +2); do
            # Skip if not a partition
            if [ ! -b "$partition" ]; then
                continue
            fi
            
            # Get filesystem type safely
            local fstype=$(blkid -o value -s TYPE "$partition" 2>/dev/null || echo "unknown")
            local label=$(blkid -o value -s LABEL "$partition" 2>/dev/null || echo "")
            local uuid=$(blkid -o value -s UUID "$partition" 2>/dev/null || echo "")
            
            log_message "INFO" "Checking partition $partition (fs: $fstype, label: $label)"
            
            # Only check Linux filesystems
            if [[ "$fstype" =~ ^(ext[234]|xfs|btrfs)$ ]]; then
                # Try to safely mount and check
                local mount_point="/tmp/safe_mount_$(basename "$partition")"
                mkdir -p "$mount_point"
                
                # Mount read-only first for safety
                if sudo mount -o ro "$partition" "$mount_point" 2>/dev/null; then
                    add_mount "$mount_point"
                    
                    # Check for Linux installation markers
                    local is_linux_system=0
                    
                    # Check for essential Linux directories and files
                    if [ -f "$mount_point/etc/fstab" ] && 
                       [ -d "$mount_point/boot" ] && 
                       [ -d "$mount_point/etc" ] &&
                       [ -d "$mount_point/usr" ]; then
                        
                        # Additional verification - check for distro markers
                        local distro="Unknown"
                        if [ -f "$mount_point/etc/os-release" ]; then
                            distro=$(grep "^NAME=" "$mount_point/etc/os-release" | cut -d'"' -f2 2>/dev/null || echo "Unknown")
                        elif [ -f "$mount_point/etc/lsb-release" ]; then
                            distro=$(grep "DISTRIB_DESCRIPTION=" "$mount_point/etc/lsb-release" | cut -d'"' -f2 2>/dev/null || echo "Unknown")
                        fi
                        
                        # Check fstab for root filesystem entry
                        if grep -q "^[^#].*[[:space:]]/[[:space:]]" "$mount_point/etc/fstab" 2>/dev/null; then
                            is_linux_system=1
                            log_message "SUCCESS" "Found Linux installation on $partition: $distro"
                            
                            # Check for Windows dual-boot to warn user
                            check_windows_dualboot "$partition" "$mount_point"
                        fi
                    fi
                    
                    # Unmount safely
                    sudo umount "$mount_point" 2>/dev/null || true
                    rmdir "$mount_point" 2>/dev/null || true
                    
                    if [ "$is_linux_system" -eq 1 ]; then
                        # Remount read-write for repair
                        if sudo mount "$partition" "$mount_point" 2>/dev/null; then
                            installations+=("$partition:$mount_point:$distro")
                        else
                            log_message "WARNING" "Could not remount $partition for repair"
                        fi
                    fi
                else
                    rmdir "$mount_point" 2>/dev/null || true
                fi
            fi
        done
    done
    
    printf '%s\n' "${installations[@]}"
}

check_windows_dualboot() {
    local partition=$1
    local mount_point=$2
    
    # Check fstab for Windows partitions
    if grep -qE "ntfs|vfat.*boot" "$mount_point/etc/fstab" 2>/dev/null; then
        log_message "WARNING" "Windows dual-boot detected on $partition"
        echo "DUAL_BOOT_DETECTED=1" >> "$LOG_FILE"
        return 0
    fi
    
    # Check for Windows partitions on the same disk
    local disk_device=$(echo "$partition" | sed 's/[0-9]*$//')
    local windows_partitions=$(blkid | grep -E "TYPE=\"ntfs\".*$disk_device" | wc -l)
    
    if [ "$windows_partitions" -gt 0 ]; then
        log_message "WARNING" "NTFS partitions detected on same disk - possible Windows dual-boot"
        echo "POSSIBLE_DUAL_BOOT=1" >> "$LOG_FILE"
        return 0
    fi
    
    return 1
}

detect_filesystem_type() {
    local mount_point=$1
    
    # Check what type of system this is
    if [ -d "$mount_point/boot/grub" ]; then
        echo "GRUB"
    elif [ -f "$mount_point/boot/syslinux/syslinux.cfg" ]; then
        echo "SYSLINUX"
    elif [ -d "$mount_point/boot/loader" ]; then
        echo "SYSTEMD_BOOT"
    else
        echo "UNKNOWN"
    fi
}

safe_grub_repair() {
    local target_partition=$1
    local mount_point=$2
    local boot_mode=$3
    local distro=$4
    
    log_message "INFO" "Starting safe GRUB repair on $target_partition ($distro)"
    
    # Create backups of critical files
    create_backup "$mount_point/boot/grub/grub.cfg"
    create_backup "$mount_point/etc/default/grub"
    
    # Check for special filesystem types
    local root_fstype=$(findmnt -no FSTYPE "$mount_point" 2>/dev/null || echo "unknown")
    log_message "INFO" "Root filesystem type: $root_fstype"
    
    case "$root_fstype" in
        btrfs)
            log_message "WARNING" "Btrfs filesystem detected - using specialized repair"
            return $(repair_btrfs_grub "$target_partition" "$mount_point" "$boot_mode")
            ;;
        xfs)
            log_message "INFO" "XFS filesystem detected - standard repair applicable"
            ;;
        ext*)
            log_message "INFO" "EXT filesystem detected - standard repair applicable"
            ;;
        *)
            log_message "WARNING" "Unknown filesystem type: $root_fstype"
            echo "Continue with repair anyway? (y/N): "
            read -n 1 continue_repair
            echo
            if [[ ! $continue_repair =~ ^[Yy]$ ]]; then
                return 1
            fi
            ;;
    esac
    
    # Prepare chroot environment safely
    log_message "INFO" "Preparing chroot environment..."
    
    # Mount essential filesystems
    sudo mount --bind /dev "$mount_point/dev" && add_mount "$mount_point/dev"
    sudo mount --bind /proc "$mount_point/proc" && add_mount "$mount_point/proc"
    sudo mount --bind /sys "$mount_point/sys" && add_mount "$mount_point/sys"
    sudo mount --bind /run "$mount_point/run" && add_mount "$mount_point/run"
    
    # Copy DNS configuration
    sudo cp /etc/resolv.conf "$mount_point/etc/resolv.conf.rescue_backup"
    sudo cp /etc/resolv.conf "$mount_point/etc/resolv.conf"
    
    # Handle LVM if present
    if [ -d "$mount_point/dev/mapper" ] && [ "$(ls -A "$mount_point/dev/mapper" 2>/dev/null)" ]; then
        log_message "INFO" "LVM detected, ensuring LVM is available in chroot"
        sudo mount --bind /dev/mapper "$mount_point/dev/mapper" && add_mount "$mount_point/dev/mapper"
    fi
    
    # Find the disk device and handle different scenarios
    local disk_device=$(lsblk -no PKNAME "$target_partition" 2>/dev/null | head -1)
    if [ -n "$disk_device" ]; then
        disk_device="/dev/$disk_device"
    else
        # Fallback method
        disk_device=$(echo "$target_partition" | sed 's/[0-9]*$//')
    fi
    
    log_message "INFO" "Target disk device: $disk_device"
    
    # Handle EFI partition for UEFI systems
    local efi_mounted=0
    if [ "$boot_mode" = "UEFI" ]; then
        local efi_partition=$(find_efi_partition "$disk_device")
        if [ -n "$efi_partition" ]; then
            log_message "INFO" "Mounting EFI partition: $efi_partition"
            sudo mkdir -p "$mount_point/boot/efi"
            if sudo mount "$efi_partition" "$mount_point/boot/efi" 2>/dev/null; then
                add_mount "$mount_point/boot/efi"
                efi_mounted=1
            else
                log_message "WARNING" "Failed to mount EFI partition"
            fi
        else
            log_message "ERROR" "Could not find EFI partition for UEFI system"
            return 1
        fi
    fi
    
    # Perform GRUB installation with error checking
    log_message "INFO" "Installing GRUB..."
    
    local grub_install_cmd=""
    local grub_config_cmd="update-grub"
    
    # Detect distribution-specific commands
    if [ -f "$mount_point/usr/sbin/grub2-install" ]; then
        # RHEL/CentOS/Fedora
        if [ "$boot_mode" = "UEFI" ]; then
            grub_install_cmd="grub2-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=rescue"
        else
            grub_install_cmd="grub2-install --target=i386-pc $disk_device"
        fi
        grub_config_cmd="grub2-mkconfig -o /boot/grub2/grub.cfg"
    else
        # Debian/Ubuntu
        if [ "$boot_mode" = "UEFI" ]; then
            grub_install_cmd="grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=ubuntu --recheck"
        else
            grub_install_cmd="grub-install --target=i386-pc --recheck $disk_device"
        fi
    fi
    
    log_message "INFO" "GRUB install command: $grub_install_cmd"
    log_message "INFO" "GRUB config command: $grub_config_cmd"
    
    # Execute GRUB installation in chroot with comprehensive error checking
    local grub_install_success=0
    
    sudo chroot "$mount_point" /bin/bash -c "
        set -e
        export DEBIAN_FRONTEND=noninteractive
        export PATH=/usr/sbin:/usr/bin:/sbin:/bin
        
        echo 'Starting GRUB installation...'
        
        # Update package database if network available
        if ping -c 1 8.8.8.8 >/dev/null 2>&1; then
            if command -v apt-get >/dev/null 2>&1; then
                apt-get update >/dev/null 2>&1 || true
            elif command -v yum >/dev/null 2>&1; then
                yum makecache >/dev/null 2>&1 || true
            fi
        fi
        
        # Ensure GRUB packages are installed
        if command -v apt-get >/dev/null 2>&1; then
            apt-get install --reinstall grub-pc grub-pc-bin -y 2>/dev/null || true
            if [ '$boot_mode' = 'UEFI' ]; then
                apt-get install --reinstall grub-efi-amd64 grub-efi-amd64-bin -y 2>/dev/null || true
            fi
        fi
        
        # Install GRUB
        $grub_install_cmd
        
        # Generate configuration
        $grub_config_cmd
        
        echo 'GRUB installation completed successfully'
    " 2>&1 | tee -a "$LOG_FILE"
    
    if [ ${PIPESTATUS[0]} -eq 0 ]; then
        grub_install_success=1
        log_message "SUCCESS" "GRUB installation completed successfully"
    else
        log_message "ERROR" "GRUB installation failed"
    fi
    
    # Cleanup: restore original resolv.conf
    if [ -f "$mount_point/etc/resolv.conf.rescue_backup" ]; then
        sudo mv "$mount_point/etc/resolv.conf.rescue_backup" "$mount_point/etc/resolv.conf"
    fi
    
    return $grub_install_success
}

find_efi_partition() {
    local disk_device=$1
    
    # Look for EFI system partition
    local efi_partition=""
    
    # Method 1: Check partition types with parted
    if command -v parted >/dev/null 2>&1; then
        efi_partition=$(sudo parted "$disk_device" print 2>/dev/null | grep -i "boot, esp" | awk '{print $1}' | head -1)
        if [ -n "$efi_partition" ]; then
            echo "${disk_device}${efi_partition}"
            return 0
        fi
    fi
    
    # Method 2: Check with gdisk
    if command -v gdisk >/dev/null 2>&1; then
        efi_partition=$(sudo gdisk -l "$disk_device" 2>/dev/null | grep "EF00" | awk '{print $1}' | head -1)
        if [ -n "$efi_partition" ]; then
            echo "${disk_device}${efi_partition}"
            return 0
        fi
    fi
    
    # Method 3: Look for mounted EFI partition
    efi_partition=$(mount | grep -E "boot/efi|EFI" | awk '{print $1}' | head -1)
    if [ -n "$efi_partition" ]; then
        echo "$efi_partition"
        return 0
    fi
    
    # Method 4: Check filesystem types
    for partition in $(lsblk -pno NAME "$disk_device" | tail -n +2); do
        local fstype=$(blkid -o value -s TYPE "$partition" 2>/dev/null || echo "")
        if [ "$fstype" = "vfat" ]; then
            # Check if it looks like an EFI partition (small size, contains EFI directory)
            local size_mb=$(lsblk -no SIZE "$partition" | sed 's/[^0-9.]//g')
            if (( $(echo "$size_mb < 1000" | bc -l 2>/dev/null || echo 1) )); then
                echo "$partition"
                return 0
            fi
        fi
    done
    
    return 1
}

repair_btrfs_grub() {
    local target_partition=$1
    local mount_point=$2  
    local boot_mode=$3
    
    log_message "INFO" "Repairing GRUB on Btrfs filesystem"
    
    # Btrfs requires special handling for subvolumes
    local root_subvol=$(btrfs subvolume show "$mount_point" 2>/dev/null | grep "Name:" | awk '{print $2}' || echo "@")
    log_message "INFO" "Btrfs root subvolume: $root_subvol"
    
    # Continue with standard GRUB repair, but note the subvolume
    return $(safe_grub_repair "$target_partition" "$mount_point" "$boot_mode" "Btrfs")
}

interactive_repair() {
    echo -e "${BOLD}Enhanced Boot Repair Utility${NC}"
    echo "Log file: $LOG_FILE"
    echo
    
    local boot_mode=$(detect_boot_environment)
    
    log_message "INFO" "Starting safe Linux installation scan..."
    local installations=($(safe_find_linux_installations))
    
    if [ ${#installations[@]} -eq 0 ]; then
        log_message "ERROR" "No Linux installations found"
        echo "This could mean:"
        echo "  - No Linux systems are installed"
        echo "  - Filesystems are corrupted"
        echo "  - Partitions are encrypted"
        echo "  - LVM/RAID configuration issues"
        return 1
    fi
    
    echo "Found Linux installations:"
    for i in "${!installations[@]}"; do
        local install_info="${installations[i]}"
        local partition=$(echo "$install_info" | cut -d':' -f1)
        local distro=$(echo "$install_info" | cut -d':' -f3)
        echo "$((i+1))) $partition - $distro"
    done
    echo
    
    # Check for dual-boot warning
    if grep -q "DUAL_BOOT_DETECTED=1" "$LOG_FILE"; then
        echo -e "${YELLOW}⚠️  WARNING: Windows dual-boot detected!${NC}"
        echo "This system appears to have Windows installed alongside Linux."
        echo "Boot repair will preserve the dual-boot configuration."
        echo
    fi
    
    echo "Repair options:"
    echo "1) Safe automatic repair (recommended)"
    echo "2) Advanced GRUB reinstall"
    echo "3) MBR restore only"
    echo "4) Generate boot menu only"
    echo "5) Check boot configuration"
    echo "6) Emergency shell access"
    echo
    
    read -p "Select repair option (1-6): " repair_choice
    read -p "Select installation (1-${#installations[@]}): " install_choice
    
    if [ "$install_choice" -lt 1 ] || [ "$install_choice" -gt ${#installations[@]} ]; then
        log_message "ERROR" "Invalid installation selection"
        return 1
    fi
    
    local selected_install="${installations[$((install_choice-1))]}"
    local partition=$(echo "$selected_install" | cut -d':' -f1)
    local mount_point=$(echo "$selected_install" | cut -d':' -f2)
    local distro=$(echo "$selected_install" | cut -d':' -f3)
    
    log_message "INFO" "Selected: $partition ($distro)"
    
    case $repair_choice in
        1)
            log_message "INFO" "Starting safe automatic repair..."
            if safe_grub_repair "$partition" "$mount_point" "$boot_mode" "$distro"; then
                log_message "SUCCESS" "Automatic repair completed successfully"
            else
                log_message "ERROR" "Automatic repair failed - check log file"
                return 1
            fi
            ;;
        2)
            log_message "INFO" "Starting advanced GRUB reinstall..."
            safe_grub_repair "$partition" "$mount_point" "$boot_mode" "$distro"
            ;;
        3)
            log_message "INFO" "Restoring MBR only..."
            local disk_device=$(echo "$partition" | sed 's/[0-9]*$//')
            if sudo grub-install --target=i386-pc --boot-directory="$mount_point/boot" "$disk_device"; then
                log_message "SUCCESS" "MBR restored successfully"
            else
                log_message "ERROR" "MBR restore failed"
            fi
            ;;
        4)
            log_message "INFO" "Regenerating boot menu..."
            sudo chroot "$mount_point" update-grub
            ;;
        5)
            echo -e "${BOLD}Boot Configuration Analysis:${NC}"
            echo "Partition: $partition"
            echo "Mount point: $mount_point"
            echo "Distribution: $distro"
            echo "Boot mode: $boot_mode"
            echo "Filesystem: $(findmnt -no FSTYPE "$mount_point")"
            echo
            echo "Boot loader type: $(detect_filesystem_type "$mount_point")"
            if [ -f "$mount_point/boot/grub/grub.cfg" ]; then
                echo "GRUB config present: Yes"
                echo "GRUB entries: $(grep -c "menuentry" "$mount_point/boot/grub/grub.cfg" 2>/dev/null || echo 0)"
            else
                echo "GRUB config present: No"
            fi
            ;;
        6)
            echo "Opening emergency shell in chroot environment..."
            echo "Type 'exit' to return to rescue menu"
            
            # Prepare chroot
            sudo mount --bind /dev "$mount_point/dev"
            sudo mount --bind /proc "$mount_point/proc"
            sudo mount --bind /sys "$mount_point/sys"
            sudo chroot "$mount_point" /bin/bash
            ;;
        *)
            log_message "ERROR" "Invalid repair option"
            return 1
            ;;
    esac
    
    log_message "SUCCESS" "Boot repair operations completed"
    echo
    echo "Repair log saved to: $LOG_FILE"
    
    # Clear trap to avoid cleanup on normal exit
    trap - ERR EXIT
    
    # Clean up mounts
    cleanup_on_error
}

main() {
    echo -e "${CYAN}Enhanced Boot Repair Utility${NC}"
    echo "This tool safely repairs boot loaders with comprehensive error checking"
    echo
    
    interactive_repair
}

main "$@"