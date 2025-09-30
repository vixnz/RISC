#!/bin/bash
#
# Filesystem Repair Utility
# Comprehensive filesystem checking and repair tool
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

detect_filesystems() {
    log_message "INFO" "Detecting filesystems..."
    
    echo "Available filesystems:"
    lsblk -f | grep -E 'ext[234]|xfs|btrfs|ntfs|fat32|vfat' | while read line; do
        local device=$(echo "$line" | awk '{print $1}' | sed 's/[├└─]//g' | tr -d '└├─ ')
        local fstype=$(echo "$line" | awk '{print $2}')
        local label=$(echo "$line" | awk '{print $3}')
        local size=$(lsblk -no SIZE "/dev/$device" 2>/dev/null || echo "Unknown")
        
        printf "  /dev/%-10s %-8s %-15s %s\n" "$device" "$fstype" "$label" "$size"
    done
    echo
}

check_ext_filesystem() {
    local device=$1
    local force_repair=$2
    
    log_message "INFO" "Checking ext filesystem on $device..."
    
    # Unmount if mounted
    if mount | grep -q "$device"; then
        local mount_point=$(mount | grep "$device" | awk '{print $3}')
        log_message "INFO" "Unmounting $device from $mount_point..."
        sudo umount "$device" 2>/dev/null || true
    fi
    
    # Check filesystem
    if [ "$force_repair" = "yes" ]; then
        log_message "INFO" "Force repairing filesystem..."
        sudo fsck.ext4 -f -y "$device"
    else
        log_message "INFO" "Checking filesystem (read-only)..."
        if sudo fsck.ext4 -n "$device" 2>&1 | grep -q "clean"; then
            log_message "SUCCESS" "Filesystem is clean"
            return 0
        else
            log_message "WARNING" "Filesystem has errors"
            
            echo "Filesystem errors detected. Repair options:"
            echo "1) Automatic repair (recommended)"
            echo "2) Interactive repair"
            echo "3) Force repair (may cause data loss)"
            echo "4) Skip repair"
            
            read -p "Select option (1-4): " repair_option
            
            case $repair_option in
                1)
                    log_message "INFO" "Starting automatic repair..."
                    sudo fsck.ext4 -p "$device"
                    ;;
                2)
                    log_message "INFO" "Starting interactive repair..."
                    sudo fsck.ext4 "$device"
                    ;;
                3)
                    log_message "WARNING" "Starting force repair (may cause data loss)..."
                    sudo fsck.ext4 -f -y "$device"
                    ;;
                4)
                    log_message "INFO" "Skipping repair"
                    return 1
                    ;;
                *)
                    log_message "ERROR" "Invalid option"
                    return 1
                    ;;
            esac
        fi
    fi
    
    # Verify repair
    if sudo fsck.ext4 -n "$device" 2>&1 | grep -q "clean"; then
        log_message "SUCCESS" "Filesystem repair completed successfully"
        return 0
    else
        log_message "ERROR" "Filesystem repair failed or incomplete"
        return 1
    fi
}

check_xfs_filesystem() {
    local device=$1
    
    log_message "INFO" "Checking XFS filesystem on $device..."
    
    # Unmount if mounted
    if mount | grep -q "$device"; then
        local mount_point=$(mount | grep "$device" | awk '{print $3}')
        log_message "INFO" "Unmounting $device from $mount_point..."
        sudo umount "$device" 2>/dev/null || true
    fi
    
    # Check filesystem
    if sudo xfs_repair -n "$device" 2>/dev/null; then
        log_message "SUCCESS" "XFS filesystem is clean"
        return 0
    else
        log_message "WARNING" "XFS filesystem has errors"
        
        echo "Repair XFS filesystem? (y/N): "
        read -n 1 confirm
        echo
        
        if [[ $confirm =~ ^[Yy]$ ]]; then
            log_message "INFO" "Repairing XFS filesystem..."
            if sudo xfs_repair "$device"; then
                log_message "SUCCESS" "XFS filesystem repaired successfully"
                return 0
            else
                log_message "ERROR" "XFS filesystem repair failed"
                return 1
            fi
        else
            log_message "INFO" "Skipping XFS repair"
            return 1
        fi
    fi
}

