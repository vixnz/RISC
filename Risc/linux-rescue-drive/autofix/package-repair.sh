#!/bin/bash
#
# Package Management Repair
# Fix broken packages and package manager issues
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

detect_package_manager() {
    if command -v apt >/dev/null 2>&1; then
        echo "apt"
    elif command -v yum >/dev/null 2>&1; then
        echo "yum"
    elif command -v dnf >/dev/null 2>&1; then
        echo "dnf"
    elif command -v zypper >/dev/null 2>&1; then
        echo "zypper"
    elif command -v pacman >/dev/null 2>&1; then
        echo "pacman"
    else
        echo "unknown"
    fi
}

fix_apt_issues() {
    log_message "INFO" "Fixing APT package manager issues..."
    
    # Update package lists
    log_message "INFO" "Updating package lists..."
    if sudo apt update 2>/dev/null; then
        log_message "SUCCESS" "Package lists updated"
    else
        log_message "WARNING" "Failed to update package lists, trying to fix..."
        
        # Fix broken package lists
        sudo rm -rf /var/lib/apt/lists/*
        sudo apt clean
        sudo apt update
    fi
    
    # Fix broken packages
    log_message "INFO" "Checking for broken packages..."
    if sudo apt --fix-broken install -y 2>/dev/null; then
        log_message "SUCCESS" "Broken packages fixed"
    else
        log_message "WARNING" "Some broken packages could not be fixed automatically"
    fi
    
    # Configure pending packages
    log_message "INFO" "Configuring pending packages..."
    sudo dpkg --configure -a
    
    # Clean package cache
    log_message "INFO" "Cleaning package cache..."
    sudo apt clean
    sudo apt autoremove -y
    
    # Check for held packages
    local held_packages=$(apt-mark showheld)
    if [ -n "$held_packages" ]; then
        log_message "WARNING" "Found held packages:"
        echo "$held_packages"
    fi
}

fix_yum_dnf_issues() {
    local pm=$1
    log_message "INFO" "Fixing $pm package manager issues..."
    
    # Clean cache
    log_message "INFO" "Cleaning $pm cache..."
    sudo $pm clean all
    
    # Update package lists
    log_message "INFO" "Updating package metadata..."
    if sudo $pm check-update 2>/dev/null; then
        log_message "SUCCESS" "Package metadata updated"
    else
        # check-update returns 100 when updates are available, which is normal
        if [ $? -eq 100 ]; then
            log_message "SUCCESS" "Package metadata updated (updates available)"
        else
            log_message "WARNING" "Failed to update package metadata"
        fi
    fi
    
    # Fix broken packages
    log_message "INFO" "Checking for package issues..."
    if command -v package-cleanup >/dev/null 2>&1; then
        sudo package-cleanup --cleandupes -y
        sudo package-cleanup --orphans -y
    fi
    
    # Verify package database
    if sudo rpm --rebuilddb; then
        log_message "SUCCESS" "RPM database rebuilt"
    else
        log_message "WARNING" "Failed to rebuild RPM database"
    fi
}

fix_zypper_issues() {
    log_message "INFO" "Fixing Zypper package manager issues..."
    
    # Clean cache
    log_message "INFO" "Cleaning zypper cache..."
    sudo zypper clean -a
    
    # Refresh repositories
    log_message "INFO" "Refreshing repositories..."
    if sudo zypper refresh; then
        log_message "SUCCESS" "Repositories refreshed"
    else
        log_message "WARNING" "Some repositories could not be refreshed"
    fi
    
    # Verify package integrity
    log_message "INFO" "Verifying package integrity..."
    sudo zypper verify
}

fix_pacman_issues() {
    log_message "INFO" "Fixing Pacman package manager issues..."
    
    # Update package database
    log_message "INFO" "Updating package database..."
    if sudo pacman -Sy; then
        log_message "SUCCESS" "Package database updated"
    else
        log_message "WARNING" "Failed to update package database"
    fi
    
    # Check for corrupted packages
    log_message "INFO" "Checking package integrity..."
    if sudo pacman -Qkk >/dev/null 2>&1; then
        log_message "SUCCESS" "Package integrity check passed"
    else
        log_message "WARNING" "Some packages failed integrity check"
    fi
    
    # Clean cache
    log_message "INFO" "Cleaning package cache..."
    sudo pacman -Sc --noconfirm
}

repair_package_database() {
    local pm=$(detect_package_manager)
    
    log_message "INFO" "Detected package manager: $pm"
    
    case $pm in
        apt)
            fix_apt_issues
            ;;
        yum)
            fix_yum_dnf_issues "yum"
            ;;
        dnf)
            fix_yum_dnf_issues "dnf"
            ;;
        zypper)
            fix_zypper_issues
            ;;
        pacman)
            fix_pacman_issues
            ;;
        unknown)
            log_message "ERROR" "Unknown or unsupported package manager"
            return 1
            ;;
    esac
}

reinstall_critical_packages() {
    local pm=$(detect_package_manager)
    
    log_message "INFO" "Checking critical system packages..."
    
    local critical_packages=""
    
    case $pm in
        apt)
            critical_packages="libc6 systemd dbus network-manager"
            ;;
        yum|dnf)
            critical_packages="glibc systemd dbus NetworkManager"
            ;;
        zypper)
            critical_packages="glibc systemd dbus NetworkManager"
            ;;
        pacman)
            critical_packages="glibc systemd dbus networkmanager"
            ;;
    esac
    
    if [ -n "$critical_packages" ]; then
        for package in $critical_packages; do
            log_message "INFO" "Checking package: $package"
            
            case $pm in
                apt)
                    if ! dpkg -l "$package" 2>/dev/null | grep -q "^ii"; then
                        log_message "WARNING" "Package $package is missing or broken"
                        sudo apt install --reinstall "$package" -y
                    fi
                    ;;
                yum|dnf)
                    if ! rpm -q "$package" >/dev/null 2>&1; then
                        log_message "WARNING" "Package $package is missing"
                        sudo $pm reinstall "$package" -y
                    fi
                    ;;
                zypper)
                    if ! rpm -q "$package" >/dev/null 2>&1; then
                        log_message "WARNING" "Package $package is missing"
                        sudo zypper install -f "$package"
                    fi
                    ;;
                pacman)
                    if ! pacman -Q "$package" >/dev/null 2>&1; then
                        log_message "WARNING" "Package $package is missing"
                        sudo pacman -S "$package" --noconfirm
                    fi
                    ;;
            esac
        done
    fi
}

check_disk_space() {
    log_message "INFO" "Checking disk space for package operations..."
    
    # Check available space in common package cache directories
    local cache_dirs=("/var/cache/apt" "/var/cache/yum" "/var/cache/dnf" "/var/cache/pacman" "/var/cache/zypp")
    
    for cache_dir in "${cache_dirs[@]}"; do
        if [ -d "$cache_dir" ]; then
            local available=$(df "$cache_dir" | tail -1 | awk '{print $4}')
            local used_percent=$(df "$cache_dir" | tail -1 | awk '{print $5}' | sed 's/%//')
            
            if [ "$used_percent" -gt 90 ]; then
                log_message "WARNING" "Low disk space in $cache_dir (${used_percent}% used)"
                
                echo "Clean package cache? (y/N): "
                read -n 1 clean_cache
                echo
                
                if [[ $clean_cache =~ ^[Yy]$ ]]; then
                    log_message "INFO" "Cleaning cache in $cache_dir..."
                    sudo find "$cache_dir" -type f -name "*.deb" -delete 2>/dev/null || true
                    sudo find "$cache_dir" -type f -name "*.rpm" -delete 2>/dev/null || true
                    sudo find "$cache_dir" -type f -name "*.pkg.tar.*" -delete 2>/dev/null || true
                fi
            fi
        fi
    done
}

fix_repository_issues() {
    local pm=$(detect_package_manager)
    
    log_message "INFO" "Checking repository configuration..."
    
    case $pm in
        apt)
            log_message "INFO" "Checking APT repositories..."
            
            # Check for duplicate sources
            if [ -d /etc/apt/sources.list.d ]; then
                local duplicate_sources=$(find /etc/apt/sources.list.d -name "*.list" -exec grep -l "ubuntu\|debian" {} \; | wc -l)
                if [ "$duplicate_sources" -gt 5 ]; then
                    log_message "WARNING" "Many repository files detected, possible duplicates"
                fi
            fi
            
            # Test repository connectivity
            log_message "INFO" "Testing repository connectivity..."
            if sudo apt update -q 2>/dev/null; then
                log_message "SUCCESS" "All repositories accessible"
            else
                log_message "WARNING" "Some repositories are not accessible"
                
                # Show failing repositories
                sudo apt update 2>&1 | grep -E "Failed|Error" | head -5
            fi
            ;;
            
        yum|dnf)
            log_message "INFO" "Checking $pm repositories..."
            
            if sudo $pm repolist 2>/dev/null | grep -q "repolist: 0"; then
                log_message "ERROR" "No repositories enabled"
            else
                log_message "SUCCESS" "Repositories are configured"
            fi
            ;;
    esac
}

interactive_package_repair() {
    echo -e "${BOLD}Package Management Repair${NC}"
    echo
    
    local pm=$(detect_package_manager)
    log_message "INFO" "Detected package manager: $pm"
    echo
    
    echo "Select repair option:"
    echo "1) Quick package database repair"
    echo "2) Fix broken packages"
    echo "3) Clean package cache"
    echo "4) Reinstall critical packages"
    echo "5) Check repository configuration"
    echo "6) Complete package system repair"
    echo "7) Package system diagnostics"
    echo
    
    read -p "Select option (1-7): " repair_option
    
    case $repair_option in
        1)
            repair_package_database
            ;;
        2)
            case $pm in
                apt)
                    sudo apt --fix-broken install -y
                    sudo dpkg --configure -a
                    ;;
                yum|dnf)
                    sudo $pm check
                    sudo package-cleanup --cleandupes -y 2>/dev/null || true
                    ;;
                zypper)
                    sudo zypper verify
                    ;;
                pacman)
                    sudo pacman -Qkk
                    ;;
            esac
            ;;
        3)
            check_disk_space
            case $pm in
                apt)
                    sudo apt clean
                    sudo apt autoremove -y
                    ;;
                yum|dnf)
                    sudo $pm clean all
                    ;;
                zypper)
                    sudo zypper clean -a
                    ;;
                pacman)
                    sudo pacman -Sc --noconfirm
                    ;;
            esac
            ;;
        4)
            reinstall_critical_packages
            ;;
        5)
            fix_repository_issues
            ;;
        6)
            log_message "INFO" "Performing complete package system repair..."
            check_disk_space
            repair_package_database
            reinstall_critical_packages
            fix_repository_issues
            ;;
        7)
            echo -e "${BOLD}Package System Diagnostics:${NC}"
            echo
            echo "Package manager: $pm"
            echo
            
            case $pm in
                apt)
                    echo "APT configuration:"
                    apt-config dump | grep -E "Dir|Cache" | head -10
                    echo
                    echo "Installed packages: $(dpkg -l | grep "^ii" | wc -l)"
                    echo "Broken packages: $(apt list --upgradable 2>/dev/null | wc -l)"
                    echo
                    echo "Repository status:"
                    apt update -q 2>&1 | tail -5
                    ;;
                yum|dnf)
                    echo "Enabled repositories:"
                    $pm repolist enabled | head -10
                    echo
                    echo "Installed packages: $(rpm -qa | wc -l)"
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
    interactive_package_repair
}

main "$@"