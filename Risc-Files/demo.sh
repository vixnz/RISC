#!/bin/bash
#
# Linux Rescue Drive Demo
# Demonstrates the main features and capabilities
#

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

show_banner() {
    clear
    echo -e "${CYAN}${BOLD}"
    echo "╔══════════════════════════════════════════════════════════════╗"
    echo "║                 LINUX RESCUE DRIVE DEMO                     ║"
    echo "║              Feature Demonstration & Test                    ║"
    echo "╚══════════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
    echo
}

demo_message() {
    echo -e "${BLUE}[DEMO]${NC} $1"
}

demo_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

demo_info() {
    echo -e "${YELLOW}[INFO]${NC} $1"
}

wait_for_user() {
    echo
    echo -e "${CYAN}Press Enter to continue...${NC}"
    read
}

demo_system_overview() {
    demo_message "Demonstrating System Overview functionality..."
    
    echo -e "${BOLD}System Information:${NC}"
    echo "Hostname: $(hostname)"
    echo "Uptime: $(uptime -p 2>/dev/null || uptime)"
    echo "Kernel: $(uname -r)"
    echo "Architecture: $(uname -m)"
    echo
    
    echo -e "${BOLD}Hardware Summary:${NC}"
    echo "CPU: $(grep 'model name' /proc/cpuinfo | head -1 | cut -d: -f2 | xargs || echo 'Unknown')"
    echo "Memory: $(free -h | grep Mem | awk '{print $2}')"
    echo "Storage: $(df -h / | tail -1 | awk '{print $2}') root filesystem"
    echo
    
    demo_success "System overview complete"
    wait_for_user
}

demo_filesystem_check() {
    demo_message "Demonstrating Filesystem Check (simulated)..."
    
    echo -e "${BOLD}Available Filesystems:${NC}"
    lsblk -f | grep -E 'NAME|ext|xfs|ntfs|fat' | head -5
    echo
    
    demo_info "In real operation, this would:"
    echo "  ✓ Check filesystem integrity"
    echo "  ✓ Repair bad sectors"
    echo "  ✓ Fix filesystem errors"
    echo "  ✓ Verify partition tables"
    echo
    
    demo_success "Filesystem check demonstration complete"
    wait_for_user
}

demo_network_diagnostics() {
    demo_message "Demonstrating Network Diagnostics..."
    
    echo -e "${BOLD}Network Interfaces:${NC}"
    ip addr show | grep -E "^[0-9]:|inet " | head -10
    echo
    
    echo -e "${BOLD}Testing Connectivity:${NC}"
    if ping -c 1 -W 3 8.8.8.8 >/dev/null 2>&1; then
        demo_success "Internet connectivity: WORKING"
    else
        demo_info "Internet connectivity: NOT AVAILABLE (expected in demo)"
    fi
    
    echo -e "${BOLD}DNS Configuration:${NC}"
    if [ -f /etc/resolv.conf ]; then
        grep nameserver /etc/resolv.conf | head -3 || echo "No nameservers configured"
    fi
    echo
    
    demo_success "Network diagnostics complete"
    wait_for_user
}

demo_hardware_test() {
    demo_message "Demonstrating Hardware Test capabilities..."
    
    echo -e "${BOLD}CPU Information:${NC}"
    grep -E "model name|cpu cores|processor" /proc/cpuinfo | head -3
    echo
    
    echo -e "${BOLD}Memory Status:${NC}"
    free -h | grep -E "Mem|Swap"
    echo
    
    echo -e "${BOLD}Storage Devices:${NC}"
    lsblk -d -o NAME,SIZE,MODEL | head -5
    echo
    
    echo -e "${BOLD}Load Average:${NC}"
    uptime
    echo
    
    demo_info "In full operation, this would also test:"
    echo "  ✓ Memory stress testing"
    echo "  ✓ CPU burn-in tests"
    echo "  ✓ SMART disk analysis"
    echo "  ✓ Network speed tests"
    
    demo_success "Hardware test demonstration complete"
    wait_for_user
}

