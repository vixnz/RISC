#!/bin/bash
#
# Linux Rescue Menu - Main Interface
# Provides a user-friendly menu for all rescue operations
#

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

RESCUE_DIR="/opt/rescue"

show_banner() {
    clear
    echo -e "${CYAN}${BOLD}"
    echo "╔══════════════════════════════════════════════════════════════╗"
    echo "║                    LINUX RESCUE DRIVE                       ║"
    echo "║               Automated System Recovery Tool                 ║"
    echo "║                        Version 1.0                          ║"
    echo "╚══════════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
    echo
}

show_main_menu() {
    echo -e "${BOLD}═══ MAIN MENU ═══${NC}"
    echo
    echo -e "${GREEN}1)${NC} Quick AutoFix - Automatically detect and fix common issues"
    echo -e "${GREEN}2)${NC} Boot Repair - Fix GRUB and boot loader problems"
    echo -e "${GREEN}3)${NC} Filesystem Check - Scan and repair filesystem errors"
    echo -e "${GREEN}4)${NC} Hardware Diagnostics - Test system hardware"
    echo -e "${GREEN}5)${NC} Network Configuration - Fix network connectivity"
    echo -e "${GREEN}6)${NC} Package Management - Repair broken packages"
    echo -e "${GREEN}7)${NC} Security Scan - Check for rootkits and malware"
    echo -e "${GREEN}8)${NC} Data Recovery - Recover deleted or corrupted files"
    echo -e "${GREEN}9)${NC} System Information - View detailed system info"
    echo -e "${GREEN}10)${NC} Manual Tools - Access individual repair utilities"
    echo
    echo -e "${YELLOW}s)${NC} Open System Shell"
    echo -e "${YELLOW}r)${NC} Reboot System"
    echo -e "${YELLOW}q)${NC} Quit to Desktop"
    echo
}

run_quick_autofix() {
    echo -e "${BOLD}Running Quick AutoFix...${NC}"
    echo
    "$RESCUE_DIR/quick-autofix.sh"
    echo
    echo "Press any key to return to menu..."
    read -n 1
}

run_boot_repair() {
    echo -e "${BOLD}Boot Repair Utility${NC}"
    echo
    "$RESCUE_DIR/boot-repair.sh"
    echo
    echo "Press any key to return to menu..."
    read -n 1
}

run_filesystem_check() {
    echo -e "${BOLD}Filesystem Check and Repair${NC}"
    echo
    "$RESCUE_DIR/filesystem-repair.sh"
    echo
    echo "Press any key to return to menu..."
    read -n 1
}

run_hardware_diagnostics() {
    echo -e "${BOLD}Hardware Diagnostics${NC}"
    echo
    "$RESCUE_DIR/hardware-test.sh"
    echo
    echo "Press any key to return to menu..."
    read -n 1
}

run_network_config() {
    echo -e "${BOLD}Network Configuration${NC}"
    echo
    "$RESCUE_DIR/network-repair.sh"
    echo
    echo "Press any key to return to menu..."
    read -n 1
}

run_package_repair() {
    echo -e "${BOLD}Package Management Repair${NC}"
    echo
    "$RESCUE_DIR/package-repair.sh"
    echo
    echo "Press any key to return to menu..."
    read -n 1
}

run_security_scan() {
    echo -e "${BOLD}Security Scan${NC}"
    echo
    "$RESCUE_DIR/security-scan.sh"
    echo
    echo "Press any key to return to menu..."
    read -n 1
}

run_data_recovery() {
    echo -e "${BOLD}Data Recovery Tools${NC}"
    echo
    "$RESCUE_DIR/data-recovery.sh"
    echo
    echo "Press any key to return to menu..."
    read -n 1
}

show_system_info() {
    echo -e "${BOLD}System Information${NC}"
    echo
    "$RESCUE_DIR/system-info.sh"
    echo
    echo "Press any key to return to menu..."
    read -n 1
}

show_manual_tools() {
    echo -e "${BOLD}Manual Tools Menu${NC}"
    echo
    echo "1) GParted - Partition editor"
    echo "2) TestDisk - Partition recovery"
    echo "3) PhotoRec - File recovery"
    echo "4) Memtest86+ - Memory test"
    echo "5) File Manager"
    echo "6) Terminal"
    echo "b) Back to main menu"
    echo
    read -p "Select tool: " tool_choice
    
    case $tool_choice in
        1) gparted ;;
        2) sudo testdisk ;;
        3) sudo photorec ;;
        4) memtest86+ ;;
        5) nautilus ;;
        6) gnome-terminal ;;
        b|B) return ;;
        *) echo "Invalid choice" ;;
    esac
    
    echo "Press any key to return..."
    read -n 1
}

main_loop() {
    while true; do
        show_banner
        show_main_menu
        
        read -p "Select option: " choice
        echo
        
        case $choice in
            1) run_quick_autofix ;;
            2) run_boot_repair ;;
            3) run_filesystem_check ;;
            4) run_hardware_diagnostics ;;
            5) run_network_config ;;
            6) run_package_repair ;;
            7) run_security_scan ;;
            8) run_data_recovery ;;
            9) show_system_info ;;
            10) show_manual_tools ;;
            s|S) 
                echo "Opening system shell..."
                bash
                ;;
            r|R)
                echo "Rebooting system..."
                sudo reboot
                ;;
            q|Q)
                echo "Returning to desktop..."
                exit 0
                ;;
            *)
                echo "Invalid choice. Please try again."
                sleep 2
                ;;
        esac
    done
}

# Check if running in rescue environment
if [ ! -d "$RESCUE_DIR" ]; then
    echo -e "${RED}Error: Rescue tools not found. Please run from rescue environment.${NC}"
    exit 1
fi

main_loop