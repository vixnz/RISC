#!/bin/bash
#
# Data Recovery Tool
# Recover deleted files and repair corrupted data
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

scan_deleted_files() {
    log_message "INFO" "Scanning for recoverable deleted files..."
    
    read -p "Enter the device/partition to scan (e.g., /dev/sda1): " device
    
    if [ ! -b "$device" ]; then
        log_message "ERROR" "Device $device does not exist"
        return 1
    fi
    
    # Check if device is mounted
    if mount | grep -q "$device"; then
        log_message "WARNING" "Device $device is currently mounted"
        echo "For best results, the device should be unmounted. Continue anyway? (y/N): "
        read -n 1 continue_mounted
        echo
        if [[ ! $continue_mounted =~ ^[Yy]$ ]]; then
            return 1
        fi
    fi
    
    # Create recovery directory
    local recovery_dir="/tmp/recovery_$(date +%Y%m%d_%H%M%S)"
    mkdir -p "$recovery_dir"
    
    log_message "INFO" "Recovery directory created: $recovery_dir"
    
    # Use TestDisk/PhotoRec if available
    if command -v photorec >/dev/null 2>&1; then
        echo "Use PhotoRec for file recovery? (y/N): "
        read -n 1 use_photorec
        echo
        
        if [[ $use_photorec =~ ^[Yy]$ ]]; then
            log_message "INFO" "Starting PhotoRec..."
            log_message "INFO" "PhotoRec will open in interactive mode"
            log_message "INFO" "Select the device and choose destination: $recovery_dir"
            sudo photorec
            return 0
        fi
    fi
    
    # Use debugfs for ext2/3/4 filesystems
    local fstype=$(lsblk -no FSTYPE "$device" 2>/dev/null || echo "unknown")
    
    if [[ "$fstype" =~ ^ext[234]$ ]]; then
        log_message "INFO" "Detected ext filesystem, using debugfs recovery method..."
        
        echo "Enter approximate deletion time (YYYY-MM-DD HH:MM or 'recent' for last 24h): "
        read deletion_time
        
        if [ "$deletion_time" = "recent" ]; then
            deletion_time=$(date -d "24 hours ago" "+%Y-%m-%d %H:%M")
        fi
        
        log_message "INFO" "Scanning for files deleted around: $deletion_time"
        
        # Use debugfs to find deleted files
        sudo debugfs -R "lsdel" "$device" 2>/dev/null | head -50 > "$recovery_dir/deleted_inodes.txt"
        
        local deleted_count=$(wc -l < "$recovery_dir/deleted_inodes.txt")
        log_message "INFO" "Found $deleted_count potentially recoverable inodes"
        
        if [ "$deleted_count" -gt 0 ]; then
            echo "Attempt to recover files? This may take time (y/N): "
            read -n 1 recover_files
            echo
            
            if [[ $recover_files =~ ^[Yy]$ ]]; then
                local count=0
                while read inode_line; do
                    local inode=$(echo "$inode_line" | awk '{print $1}')
                    if [[ "$inode" =~ ^[0-9]+$ ]] && [ "$inode" -gt 0 ]; then
                        local output_file="$recovery_dir/recovered_file_$inode"
                        if sudo debugfs -R "dump <$inode> $output_file" "$device" 2>/dev/null; then
                            if [ -s "$output_file" ]; then
                                count=$((count + 1))
                                log_message "SUCCESS" "Recovered file: $output_file"
                            else
                                rm -f "$output_file"
                            fi
                        fi
                    fi
                    
                    # Limit recovery to prevent overwhelming
                    if [ "$count" -ge 20 ]; then
                        log_message "INFO" "Recovered 20 files, stopping to prevent overflow"
                        break
                    fi
                done < "$recovery_dir/deleted_inodes.txt"
                
                log_message "SUCCESS" "Recovery completed. Recovered $count files to $recovery_dir"
            fi
        fi
    else
        log_message "WARNING" "Filesystem type $fstype not supported for automated recovery"
        log_message "INFO" "Try using PhotoRec or TestDisk manually"
    fi
    
    # Show recovery results
    if [ -d "$recovery_dir" ]; then
        local recovered_files=$(find "$recovery_dir" -type f -size +0c | wc -l)
        if [ "$recovered_files" -gt 0 ]; then
            log_message "SUCCESS" "Recovery summary:"
            echo "  Recovery directory: $recovery_dir"
            echo "  Files recovered: $recovered_files"
            
            echo "View recovered files? (y/N): "
            read -n 1 view_files
            echo
            
            if [[ $view_files =~ ^[Yy]$ ]]; then
                ls -la "$recovery_dir"
            fi
        fi
    fi
}