demo_security_scan() {
    demo_message "Demonstrating Security Scan (safe demo mode)..."
    
    echo -e "${BOLD}User Account Security:${NC}"
    echo "Current user: $(whoami)"
    echo "User groups: $(groups)"
    echo
    
    echo -e "${BOLD}Process Analysis:${NC}"
    echo "Total processes: $(ps aux | wc -l)"
    echo "Running as root: $(ps aux | awk '$1 == "root"' | wc -l)"
    echo
    
    echo -e "${BOLD}Network Security:${NC}"
    echo "Listening services:"
    ss -tuln | grep LISTEN | head -5 | awk '{print "  " $1 " " $5}'
    echo
    
    demo_info "Full security scan includes:"
    echo "  ✓ Rootkit detection"
    echo "  ✓ Malware scanning"
    echo "  ✓ Vulnerability checks"
    echo "  ✓ File integrity verification"
    
    demo_success "Security scan demonstration complete"
    wait_for_user
}

demo_data_recovery() {
    demo_message "Demonstrating Data Recovery capabilities..."
    
    echo -e "${BOLD}Available Storage:${NC}"
    df -h | grep -E "Filesystem|/dev" | head -5
    echo
    
    demo_info "Data recovery features include:"
    echo "  ✓ Deleted file recovery (PhotoRec)"
    echo "  ✓ Partition table recovery (TestDisk)"
    echo "  ✓ File system repair"
    echo "  ✓ Drive cloning with ddrescue"
    echo "  ✓ Corrupted file repair"
    echo
    
    echo -e "${BOLD}Recovery Tools Available:${NC}"
    for tool in photorec testdisk ddrescue; do
        if command -v $tool >/dev/null 2>&1; then
            echo "  ✓ $tool - Available"
        else
            echo "  ✗ $tool - Would be available in full rescue environment"
        fi
    done
    echo
    
    demo_success "Data recovery demonstration complete"
    wait_for_user
}

demo_boot_repair() {
    demo_message "Demonstrating Boot Repair capabilities..."
    
    # Check boot environment
    if [ -d /sys/firmware/efi ]; then
        echo -e "${BOLD}Boot Environment:${NC} UEFI"
    else
        echo -e "${BOLD}Boot Environment:${NC} BIOS/Legacy"
    fi
    echo
    
    echo -e "${BOLD}Available Disks:${NC}"
    lsblk -d -o NAME,SIZE,TYPE | grep disk | head -3
    echo
    
    demo_info "Boot repair features:"
    echo "  ✓ GRUB installation and configuration"
    echo "  ✓ MBR restoration"
    echo "  ✓ EFI boot repair"
    echo "  ✓ Multi-boot detection"
    echo "  ✓ Boot flag management"
    echo "  ✓ OS detection and menu generation"
    echo
    
    demo_success "Boot repair demonstration complete"
    wait_for_user
}

demo_package_management() {
    demo_message "Demonstrating Package Management repair..."
    
    # Detect package manager
    local pm="unknown"
    if command -v apt >/dev/null 2>&1; then
        pm="apt (Debian/Ubuntu)"
    elif command -v yum >/dev/null 2>&1; then
        pm="yum (RHEL/CentOS)"
    elif command -v dnf >/dev/null 2>&1; then
        pm="dnf (Fedora)"
    elif command -v pacman >/dev/null 2>&1; then
        pm="pacman (Arch)"
    elif command -v zypper >/dev/null 2>&1; then
        pm="zypper (openSUSE)"
    fi
    
    echo -e "${BOLD}Detected Package Manager:${NC} $pm"
    echo
    
    demo_info "Package management repair includes:"
    echo "  ✓ Broken package detection and repair"
    echo "  ✓ Repository configuration fixes"
    echo "  ✓ Cache cleanup and rebuilding"
    echo "  ✓ Dependency resolution"
    echo "  ✓ Critical package reinstallation"
    echo
    
    demo_success "Package management demonstration complete"
    wait_for_user
}

