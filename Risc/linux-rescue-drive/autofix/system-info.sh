#!/bin/bash
#
# System Information Tool
# Display comprehensive system information
#

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
BOLD='\033[1m'
NC='\033[0m'

show_system_overview() {
    echo -e "${BOLD}═══ SYSTEM OVERVIEW ═══${NC}"
    echo
    
    echo -e "${BLUE}Hostname:${NC} $(hostname)"
    echo -e "${BLUE}Uptime:${NC} $(uptime -p)"
    echo -e "${BLUE}Current Date:${NC} $(date)"
    echo -e "${BLUE}Time Zone:${NC} $(timedatectl show -p Timezone --value 2>/dev/null || cat /etc/timezone 2>/dev/null || echo "Unknown")"
    echo -e "${BLUE}System Load:${NC} $(uptime | awk -F'load average:' '{print $2}')"
    echo
}

show_hardware_info() {
    echo -e "${BOLD}═══ HARDWARE INFORMATION ═══${NC}"
    echo
    
    # CPU Information
    echo -e "${BLUE}CPU Information:${NC}"
    if command -v lscpu >/dev/null 2>&1; then
        lscpu | grep -E "Model name|Architecture|CPU\(s\)|Thread|Core|Socket|Vendor ID|CPU MHz"
    else
        grep -E "model name|processor|cpu cores" /proc/cpuinfo | head -10
    fi
    echo
    
    # Memory Information
    echo -e "${BLUE}Memory Information:${NC}"
    free -h
    echo
    
    # Storage Information
    echo -e "${BLUE}Storage Devices:${NC}"
    lsblk -o NAME,SIZE,TYPE,MOUNTPOINT,FSTYPE,MODEL
    echo
    
    # Graphics Information
    echo -e "${BLUE}Graphics Information:${NC}"
    if command -v lspci >/dev/null 2>&1; then
        lspci | grep -i vga
        lspci | grep -i display
    else
        echo "lspci not available"
    fi
    echo
}

show_network_info() {
    echo -e "${BOLD}═══ NETWORK INFORMATION ═══${NC}"
    echo
    
    # Network Interfaces
    echo -e "${BLUE}Network Interfaces:${NC}"
    ip addr show | grep -E "^[0-9]+:|inet " | while read line; do
        if echo "$line" | grep -q "^[0-9]+:"; then
            local interface=$(echo "$line" | awk -F': ' '{print $2}' | cut -d'@' -f1)
            local state=$(echo "$line" | grep -o "state [A-Z]*" | awk '{print $2}')
            echo "  Interface: $interface ($state)"
        elif echo "$line" | grep -q "inet "; then
            local ip=$(echo "$line" | awk '{print $2}')
            echo "    IP: $ip"
        fi
    done
    echo
    
    # Routing Information
    echo -e "${BLUE}Default Routes:${NC}"
    ip route | grep default
    echo
    
    # DNS Configuration
    echo -e "${BLUE}DNS Configuration:${NC}"
    if [ -f /etc/resolv.conf ]; then
        grep nameserver /etc/resolv.conf | head -5
    else
        echo "No /etc/resolv.conf found"
    fi
    echo
}

show_filesystem_info() {
    echo -e "${BOLD}═══ FILESYSTEM INFORMATION ═══${NC}"
    echo
    
    # Disk Usage
    echo -e "${BLUE}Disk Usage:${NC}"
    df -h | grep -E "^/dev|Filesystem"
    echo
    
    # Mount Points
    echo -e "${BLUE}Mount Points:${NC}"
    mount | grep "^/dev" | while read line; do
        local device=$(echo "$line" | awk '{print $1}')
        local mountpoint=$(echo "$line" | awk '{print $3}')
        local fstype=$(echo "$line" | awk '{print $5}')
        local options=$(echo "$line" | sed 's/.*(\(.*\))/\1/')
        echo "  $device -> $mountpoint ($fstype) [$options]"
    done
    echo
    
    # Swap Information
    echo -e "${BLUE}Swap Information:${NC}"
    if [ -f /proc/swaps ]; then
        cat /proc/swaps
    else
        echo "No swap information available"
    fi
    echo
}