check_ntfs_filesystem() {
    local device=$1
    
    log_message "INFO" "Checking NTFS filesystem on $device..."
    
    # Unmount if mounted
    if mount | grep -q "$device"; then
        local mount_point=$(mount | grep "$device" | awk '{print $3}')
        log_message "INFO" "Unmounting $device from $mount_point..."
        sudo umount "$device" 2>/dev/null || true
    fi
    
    # Check if ntfsfix is available
    if command -v ntfsfix >/dev/null 2>&1; then
        log_message "INFO" "Running NTFS consistency check..."
        if sudo ntfsfix -n "$device" 2>/dev/null; then
            log_message "SUCCESS" "NTFS filesystem is consistent"
            return 0
        else
            log_message "WARNING" "NTFS filesystem has issues"
            
            echo "Repair NTFS filesystem? (y/N): "
            read -n 1 confirm
            echo
            
            if [[ $confirm =~ ^[Yy]$ ]]; then
                log_message "INFO" "Repairing NTFS filesystem..."
                if sudo ntfsfix "$device"; then
                    log_message "SUCCESS" "NTFS filesystem repaired"
                    return 0
                else
                    log_message "ERROR" "NTFS filesystem repair failed"
                    return 1
                fi
            fi
        fi
    else
        log_message "WARNING" "ntfsfix not available, skipping NTFS check"
        return 1
    fi
}

check_fat_filesystem() {
    local device=$1
    
    log_message "INFO" "Checking FAT filesystem on $device..."
    
    # Unmount if mounted
    if mount | grep -q "$device"; then
        local mount_point=$(mount | grep "$device" | awk '{print $3}')
        log_message "INFO" "Unmounting $device from $mount_point..."
        sudo umount "$device" 2>/dev/null || true
    fi
    
    # Check filesystem
    if sudo fsck.fat -r "$device" 2>/dev/null; then
        log_message "SUCCESS" "FAT filesystem is clean"
        return 0
    else
        log_message "WARNING" "FAT filesystem has errors"
        
        echo "Repair FAT filesystem? (y/N): "
        read -n 1 confirm
        echo
        
        if [[ $confirm =~ ^[Yy]$ ]]; then
            log_message "INFO" "Repairing FAT filesystem..."
            if sudo fsck.fat -a "$device"; then
                log_message "SUCCESS" "FAT filesystem repaired"
                return 0
            else
                log_message "ERROR" "FAT filesystem repair failed"
                return 1
            fi
        fi
    fi
}

scan_bad_blocks() {
    local device=$1
    
    log_message "INFO" "Scanning for bad blocks on $device..."
    log_message "WARNING" "This operation may take a long time for large devices"
    
    echo "Scan for bad blocks? This is a read-only operation (y/N): "
    read -n 1 confirm
    echo
    
    if [[ $confirm =~ ^[Yy]$ ]]; then
        log_message "INFO" "Starting bad block scan (read-only)..."
        if sudo badblocks -v "$device" > "/tmp/badblocks_$(basename "$device").txt" 2>&1; then
            local bad_blocks=$(wc -l < "/tmp/badblocks_$(basename "$device").txt")
            if [ "$bad_blocks" -gt 0 ]; then
                log_message "ERROR" "Found $bad_blocks bad blocks on $device"
                log_message "INFO" "Bad block list saved to /tmp/badblocks_$(basename "$device").txt"
                
                echo "Add bad blocks to filesystem? (y/N): "
                read -n 1 add_blocks
                echo
                
                if [[ $add_blocks =~ ^[Yy]$ ]]; then
                    local fstype=$(lsblk -no FSTYPE "$device")
                    case $fstype in
                        ext2|ext3|ext4)
                            sudo e2fsck -l "/tmp/badblocks_$(basename "$device").txt" "$device"
                            ;;
                        *)
                            log_message "WARNING" "Bad block marking not supported for $fstype"
                            ;;
                    esac
                fi
            else
                log_message "SUCCESS" "No bad blocks found"
            fi
        else
            log_message "ERROR" "Bad block scan failed"
        fi
    fi
}

check_smart_status() {
    local device=$1
    
    # Get the disk device (remove partition number)
    local disk_device=$(echo "$device" | sed 's/[0-9]*$//')
    
    log_message "INFO" "Checking SMART status for $disk_device..."
    
    if command -v smartctl >/dev/null 2>&1; then
        if sudo smartctl -H "$disk_device" 2>/dev/null | grep -q "PASSED"; then
            log_message "SUCCESS" "SMART status: PASSED"
        else
            log_message "ERROR" "SMART status: FAILED or unavailable"
            log_message "WARNING" "Drive may be failing - backup data immediately"
            
            echo "View detailed SMART information? (y/N): "
            read -n 1 view_smart
            echo
            
            if [[ $view_smart =~ ^[Yy]$ ]]; then
                sudo smartctl -a "$disk_device" | less
            fi
        fi
    else
        log_message "WARNING" "smartctl not available, cannot check SMART status"
    fi
}

