#!/bin/bash
#
# USB Creation Utility
# Creates a bootable USB drive from the rescue ISO
#

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

show_usage() {
    echo "Usage: $0 <iso-file> <device>"
    echo ""
    echo "Example: $0 linux-rescue-drive-1.0.iso /dev/sdb"
    echo ""
    echo "Available USB/Removable devices:"
    show_safe_devices
}

show_safe_devices() {
    echo "Device    Size      Model                 Removable  Mounted"
    echo "------    ----      -----                 ---------  -------"
    
    for dev in /sys/block/sd* /sys/block/nvme*; do
        if [ -d "$dev" ]; then
            local device_name=$(basename "$dev")
            local device_path="/dev/$device_name"
            
            # Check if it's a real block device
            if [ ! -b "$device_path" ]; then
                continue
            fi
            
            local size=$(lsblk -dno SIZE "$device_path" 2>/dev/null || echo "Unknown")
            local model=$(lsblk -dno MODEL "$device_path" 2>/dev/null | tr -d ' ' || echo "Unknown")
            local removable="No"
            local mounted="No"
            
            # Check if removable
            if [ -f "$dev/removable" ] && [ "$(cat "$dev/removable")" = "1" ]; then
                removable="Yes"
            fi
            
            # Check if any partition is mounted
            if lsblk -no MOUNTPOINT "$device_path" 2>/dev/null | grep -q "/"; then
                mounted="Yes"
            fi
            
            # Only show removable devices or warn about fixed disks
            if [ "$removable" = "Yes" ]; then
                printf "%-8s  %-8s  %-20s  %-9s  %-7s\n" "$device_name" "$size" "$model" "$removable" "$mounted"
            else
                printf "%-8s  %-8s  %-20s  %-9s  %-7s  (FIXED DISK - BE CAREFUL!)\n" "$device_name" "$size" "$model" "$removable" "$mounted"
            fi
        fi
    done
}

check_dependencies() {
    local deps=("dd" "sync" "partprobe")
    for dep in "${deps[@]}"; do
        if ! command -v $dep &> /dev/null; then
            log_error "Missing dependency: $dep"
            exit 1
        fi
    done
}

verify_device() {
    local device=$1
    
    if [ ! -b "$device" ]; then
        log_error "Device $device does not exist or is not a block device"
        exit 1
    fi
    
    # Extract device name without /dev/
    local device_name=$(basename "$device")
    local sys_path="/sys/block/$device_name"
    
    # Check if device exists in sysfs
    if [ ! -d "$sys_path" ]; then
        log_error "Device $device not found in system"
        exit 1
    fi
    
    # Safety check: Warn if not removable
    if [ -f "$sys_path/removable" ]; then
        local removable=$(cat "$sys_path/removable")
        if [ "$removable" != "1" ]; then
            log_warning "WARNING: $device appears to be a FIXED DISK, not removable storage!"
            echo "This could be your main hard drive. Are you absolutely sure?"
            read -p "Type 'I UNDERSTAND THE RISK' to continue: " risk_acknowledge
            if [ "$risk_acknowledge" != "I UNDERSTAND THE RISK" ]; then
                log_error "Operation cancelled for safety"
                exit 1
            fi
        fi
    fi
    
    # Check if any partition is mounted
    if lsblk -no MOUNTPOINT "$device" 2>/dev/null | grep -q "/"; then
        log_error "Device $device has mounted partitions. Please unmount all partitions first:"
        lsblk "$device"
        echo
        echo "To unmount all partitions, run:"
        lsblk -ln -o NAME "$device" | tail -n +2 | while read partition; do
            echo "  sudo umount /dev/$partition"
        done
        exit 1
    fi
    
    # Check device size (warn if too small or suspiciously large)
    local size_bytes=$(lsblk -bno SIZE "$device" 2>/dev/null || echo "0")
    local size_gb=$((size_bytes / 1024 / 1024 / 1024))
    
    if [ "$size_gb" -lt 4 ]; then
        log_error "Device $device is too small (${size_gb}GB). Need at least 4GB for rescue drive."
        exit 1
    fi
    
    if [ "$size_gb" -gt 2000 ]; then
        log_warning "WARNING: Device $device is very large (${size_gb}GB). This is unusual for USB drives."
        read -p "Are you sure this is the correct device? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            exit 1
        fi
    fi
    
    # Final device information display
    log_info "Device verification passed for $device"
    echo "Device details:"
    lsblk -o NAME,SIZE,TYPE,MODEL,SERIAL "$device" 2>/dev/null || lsblk "$device"
}

verify_iso() {
    local iso_file=$1
    
    if [ ! -f "$iso_file" ]; then
        log_error "ISO file $iso_file does not exist"
        exit 1
    fi
    
    # Check file size
    local iso_size=$(stat -c%s "$iso_file")
    local iso_size_mb=$((iso_size / 1024 / 1024))
    log_info "ISO file size: ${iso_size_mb}MB"
    
    # Check if it's actually an ISO file
    if ! file "$iso_file" | grep -q "ISO 9660"; then
        log_warning "File $iso_file may not be a valid ISO image"
        read -p "Continue anyway? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            exit 1
        fi
    else
        log_success "ISO file verification passed"
    fi
    
    # Check for hybrid ISO (can be written directly to USB)
    if file "$iso_file" | grep -q "DOS/MBR"; then
        log_success "Hybrid ISO detected - suitable for direct USB writing"
    else
        log_warning "ISO may not be hybrid - bootability not guaranteed"
    fi
}