backup_important_data() {
    log_message "INFO" "Creating backup of important system data..."
    
    read -p "Enter backup destination directory: " backup_dest
    
    if [ ! -d "$backup_dest" ]; then
        mkdir -p "$backup_dest" || {
            log_message "ERROR" "Cannot create backup directory"
            return 1
        }
    fi
    
    local backup_dir="$backup_dest/system_backup_$(date +%Y%m%d_%H%M%S)"
    mkdir -p "$backup_dir"
    
    log_message "INFO" "Backup directory: $backup_dir"
    
    # Define important directories and files
    local important_items=(
        "/etc"
        "/home"
        "/root"
        "/var/log"
        "/opt"
    )
    
    echo "Select items to backup:"
    for i in "${!important_items[@]}"; do
        echo "$((i+1))) ${important_items[i]}"
    done
    echo "$((${#important_items[@]}+1))) Custom path"
    echo "$((${#important_items[@]}+2))) All of the above"
    
    read -p "Enter selections (space-separated numbers): " selections
    
    for selection in $selections; do
        case $selection in
            $((${#important_items[@]}+1)))
                read -p "Enter custom path to backup: " custom_path
                if [ -e "$custom_path" ]; then
                    log_message "INFO" "Backing up $custom_path..."
                    rsync -av "$custom_path" "$backup_dir/" 2>/dev/null || {
                        log_message "WARNING" "Failed to backup $custom_path"
                    }
                fi
                ;;
            $((${#important_items[@]}+2)))
                for item in "${important_items[@]}"; do
                    if [ -e "$item" ]; then
                        log_message "INFO" "Backing up $item..."
                        rsync -av "$item" "$backup_dir/" 2>/dev/null || {
                            log_message "WARNING" "Failed to backup $item"
                        }
                    fi
                done
                ;;
            *)
                if [ "$selection" -ge 1 ] && [ "$selection" -le ${#important_items[@]} ]; then
                    local item="${important_items[$((selection-1))]}"
                    if [ -e "$item" ]; then
                        log_message "INFO" "Backing up $item..."
                        rsync -av "$item" "$backup_dir/" 2>/dev/null || {
                            log_message "WARNING" "Failed to backup $item"
                        }
                    fi
                fi
                ;;
        esac
    done
    
    # Create backup summary
    {
        echo "Backup Summary"
        echo "=============="
        echo "Date: $(date)"
        echo "Source system: $(hostname)"
        echo "Backup location: $backup_dir"
        echo
        echo "Backed up items:"
        find "$backup_dir" -type d -maxdepth 2 | sort
        echo
        echo "Total size: $(du -sh "$backup_dir" | cut -f1)"
        echo "File count: $(find "$backup_dir" -type f | wc -l)"
    } > "$backup_dir/backup_summary.txt"
    
    log_message "SUCCESS" "Backup completed successfully"
    log_message "INFO" "Backup summary saved to: $backup_dir/backup_summary.txt"
}

recover_partition_table() {
    log_message "INFO" "Attempting to recover partition table..."
    
    read -p "Enter disk device (e.g., /dev/sda): " disk
    
    if [ ! -b "$disk" ]; then
        log_message "ERROR" "Device $disk does not exist"
        return 1
    fi
    
    log_message "WARNING" "This operation will scan the disk for lost partitions"
    log_message "WARNING" "It's recommended to backup important data first"
    
    echo "Continue with partition recovery? (y/N): "
    read -n 1 continue_recovery
    echo
    
    if [[ ! $continue_recovery =~ ^[Yy]$ ]]; then
        return 0
    fi
    
    # Use TestDisk if available
    if command -v testdisk >/dev/null 2>&1; then
        log_message "INFO" "Starting TestDisk for partition recovery..."
        log_message "INFO" "TestDisk will open in interactive mode"
        log_message "INFO" "Follow the wizard to analyze and recover partitions"
        sudo testdisk "$disk"
    else
        log_message "ERROR" "TestDisk not available for partition recovery"
        log_message "INFO" "Install testdisk package and try again"
        return 1
    fi
}

clone_failing_drive() {
    log_message "INFO" "Cloning failing drive to preserve data..."
    
    read -p "Enter source device (failing drive, e.g., /dev/sda): " source_drive
    read -p "Enter destination device (good drive, e.g., /dev/sdb): " dest_drive
    
    if [ ! -b "$source_drive" ] || [ ! -b "$dest_drive" ]; then
        log_message "ERROR" "One or both devices do not exist"
        return 1
    fi
    
    # Check destination size
    local source_size=$(lsblk -bno SIZE "$source_drive")
    local dest_size=$(lsblk -bno SIZE "$dest_drive")
    
    if [ "$dest_size" -lt "$source_size" ]; then
        log_message "ERROR" "Destination drive is smaller than source drive"
        return 1
    fi
    
    log_message "WARNING" "This will completely overwrite $dest_drive"
    log_message "WARNING" "All data on $dest_drive will be lost"
    
    echo "Continue with cloning? Type 'YES' to proceed: "
    read confirmation
    
    if [ "$confirmation" != "YES" ]; then
        log_message "INFO" "Cloning cancelled"
        return 0
    fi
    
    # Use ddrescue if available (better for failing drives)
    if command -v ddrescue >/dev/null 2>&1; then
        log_message "INFO" "Using ddrescue for fault-tolerant cloning..."
        
        local logfile="/tmp/ddrescue_$(date +%Y%m%d_%H%M%S).log"
        
        log_message "INFO" "Starting clone operation (this may take hours)..."
        log_message "INFO" "Progress will be shown. Press Ctrl+C to pause/resume later"
        
        if sudo ddrescue -f -n "$source_drive" "$dest_drive" "$logfile"; then
            log_message "SUCCESS" "Initial clone completed"
            
            # Second pass to retry failed sectors
            log_message "INFO" "Running second pass to retry failed sectors..."
            sudo ddrescue -f -d -r3 "$source_drive" "$dest_drive" "$logfile"
            
            log_message "SUCCESS" "Drive cloning completed"
            log_message "INFO" "Log file saved to: $logfile"
        else
            log_message "ERROR" "Cloning failed or was interrupted"
            log_message "INFO" "You can resume with: ddrescue -f -d -r3 $source_drive $dest_drive $logfile"
        fi
    else
        # Fallback to dd with error recovery
        log_message "WARNING" "ddrescue not available, using dd (less reliable for failing drives)"
        
        echo "Continue with dd? (y/N): "
        read -n 1 use_dd
        echo
        
        if [[ $use_dd =~ ^[Yy]$ ]]; then
            log_message "INFO" "Starting clone with dd..."
            if sudo dd if="$source_drive" of="$dest_drive" bs=4M conv=noerror,sync status=progress; then
                log_message "SUCCESS" "Drive cloning completed"
            else
                log_message "ERROR" "Cloning failed"
            fi
        fi
    fi
}

repair_corrupted_files() {
    log_message "INFO" "Attempting to repair corrupted files..."
    
    read -p "Enter path to corrupted file or directory: " target_path
    
    if [ ! -e "$target_path" ]; then
        log_message "ERROR" "Path $target_path does not exist"
        return 1
    fi
    
    local backup_path="${target_path}.backup.$(date +%s)"
    
    # Create backup
    log_message "INFO" "Creating backup: $backup_path"
    cp -r "$target_path" "$backup_path"
    
    if [ -f "$target_path" ]; then
        # Single file repair
        local file_type=$(file "$target_path" | cut -d: -f2)
        log_message "INFO" "File type detected: $file_type"
        
        case "$file_type" in
            *"gzip compressed"*)
                log_message "INFO" "Attempting gzip repair..."
                if gzip -t "$target_path" 2>/dev/null; then
                    log_message "SUCCESS" "Gzip file is valid"
                else
                    log_message "WARNING" "Gzip file is corrupted"
                    # Try to recover what we can
                    gunzip -c "$target_path" > "${target_path}.recovered" 2>/dev/null || true
                fi
                ;;
            *"tar archive"*)
                log_message "INFO" "Attempting tar repair..."
                if tar -tf "$target_path" >/dev/null 2>&1; then
                    log_message "SUCCESS" "Tar file is valid"
                else
                    log_message "WARNING" "Tar file is corrupted"
                    # Try to extract what we can
                    tar -xf "$target_path" -C "/tmp" --ignore-failed-read 2>/dev/null || true
                fi
                ;;
            *"UTF-8 text"*|*"ASCII text"*)
                log_message "INFO" "Checking text file for corruption..."
                # Check for null bytes or other corruption indicators
                if grep -q $'\0' "$target_path"; then
                    log_message "WARNING" "File contains null bytes (possibly corrupted)"
                    # Remove null bytes
                    tr -d '\0' < "$target_path" > "${target_path}.cleaned"
                    log_message "INFO" "Cleaned file saved as ${target_path}.cleaned"
                else
                    log_message "SUCCESS" "Text file appears intact"
                fi
                ;;
            *)
                log_message "INFO" "Generic file repair attempt..."
                # Check file size and basic integrity
                if [ ! -s "$target_path" ]; then
                    log_message "ERROR" "File is empty (0 bytes)"
                else
                    log_message "INFO" "File size: $(stat -f%z "$target_path" 2>/dev/null || stat -c%s "$target_path") bytes"
                    log_message "SUCCESS" "File appears to have content"
                fi
                ;;
        esac
    else
        # Directory repair
        log_message "INFO" "Checking directory integrity..."
        
        # Check for filesystem errors
        local mount_point=$(df "$target_path" | tail -1 | awk '{print $6}')
        local device=$(df "$target_path" | tail -1 | awk '{print $1}')
        
        log_message "INFO" "Directory is on device: $device, mount point: $mount_point"
        
        # Check directory permissions
        local perms=$(stat -c%a "$target_path" 2>/dev/null || stat -f%Mp%Lp "$target_path" 2>/dev/null)
        log_message "INFO" "Directory permissions: $perms"
        
        # Count files and check for issues
        local file_count=$(find "$target_path" -type f 2>/dev/null | wc -l)
        local dir_count=$(find "$target_path" -type d 2>/dev/null | wc -l)
        
        log_message "INFO" "Contains: $file_count files, $dir_count directories"
        
        # Check for files with problematic names
        local problematic_files=$(find "$target_path" -name "*[[:cntrl:]]*" 2>/dev/null | wc -l)
        if [ "$problematic_files" -gt 0 ]; then
            log_message "WARNING" "Found $problematic_files files with control characters in names"
        fi
    fi
    
    log_message "INFO" "Repair attempt completed"
    log_message "INFO" "Original backed up to: $backup_path"
}

interactive_data_recovery() {
    echo -e "${BOLD}Data Recovery Tool${NC}"
    echo
    
    echo "Select recovery operation:"
    echo "1) Scan for deleted files"
    echo "2) Backup important data"
    echo "3) Recover partition table"
    echo "4) Clone failing drive"
    echo "5) Repair corrupted files"
    echo "6) File system analysis"
    echo
    
    read -p "Select option (1-6): " recovery_option
    
    case $recovery_option in
        1) scan_deleted_files ;;
        2) backup_important_data ;;
        3) recover_partition_table ;;
        4) clone_failing_drive ;;
        5) repair_corrupted_files ;;
        6)
            echo -e "${BOLD}File System Analysis${NC}"
            echo
            echo "Available file systems:"
            lsblk -f
            echo
            read -p "Enter device to analyze: " analyze_device
            
            if [ -b "$analyze_device" ]; then
                local fstype=$(lsblk -no FSTYPE "$analyze_device")
                echo "File system type: $fstype"
                echo "Mount status: $(mount | grep "$analyze_device" || echo "Not mounted")"
                echo "Size: $(lsblk -no SIZE "$analyze_device")"
                
                case $fstype in
                    ext*)
                        sudo tune2fs -l "$analyze_device" 2>/dev/null | head -20
                        ;;
                    xfs)
                        sudo xfs_info "$analyze_device" 2>/dev/null || echo "Mount the filesystem to see xfs_info"
                        ;;
                    *)
                        log_message "INFO" "Limited analysis available for $fstype"
                        ;;
                esac
            else
                log_message "ERROR" "Device not found"
            fi
            ;;
        *)
            log_message "ERROR" "Invalid option"
            return 1
            ;;
    esac
}

main() {
    interactive_data_recovery
}

main "$@"