interactive_filesystem_repair() {
    echo -e "${BOLD}Filesystem Repair Utility${NC}"
    echo
    
    detect_filesystems
    
    echo "Select operation:"
    echo "1) Check and repair specific filesystem"
    echo "2) Check all filesystems"
    echo "3) Scan for bad blocks"
    echo "4) Check SMART status"
    echo "5) Advanced filesystem operations"
    echo
    
    read -p "Select option (1-5): " main_option
    
    case $main_option in
        1)
            read -p "Enter device path (e.g., /dev/sda1): " device
            if [ ! -b "$device" ]; then
                log_message "ERROR" "Device $device does not exist"
                return 1
            fi
            
            local fstype=$(lsblk -no FSTYPE "$device" 2>/dev/null || echo "unknown")
            log_message "INFO" "Filesystem type: $fstype"
            
            case $fstype in
                ext2|ext3|ext4)
                    check_ext_filesystem "$device" "no"
                    ;;
                xfs)
                    check_xfs_filesystem "$device"
                    ;;
                ntfs)
                    check_ntfs_filesystem "$device"
                    ;;
                vfat|fat32)
                    check_fat_filesystem "$device"
                    ;;
                *)
                    log_message "ERROR" "Unsupported filesystem type: $fstype"
                    return 1
                    ;;
            esac
            ;;
        2)
            log_message "INFO" "Checking all filesystems..."
            lsblk -f | grep -E 'ext[234]|xfs|ntfs|vfat' | while read line; do
                local device="/dev/$(echo "$line" | awk '{print $1}' | sed 's/[├└─]//g' | tr -d '└├─ ')"
                local fstype=$(echo "$line" | awk '{print $2}')
                
                if [ -b "$device" ]; then
                    case $fstype in
                        ext2|ext3|ext4)
                            check_ext_filesystem "$device" "no"
                            ;;
                        xfs)
                            check_xfs_filesystem "$device"
                            ;;
                        ntfs)
                            check_ntfs_filesystem "$device"
                            ;;
                        vfat)
                            check_fat_filesystem "$device"
                            ;;
                    esac
                fi
            done
            ;;
        3)
            read -p "Enter device path for bad block scan: " device
            if [ ! -b "$device" ]; then
                log_message "ERROR" "Device $device does not exist"
                return 1
            fi
            scan_bad_blocks "$device"
            ;;
        4)
            read -p "Enter device path for SMART check: " device
            check_smart_status "$device"
            ;;
        5)
            echo "Advanced operations:"
            echo "1) Force filesystem check"
            echo "2) Create filesystem backup"
            echo "3) Clone partition"
            
            read -p "Select advanced option: " adv_option
            
            case $adv_option in
                1)
                    read -p "Enter device path: " device
                    check_ext_filesystem "$device" "yes"
                    ;;
                2)
                    read -p "Enter source device: " src_device
                    read -p "Enter backup file path: " backup_file
                    log_message "INFO" "Creating filesystem backup..."
                    if sudo dd if="$src_device" of="$backup_file" bs=4M status=progress; then
                        log_message "SUCCESS" "Backup created: $backup_file"
                    else
                        log_message "ERROR" "Backup failed"
                    fi
                    ;;
                3)
                    read -p "Enter source device: " src_device
                    read -p "Enter destination device: " dst_device
                    log_message "WARNING" "This will overwrite $dst_device completely"
                    read -p "Continue? (yes/no): " confirm
                    if [ "$confirm" = "yes" ]; then
                        log_message "INFO" "Cloning partition..."
                        if sudo dd if="$src_device" of="$dst_device" bs=4M status=progress; then
                            log_message "SUCCESS" "Partition cloned successfully"
                        else
                            log_message "ERROR" "Cloning failed"
                        fi
                    fi
                    ;;
            esac
            ;;
        *)
            log_message "ERROR" "Invalid option"
            return 1
            ;;
    esac
}

main() {
    interactive_filesystem_repair
}

main "$@"