show_process_info() {
    echo -e "${BOLD}═══ PROCESS INFORMATION ═══${NC}"
    echo
    
    # Top CPU Processes
    echo -e "${BLUE}Top CPU Processes:${NC}"
    ps aux --sort=-%cpu | head -6
    echo
    
    # Top Memory Processes
    echo -e "${BLUE}Top Memory Processes:${NC}"
    ps aux --sort=-%mem | head -6
    echo
    
    # Process Count
    local total_processes=$(ps aux | wc -l)
    echo -e "${BLUE}Total Processes:${NC} $total_processes"
    
    # Running Processes
    local running_processes=$(ps aux | awk '$8 ~ /^[RD]/ {print $0}' | wc -l)
    echo -e "${BLUE}Running Processes:${NC} $running_processes"
    echo
}

show_kernel_info() {
    echo -e "${BOLD}═══ KERNEL INFORMATION ═══${NC}"
    echo
    
    echo -e "${BLUE}Kernel Version:${NC} $(uname -r)"
    echo -e "${BLUE}Architecture:${NC} $(uname -m)"
    echo -e "${BLUE}Operating System:${NC} $(uname -s)"
    
    # Distribution Information
    if [ -f /etc/os-release ]; then
        echo -e "${BLUE}Distribution:${NC}"
        grep -E "^(NAME|VERSION|ID)" /etc/os-release | sed 's/^/  /'
    elif [ -f /etc/lsb-release ]; then
        echo -e "${BLUE}Distribution:${NC}"
        cat /etc/lsb-release | sed 's/^/  /'
    fi
    echo
    
    # Kernel Modules
    echo -e "${BLUE}Loaded Kernel Modules (top 10):${NC}"
    lsmod | head -11
    echo
}

show_services_info() {
    echo -e "${BOLD}═══ SERVICES INFORMATION ═══${NC}"
    echo
    
    if command -v systemctl >/dev/null 2>&1; then
        # Active Services
        echo -e "${BLUE}Active Services (first 10):${NC}"
        systemctl list-units --type=service --state=active --no-pager | head -12
        echo
        
        # Failed Services
        echo -e "${BLUE}Failed Services:${NC}"
        local failed_services=$(systemctl list-units --type=service --state=failed --no-pager --no-legend | wc -l)
        if [ "$failed_services" -gt 0 ]; then
            systemctl list-units --type=service --state=failed --no-pager | head -10
        else
            echo "  No failed services"
        fi
        echo
    else
        echo -e "${YELLOW}systemctl not available${NC}"
        
        # Fallback to init scripts
        if [ -d /etc/init.d ]; then
            echo -e "${BLUE}Available Services:${NC}"
            ls /etc/init.d/ | head -10
        fi
        echo
    fi
}

show_security_info() {
    echo -e "${BOLD}═══ SECURITY INFORMATION ═══${NC}"
    echo
    
    # User Information
    echo -e "${BLUE}Current User:${NC} $(whoami)"
    echo -e "${BLUE}User ID:${NC} $(id)"
    echo
    
    # Logged in Users
    echo -e "${BLUE}Logged in Users:${NC}"
    who
    echo
    
    # Last Logins
    echo -e "${BLUE}Recent Logins:${NC}"
    if command -v last >/dev/null 2>&1; then
        last | head -5
    else
        echo "last command not available"
    fi
    echo
    
    # Firewall Status
    echo -e "${BLUE}Firewall Status:${NC}"
    if command -v ufw >/dev/null 2>&1; then
        sudo ufw status | head -5
    elif command -v iptables >/dev/null 2>&1; then
        local iptables_rules=$(sudo iptables -L | wc -l)
        echo "  iptables rules: $iptables_rules lines"
    else
        echo "  No firewall tools detected"
    fi
    echo
}

show_performance_metrics() {
    echo -e "${BOLD}═══ PERFORMANCE METRICS ═══${NC}"
    echo
    
    # Load Average
    echo -e "${BLUE}System Load:${NC}"
    uptime
    echo
    
    # Memory Usage
    echo -e "${BLUE}Memory Usage:${NC}"
    free -h | grep -E "Mem:|Swap:"
    echo
    
    # CPU Usage (if available)
    if command -v top >/dev/null 2>&1; then
        echo -e "${BLUE}CPU Usage (momentary):${NC}"
        top -bn1 | grep "Cpu(s)" || echo "CPU usage not available"
        echo
    fi
    
    # I/O Statistics (if available)
    if command -v iostat >/dev/null 2>&1; then
        echo -e "${BLUE}I/O Statistics:${NC}"
        iostat | head -10
        echo
    elif [ -f /proc/diskstats ]; then
        echo -e "${BLUE}Disk Activity:${NC}"
        echo "  Device activity detected in /proc/diskstats"
        echo
    fi
    
    # Network Statistics
    echo -e "${BLUE}Network Statistics:${NC}"
    if [ -f /proc/net/dev ]; then
        cat /proc/net/dev | grep -E "eth|wlan|ens|enp" | head -5
    fi
    echo
}