demo_quick_autofix() {
    demo_message "Demonstrating Quick AutoFix simulation..."
    
    echo -e "${BOLD}Running comprehensive system check...${NC}"
    echo
    
    # Simulate various checks
    local checks=(
        "Checking filesystem integrity"
        "Verifying boot loader configuration"
        "Testing network connectivity"
        "Analyzing system services"
        "Checking disk space usage"
        "Monitoring memory usage"
        "Performing security audit"
        "Validating package integrity"
    )
    
    for check in "${checks[@]}"; do
        echo -n "$check... "
        sleep 1
        echo -e "${GREEN}OK${NC}"
    done
    
    echo
    demo_success "Quick AutoFix simulation complete!"
    echo
    demo_info "In real operation, AutoFix would automatically:"
    echo "  ✓ Repair found filesystem errors"
    echo "  ✓ Fix boot loader issues"
    echo "  ✓ Restore network connectivity"
    echo "  ✓ Restart failed services"
    echo "  ✓ Clean up disk space"
    echo "  ✓ Optimize memory usage"
    echo "  ✓ Apply security fixes"
    
    wait_for_user
}

show_feature_overview() {
    demo_message "Linux Rescue Drive Feature Overview"
    echo
    
    echo -e "${BOLD}Core Features:${NC}"
    echo "├─ Quick AutoFix - Automated problem detection and repair"
    echo "├─ Boot Repair - GRUB, MBR, and EFI boot loader repair"
    echo "├─ Filesystem Check - ext2/3/4, XFS, NTFS, FAT repair"
    echo "├─ Hardware Diagnostics - Memory, CPU, storage, network tests"
    echo "├─ Network Repair - Connectivity and configuration fixes"
    echo "├─ Package Management - Broken package detection and repair"
    echo "├─ Security Scanner - Rootkit, malware, and vulnerability detection"
    echo "├─ Data Recovery - File recovery and partition restoration"
    echo "├─ System Information - Comprehensive system analysis"
    echo "└─ Manual Tools - Direct access to repair utilities"
    echo
    
    echo -e "${BOLD}Supported Systems:${NC}"
    echo "├─ Linux Distributions: Ubuntu, Debian, RHEL, CentOS, Fedora, SUSE, Arch"
    echo "├─ Filesystems: ext2/3/4, XFS, Btrfs, NTFS, FAT32, exFAT"
    echo "├─ Boot Systems: UEFI and Legacy BIOS"
    echo "└─ Hardware: x86_64 systems with 4GB+ RAM"
    echo
    
    wait_for_user
}

interactive_demo() {
    while true; do
        show_banner
        
        echo -e "${BOLD}Select Demo Module:${NC}"
        echo
        echo "1) Feature Overview"
        echo "2) Quick AutoFix Simulation"
        echo "3) System Overview"
        echo "4) Filesystem Check Demo"
        echo "5) Network Diagnostics"
        echo "6) Hardware Testing"
        echo "7) Security Scanning"
        echo "8) Data Recovery"
        echo "9) Boot Repair"
        echo "10) Package Management"
        echo "11) Run All Demos"
        echo
        echo "q) Quit Demo"
        echo
        
        read -p "Select option: " choice
        echo
        
        case $choice in
            1) show_feature_overview ;;
            2) demo_quick_autofix ;;
            3) demo_system_overview ;;
            4) demo_filesystem_check ;;
            5) demo_network_diagnostics ;;
            6) demo_hardware_test ;;
            7) demo_security_scan ;;
            8) demo_data_recovery ;;
            9) demo_boot_repair ;;
            10) demo_package_management ;;
            11)
                show_feature_overview
                demo_quick_autofix
                demo_system_overview
                demo_filesystem_check
                demo_network_diagnostics
                demo_hardware_test
                demo_security_scan
                demo_data_recovery
                demo_boot_repair
                demo_package_management
                ;;
            q|Q)
                echo -e "${GREEN}Thank you for trying the Linux Rescue Drive demo!${NC}"
                exit 0
                ;;
            *)
                echo -e "${RED}Invalid choice. Please try again.${NC}"
                sleep 2
                ;;
        esac
    done
}

main() {
    echo -e "${CYAN}Welcome to the Linux Rescue Drive Demo!${NC}"
    echo
    echo "This demonstration shows the features and capabilities of the"
    echo "Linux Rescue Drive without making any changes to your system."
    echo
    wait_for_user
    
    interactive_demo
}

main "$@"