verify_usb_contents() {
    local device=$1
    
    log_info "Verifying USB drive contents..."
    
    # Wait for device to settle
    sleep 3
    
    # Check if partitions are visible
    local partitions=$(lsblk -ln -o NAME "$device" | tail -n +2 | wc -l)
    if [ "$partitions" -eq 0 ]; then
        log_error "No partitions found on USB drive after writing"
        return 1
    fi
    
    log_info "Found $partitions partition(s) on USB drive"
    
    # Try to mount and check critical files
    local mount_point="/tmp/usb_verify_$$"
    mkdir -p "$mount_point"
    
    # Find the first partition
    local first_partition=$(lsblk -ln -o NAME "$device" | sed -n '2p')
    if [ -z "$first_partition" ]; then
        log_error "Could not identify first partition"
        rmdir "$mount_point"
        return 1
    fi
    
    local partition_path="/dev/$first_partition"
    
    # Try to mount the partition (try different filesystem types)
    local mount_success=0
    for fstype in iso9660 vfat ext4; do
        if sudo mount -t "$fstype" "$partition_path" "$mount_point" 2>/dev/null; then
            mount_success=1
            log_success "Successfully mounted USB partition (filesystem: $fstype)"
            break
        fi
    done
    
    if [ "$mount_success" -eq 0 ]; then
        # Try mounting without specifying filesystem type
        if sudo mount "$partition_path" "$mount_point" 2>/dev/null; then
            mount_success=1
            log_success "Successfully mounted USB partition"
        else
            log_warning "Could not mount USB partition for verification"
            rmdir "$mount_point"
            return 0  # Don't fail completely, USB might still be bootable
        fi
    fi
    
    if [ "$mount_success" -eq 1 ]; then
        # Check for critical boot files
        local boot_files_found=0
        
        # Check for common boot files
        if [ -f "$mount_point/isolinux/isolinux.bin" ] || [ -f "$mount_point/syslinux/isolinux.bin" ]; then
            log_success "Found isolinux boot loader"
            boot_files_found=1
        fi
        
        if [ -d "$mount_point/boot/grub" ] || [ -d "$mount_point/grub" ]; then
            log_success "Found GRUB boot loader"
            boot_files_found=1
        fi
        
        if [ -d "$mount_point/EFI" ]; then
            log_success "Found EFI boot directory"
            boot_files_found=1
        fi
        
        if [ -f "$mount_point/casper/vmlinuz" ] || [ -f "$mount_point/live/vmlinuz" ] || [ -f "$mount_point/vmlinuz" ]; then
            log_success "Found Linux kernel"
            boot_files_found=1
        fi
        
        if [ -f "$mount_point/casper/initrd.lz" ] || [ -f "$mount_point/live/initrd.img" ] || [ -f "$mount_point/initrd.img" ]; then
            log_success "Found initial ramdisk"
            boot_files_found=1
        fi
        
        # Check disk usage
        local used_space=$(df "$mount_point" | tail -1 | awk '{print $3}')
        local total_space=$(df "$mount_point" | tail -1 | awk '{print $2}')
        local used_mb=$((used_space / 1024))
        log_info "USB drive usage: ${used_mb}MB"
        
        # Unmount
        sudo umount "$mount_point" 2>/dev/null || true
        rmdir "$mount_point"
        
        if [ "$boot_files_found" -eq 1 ]; then
            log_success "USB drive verification completed successfully"
            log_success "USB drive is ready for booting"
            return 0
        else
            log_warning "Boot files not found in expected locations"
            log_warning "USB may not boot properly"
            return 1
        fi
    fi
}

create_usb() {
    local iso_file=$1
    local device=$2
    
    log_info "Creating bootable USB drive..."
    log_warning "This will COMPLETELY ERASE all data on $device"
    
    # Get device info
    local device_info=$(lsblk -d -o NAME,SIZE,MODEL "$device" | tail -n 1)
    log_info "Target device: $device_info"
    
    # Final confirmation
    echo
    read -p "Are you absolutely sure you want to continue? Type 'YES' to proceed: " confirmation
    if [ "$confirmation" != "YES" ]; then
        log_info "Operation cancelled"
        exit 0
    fi
    
    # Unmount any mounted partitions
    log_info "Unmounting any mounted partitions..."
    for partition in $(lsblk -ln -o NAME "$device" | tail -n +2); do
        if grep -q "/dev/$partition" /proc/mounts; then
            sudo umount "/dev/$partition" 2>/dev/null || true
        fi
    done
    
    # Write ISO to device using dd (hybrid ISO approach)
    log_info "Writing ISO to $device (this may take several minutes)..."
    
    # Use dd with error checking and progress
    if ! sudo dd if="$iso_file" of="$device" bs=4M status=progress oflag=sync conv=fsync; then
        log_error "Failed to write ISO to device"
        exit 1
    fi
    
    # Ensure all data is written
    log_info "Syncing data to device..."
    sync
    sleep 2
    
    # Update partition table
    sudo partprobe "$device" 2>/dev/null || true
    sleep 2
    
    # Verify the USB drive was written correctly
    verify_usb_contents "$device"
}

main() {
    if [ $# -ne 2 ]; then
        show_usage
        exit 1
    fi
    
    local iso_file=$1
    local device=$2
    
    log_info "Linux Rescue Drive USB Creator"
    log_info "ISO file: $iso_file"
    log_info "Target device: $device"
    
    check_dependencies
    verify_iso "$iso_file"
    verify_device "$device"
    create_usb "$iso_file" "$device"
}

main "$@"