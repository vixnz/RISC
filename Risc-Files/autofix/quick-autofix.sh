#!/bin/bash
#
# Quick AutoFix - Automated System Repair
# Detects and fixes common Linux system issues automatically
#

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
BOLD='\033[1m'
NC='\033[0m'

LOG_FILE="/tmp/autofix.log"

log_message() {
    local level=$1
    local message=$2
    echo "$(date): [$level] $message" >> "$LOG_FILE"
    
    case $level in
        "INFO") echo -e "${BLUE}[INFO]${NC} $message" ;;
        "SUCCESS") echo -e "${GREEN}[SUCCESS]${NC} $message" ;;
        "WARNING") echo -e "${YELLOW}[WARNING]${NC} $message" ;;
        "ERROR") echo -e "${RED}[ERROR]${NC} $message" ;;
    esac
}

check_root_filesystem() {
    log_message "INFO" "Checking root filesystem..."
    
    # Find Linux partitions
    local linux_partitions=$(lsblk -f | grep -E 'ext[234]|xfs|btrfs' | awk '{print $1}' | sed 's/[├└─]//g' | tr -d '└├─ ')
    
    for partition in $linux_partitions; do
        if [ -b "/dev/$partition" ]; then
            log_message "INFO" "Checking /dev/$partition..."
            
            # Check filesystem
            case $(blkid -o value -s TYPE "/dev/$partition") in
                ext2|ext3|ext4)
                    if sudo fsck.ext4 -p "/dev/$partition" 2>/dev/null; then
                        log_message "SUCCESS" "Filesystem /dev/$partition is clean"
                    else
                        log_message "WARNING" "Filesystem errors found on /dev/$partition, attempting repair..."
                        if sudo fsck.ext4 -y "/dev/$partition"; then
                            log_message "SUCCESS" "Repaired filesystem /dev/$partition"
                        else
                            log_message "ERROR" "Failed to repair /dev/$partition"
                        fi
                    fi
                    ;;
                xfs)
                    if sudo xfs_repair -n "/dev/$partition" 2>/dev/null; then
                        log_message "SUCCESS" "XFS filesystem /dev/$partition is clean"
                    else
                        log_message "WARNING" "XFS filesystem errors found, attempting repair..."
                        if sudo xfs_repair "/dev/$partition"; then
                            log_message "SUCCESS" "Repaired XFS filesystem /dev/$partition"
                        else
                            log_message "ERROR" "Failed to repair XFS filesystem /dev/$partition"
                        fi
                    fi
                    ;;
            esac
        fi
    done
}

fix_boot_issues() {
    log_message "INFO" "Checking for boot issues..."
    
    # Find EFI and boot partitions
    local efi_partition=$(lsblk -f | grep -i efi | head -1 | awk '{print $1}' | sed 's/[├└─]//g' | tr -d '└├─ ')
    local boot_partitions=$(lsblk -f | grep -E '/boot|/boot/efi' | awk '{print $1}' | sed 's/[├└─]//g' | tr -d '└├─ ')
    
    # Check if GRUB is installed
    if command -v grub-install >/dev/null 2>&1; then
        log_message "INFO" "GRUB found, checking installation..."
        
        # Find the disk containing the root filesystem
        local root_disk=$(df / 2>/dev/null | tail -1 | awk '{print $1}' | sed 's/[0-9]*$//' 2>/dev/null || echo "")
        
        if [ -n "$root_disk" ] && [ -b "$root_disk" ]; then
            log_message "INFO" "Reinstalling GRUB to $root_disk..."
            if sudo grub-install "$root_disk" 2>/dev/null; then
                log_message "SUCCESS" "GRUB installed successfully"
                if sudo grub-mkconfig -o /boot/grub/grub.cfg 2>/dev/null; then
                    log_message "SUCCESS" "GRUB configuration updated"
                fi
            else
                log_message "WARNING" "Failed to install GRUB automatically"
            fi
        fi
    fi
}

fix_network_issues() {
    log_message "INFO" "Checking network connectivity..."
    
    # Check if network manager is running
    if ! systemctl is-active --quiet NetworkManager 2>/dev/null; then
        log_message "INFO" "Starting NetworkManager..."
        if sudo systemctl start NetworkManager 2>/dev/null; then
            log_message "SUCCESS" "NetworkManager started"
        else
            log_message "WARNING" "Failed to start NetworkManager"
        fi
    fi
    
    # Check internet connectivity
    if ping -c 1 8.8.8.8 >/dev/null 2>&1; then
        log_message "SUCCESS" "Internet connectivity is working"
    else
        log_message "WARNING" "No internet connectivity detected"
        
        # Try to bring up network interfaces
        for interface in $(ip link show | grep -E '^[0-9]+:' | grep -v lo | awk -F': ' '{print $2}' | cut -d'@' -f1); do
            log_message "INFO" "Bringing up interface $interface..."
            if sudo ip link set "$interface" up 2>/dev/null; then
                sudo dhclient "$interface" 2>/dev/null &
            fi
        done
        
        sleep 5
        if ping -c 1 8.8.8.8 >/dev/null 2>&1; then
            log_message "SUCCESS" "Network connectivity restored"
        fi
    fi
}