show_environment_info() {
    echo -e "${BOLD}═══ ENVIRONMENT INFORMATION ═══${NC}"
    echo
    
    # Shell Information
    echo -e "${BLUE}Shell:${NC} $SHELL"
    echo -e "${BLUE}PATH:${NC}"
    echo "$PATH" | tr ':' '\n' | sed 's/^/  /' | head -10
    echo
    
    # Important Environment Variables
    echo -e "${BLUE}Key Environment Variables:${NC}"
    env | grep -E "^(HOME|USER|LANG|TERM|DISPLAY)" | sed 's/^/  /'
    echo
    
    # Locale Information
    echo -e "${BLUE}Locale:${NC}"
    locale | head -5 | sed 's/^/  /'
    echo
}

generate_full_report() {
    echo -e "${BOLD}Generating comprehensive system report...${NC}"
    
    local report_file="/tmp/system_report_$(date +%Y%m%d_%H%M%S).txt"
    
    {
        echo "COMPREHENSIVE SYSTEM REPORT"
        echo "=========================="
        echo "Generated: $(date)"
        echo "Hostname: $(hostname)"
        echo
        
        # All sections
        show_system_overview
        echo
        show_hardware_info
        echo
        show_network_info
        echo
        show_filesystem_info
        echo
        show_process_info
        echo
        show_kernel_info
        echo
        show_services_info
        echo
        show_security_info
        echo
        show_performance_metrics
        echo
        show_environment_info
        echo
        
        # Additional detailed information
        echo "═══ DETAILED HARDWARE ═══"
        echo
        if command -v lspci >/dev/null 2>&1; then
            echo "PCI Devices:"
            lspci
            echo
        fi
        
        if command -v lsusb >/dev/null 2>&1; then
            echo "USB Devices:"
            lsusb
            echo
        fi
        
        echo "═══ KERNEL MESSAGES (last 20) ═══"
        dmesg | tail -20
        echo
        
    } > "$report_file"
    
    echo -e "${GREEN}System report saved to: $report_file${NC}"
    
    echo "View report now? (y/N): "
    read -n 1 view_report
    echo
    
    if [[ $view_report =~ ^[Yy]$ ]]; then
        less "$report_file"
    fi
}

interactive_system_info() {
    echo -e "${BOLD}System Information Tool${NC}"
    echo
    
    echo "Select information category:"
    echo "1) System Overview"
    echo "2) Hardware Information"
    echo "3) Network Information"
    echo "4) Filesystem Information"
    echo "5) Process Information"
    echo "6) Kernel Information"
    echo "7) Services Information"
    echo "8) Security Information"
    echo "9) Performance Metrics"
    echo "10) Environment Information"
    echo "11) Complete System Report"
    echo "12) Generate Full Report File"
    echo
    
    read -p "Select option (1-12): " info_option
    
    case $info_option in
        1) show_system_overview ;;
        2) show_hardware_info ;;
        3) show_network_info ;;
        4) show_filesystem_info ;;
        5) show_process_info ;;
        6) show_kernel_info ;;
        7) show_services_info ;;
        8) show_security_info ;;
        9) show_performance_metrics ;;
        10) show_environment_info ;;
        11)
            show_system_overview
            echo; show_hardware_info
            echo; show_network_info
            echo; show_filesystem_info
            echo; show_process_info
            echo; show_kernel_info
            echo; show_services_info
            echo; show_security_info
            echo; show_performance_metrics
            echo; show_environment_info
            ;;
        12) generate_full_report ;;
        *)
            echo -e "${RED}Invalid option${NC}"
            return 1
            ;;
    esac
}

main() {
    interactive_system_info
}

main "$@"