check_system_services() {
    log_message "INFO" "Checking critical system services..."
    
    local critical_services=("dbus" "systemd-logind" "NetworkManager")
    
    for service in "${critical_services[@]}"; do
        if systemctl list-unit-files | grep -q "^$service"; then
            if ! systemctl is-active --quiet "$service" 2>/dev/null; then
                log_message "INFO" "Starting $service..."
                if sudo systemctl start "$service" 2>/dev/null; then
                    log_message "SUCCESS" "Started $service"
                else
                    log_message "WARNING" "Failed to start $service"
                fi
            else
                log_message "SUCCESS" "$service is running"
            fi
        fi
    done
}

check_disk_space() {
    log_message "INFO" "Checking disk space..."
    
    # Check for partitions with less than 10% free space
    df -h | awk 'NR>1 {gsub("%","",$5); if($5>90) print $0}' | while read line; do
        local partition=$(echo "$line" | awk '{print $6}')
        local usage=$(echo "$line" | awk '{print $5}')
        log_message "WARNING" "Partition $partition is ${usage}% full"
        
        # Try to clean up common temp directories
        if [ "$partition" = "/" ] || [ "$partition" = "/tmp" ]; then
            log_message "INFO" "Cleaning temporary files..."
            sudo find /tmp -type f -atime +7 -delete 2>/dev/null || true
            sudo find /var/tmp -type f -atime +7 -delete 2>/dev/null || true
            
            # Clean package cache if available
            if command -v apt-get >/dev/null 2>&1; then
                sudo apt-get clean 2>/dev/null || true
            fi
            if command -v yum >/dev/null 2>&1; then
                sudo yum clean all 2>/dev/null || true
            fi
        fi
    done
}

check_memory_issues() {
    log_message "INFO" "Checking memory usage..."
    
    local mem_usage=$(free | awk 'FNR==2{printf "%.2f", ($3/($3+$4))*100}')
    local swap_usage=$(free | awk 'FNR==3{if($2>0) printf "%.2f", ($3/$2)*100; else print "0"}')
    
    if (( $(echo "$mem_usage > 90" | bc -l) )); then
        log_message "WARNING" "High memory usage: ${mem_usage}%"
        log_message "INFO" "Attempting to free memory..."
        
        # Drop caches
        sudo sync
        echo 3 | sudo tee /proc/sys/vm/drop_caches > /dev/null
        log_message "SUCCESS" "Memory caches cleared"
    else
        log_message "SUCCESS" "Memory usage is normal: ${mem_usage}%"
    fi
    
    if (( $(echo "$swap_usage > 50" | bc -l) )); then
        log_message "WARNING" "High swap usage: ${swap_usage}%"
    fi
}

run_security_checks() {
    log_message "INFO" "Running basic security checks..."
    
    # Check for common security issues
    
    # Check SSH configuration
    if [ -f /etc/ssh/sshd_config ]; then
        if grep -q "PermitRootLogin yes" /etc/ssh/sshd_config 2>/dev/null; then
            log_message "WARNING" "SSH root login is enabled - security risk"
        fi
        
        if grep -q "PasswordAuthentication yes" /etc/ssh/sshd_config 2>/dev/null; then
            log_message "WARNING" "SSH password authentication is enabled"
        fi
    fi
    
    # Check for world-writable files in critical directories
    local world_writable=$(find /etc /usr/bin /usr/sbin -type f -perm -002 2>/dev/null | head -5)
    if [ -n "$world_writable" ]; then
        log_message "WARNING" "Found world-writable files in system directories"
        echo "$world_writable" | while read file; do
            log_message "WARNING" "World-writable: $file"
        done
    fi
}

generate_report() {
    log_message "INFO" "Generating repair report..."
    
    echo
    echo -e "${BOLD}═══ AUTOFIX REPORT ═══${NC}"
    echo
    echo "Report generated: $(date)"
    echo "Log file: $LOG_FILE"
    echo
    
    local total_issues=$(grep -c "\[ERROR\]" "$LOG_FILE" 2>/dev/null || echo "0")
    local fixed_issues=$(grep -c "\[SUCCESS\].*repaired\|fixed\|restored" "$LOG_FILE" 2>/dev/null || echo "0")
    local warnings=$(grep -c "\[WARNING\]" "$LOG_FILE" 2>/dev/null || echo "0")
    
    echo "Issues found: $total_issues"
    echo "Issues fixed: $fixed_issues"
    echo "Warnings: $warnings"
    echo
    
    if [ "$total_issues" -eq 0 ] && [ "$warnings" -eq 0 ]; then
        echo -e "${GREEN}✓ System appears to be healthy${NC}"
    elif [ "$total_issues" -eq "$fixed_issues" ]; then
        echo -e "${GREEN}✓ All detected issues have been resolved${NC}"
    else
        echo -e "${YELLOW}⚠ Some issues require manual attention${NC}"
    fi
    
    echo
    echo "For detailed information, check: $LOG_FILE"
}

main() {
    echo -e "${BOLD}Linux System AutoFix Utility${NC}"
    echo "Starting automated system diagnosis and repair..."
    echo
    
    # Initialize log file
    echo "AutoFix started at $(date)" > "$LOG_FILE"
    
    # Run all checks
    check_root_filesystem
    fix_boot_issues
    fix_network_issues
    check_system_services
    check_disk_space
    check_memory_issues
    run_security_checks
    
    # Generate final report
    generate_report
}

main "$@"