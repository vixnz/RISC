#!/bin/bash
#
# Hardware Diagnostics Tool
# Comprehensive hardware testing and diagnostics
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

test_memory() {
    log_message "INFO" "Testing system memory..."
    
    # Show memory information
    echo -e "${BOLD}Memory Information:${NC}"
    free -h
    echo
    
    # Check for memory errors in dmesg
    local mem_errors=$(dmesg | grep -i "memory.*error\|bad.*ram\|memory.*fail" | wc -l)
    if [ "$mem_errors" -gt 0 ]; then
        log_message "WARNING" "Found $mem_errors potential memory errors in system log"
        echo "Recent memory-related errors:"
        dmesg | grep -i "memory.*error\|bad.*ram\|memory.*fail" | tail -5
        echo
    else
        log_message "SUCCESS" "No memory errors found in system log"
    fi
    
    # Basic memory stress test
    echo "Run basic memory stress test? (y/N): "
    read -n 1 run_stress
    echo
    
    if [[ $run_stress =~ ^[Yy]$ ]]; then
        log_message "INFO" "Running 30-second memory stress test..."
        
        # Simple memory allocation test
        python3 << 'EOF'
import time
import gc

print("Allocating memory blocks...")
allocated = []
try:
    for i in range(10):
        # Allocate 100MB blocks
        block = bytearray(100 * 1024 * 1024)
        allocated.append(block)
        print(f"Allocated block {i+1}/10 (100MB each)")
        time.sleep(1)
    
    print("Testing memory access patterns...")
    for i, block in enumerate(allocated):
        # Write and read pattern
        for j in range(0, len(block), 4096):
            block[j:j+4] = b'\xAA\x55\xAA\x55'
        
        # Verify pattern
        errors = 0
        for j in range(0, len(block), 4096):
            if block[j:j+4] != b'\xAA\x55\xAA\x55':
                errors += 1
        
        if errors > 0:
            print(f"ERROR: Block {i} has {errors} memory errors")
        else:
            print(f"Block {i}: OK")
    
    print("Memory stress test completed successfully")
    
except MemoryError:
    print("WARNING: System ran out of memory during test")
except Exception as e:
    print(f"ERROR: Memory test failed: {e}")
finally:
    # Clean up
    allocated.clear()
    gc.collect()
EOF
        
        log_message "SUCCESS" "Memory stress test completed"
    fi
    
    # Suggest memtest86+ for thorough testing
    if command -v memtest86+ >/dev/null 2>&1; then
        echo
        log_message "INFO" "For comprehensive memory testing, run 'memtest86+' from boot menu"
    fi
}

test_cpu() {
    log_message "INFO" "Testing CPU..."
    
    # Show CPU information
    echo -e "${BOLD}CPU Information:${NC}"
    lscpu | head -20
    echo
    
    # Check CPU temperature if available
    if [ -d /sys/class/thermal ]; then
        echo -e "${BOLD}CPU Temperature:${NC}"
        for thermal in /sys/class/thermal/thermal_zone*; do
            if [ -f "$thermal/temp" ]; then
                local temp=$(cat "$thermal/temp" 2>/dev/null)
                if [ -n "$temp" ] && [ "$temp" -gt 0 ]; then
                    temp=$((temp / 1000))
                    echo "  Thermal zone: ${temp}°C"
                    
                    if [ "$temp" -gt 80 ]; then
                        log_message "WARNING" "High CPU temperature detected: ${temp}°C"
                    fi
                fi
            fi
        done
        echo
    fi
    
    # CPU stress test
    echo "Run CPU stress test? (y/N): "
    read -n 1 run_stress
    echo
    
    if [[ $run_stress =~ ^[Yy]$ ]]; then
        log_message "INFO" "Running 30-second CPU stress test..."
        
        # Get number of CPU cores
        local cores=$(nproc)
        log_message "INFO" "Detected $cores CPU cores"
        
        # Run stress test using all cores
        timeout 30s bash -c '
            for ((i=0; i<'$cores'; i++)); do
                (while true; do :; done) &
            done
            wait
        ' 2>/dev/null &
        
        local stress_pid=$!
        
        # Monitor during stress test
        for i in {1..6}; do
            sleep 5
            local load=$(uptime | awk -F "load average:" "{print \$2}" | awk "{print \$1}" | sed "s/,//")
            echo "Load average: $load (5s elapsed)"
        done
        
        # Kill stress test if still running
        kill $stress_pid 2>/dev/null || true
        wait $stress_pid 2>/dev/null || true
        
        log_message "SUCCESS" "CPU stress test completed"
    fi
    
    # Check for CPU flags and features
    echo -e "${BOLD}CPU Features:${NC}"
    if grep -q "vmx\|svm" /proc/cpuinfo; then
        log_message "SUCCESS" "Virtualization support detected"
    fi
    
    if grep -q "aes" /proc/cpuinfo; then
        log_message "SUCCESS" "AES encryption support detected"
    fi
}

test_storage() {
    log_message "INFO" "Testing storage devices..."
    
    echo -e "${BOLD}Storage Devices:${NC}"
    lsblk -d -o NAME,SIZE,MODEL,SERIAL
    echo
    
    # Test each storage device
    for disk in $(lsblk -dpno NAME | grep -E "/dev/sd|/dev/nvme|/dev/hd"); do
        echo -e "${BOLD}Testing $disk:${NC}"
        
        # Basic disk information
        local size=$(lsblk -dno SIZE "$disk")
        local model=$(lsblk -dno MODEL "$disk" | tr -d ' ')
        log_message "INFO" "Device: $disk, Size: $size, Model: $model"
        
        # SMART status
        if command -v smartctl >/dev/null 2>&1; then
            if sudo smartctl -H "$disk" 2>/dev/null | grep -q "PASSED"; then
                log_message "SUCCESS" "SMART status: PASSED"
            else
                log_message "WARNING" "SMART status: FAILED or unavailable"
            fi
            
            # Check reallocated sectors
            local reallocated=$(sudo smartctl -A "$disk" 2>/dev/null | awk '/Reallocated_Sector_Ct/ {print $10}' | head -1)
            if [ -n "$reallocated" ] && [ "$reallocated" -gt 0 ]; then
                log_message "WARNING" "Reallocated sectors: $reallocated"
            fi
        fi
        
        # Read speed test
        echo "Test read speed for $disk? (y/N): "
        read -n 1 test_speed
        echo
        
        if [[ $test_speed =~ ^[Yy]$ ]]; then
            log_message "INFO" "Testing read speed (this may take a few minutes)..."
            
            # Test read speed with dd
            local read_speed=$(sudo dd if="$disk" of=/dev/null bs=1M count=100 iflag=direct 2>&1 | grep -o "[0-9.]* MB/s" | tail -1)
            if [ -n "$read_speed" ]; then
                log_message "SUCCESS" "Read speed: $read_speed"
            else
                log_message "WARNING" "Could not measure read speed"
            fi
        fi
        
        echo
    done
}

test_network() {
    log_message "INFO" "Testing network interfaces..."
    
    echo -e "${BOLD}Network Interfaces:${NC}"
    ip link show | grep -E "^[0-9]+:" | while read line; do
        local interface=$(echo "$line" | awk -F': ' '{print $2}' | cut -d'@' -f1)
        local state=$(echo "$line" | grep -o "state [A-Z]*" | awk '{print $2}')
        echo "  $interface: $state"
    done
    echo
    
    # Test each network interface
    for interface in $(ip link show | grep -E "^[0-9]+:" | awk -F': ' '{print $2}' | cut -d'@' -f1 | grep -v lo); do
        echo -e "${BOLD}Testing $interface:${NC}"
        
        # Check link status
        local carrier=$(cat "/sys/class/net/$interface/carrier" 2>/dev/null || echo "0")
        if [ "$carrier" = "1" ]; then
            log_message "SUCCESS" "Link detected on $interface"
            
            # Check for IP address
            local ip_addr=$(ip addr show "$interface" | grep "inet " | awk '{print $2}' | head -1)
            if [ -n "$ip_addr" ]; then
                log_message "SUCCESS" "IP address: $ip_addr"
                
                # Test connectivity
                if ping -c 1 -W 5 8.8.8.8 >/dev/null 2>&1; then
                    log_message "SUCCESS" "Internet connectivity working"
                else
                    log_message "WARNING" "No internet connectivity"
                fi
            else
                log_message "WARNING" "No IP address assigned"
            fi
        else
            log_message "WARNING" "No link detected on $interface"
        fi
        
        # Show interface statistics
        local rx_bytes=$(cat "/sys/class/net/$interface/statistics/rx_bytes" 2>/dev/null || echo "0")
        local tx_bytes=$(cat "/sys/class/net/$interface/statistics/tx_bytes" 2>/dev/null || echo "0")
        local rx_errors=$(cat "/sys/class/net/$interface/statistics/rx_errors" 2>/dev/null || echo "0")
        local tx_errors=$(cat "/sys/class/net/$interface/statistics/tx_errors" 2>/dev/null || echo "0")
        
        echo "  RX: $(numfmt --to=iec $rx_bytes) bytes, $rx_errors errors"
        echo "  TX: $(numfmt --to=iec $tx_bytes) bytes, $tx_errors errors"
        
        if [ "$rx_errors" -gt 100 ] || [ "$tx_errors" -gt 100 ]; then
            log_message "WARNING" "High error count on $interface"
        fi
        
        echo
    done
}

test_usb_ports() {
    log_message "INFO" "Testing USB ports..."
    
    echo -e "${BOLD}USB Devices:${NC}"
    if command -v lsusb >/dev/null 2>&1; then
        lsusb
        echo
        
        # Check USB controller status
        echo -e "${BOLD}USB Controllers:${NC}"
        lspci | grep -i usb | while read controller; do
            echo "  $controller"
        done
        echo
        
        # Check for USB errors
        local usb_errors=$(dmesg | grep -i "usb.*error\|usb.*fail" | wc -l)
        if [ "$usb_errors" -gt 0 ]; then
            log_message "WARNING" "Found $usb_errors USB-related errors in system log"
        else
            log_message "SUCCESS" "No USB errors found in system log"
        fi
    else
        log_message "WARNING" "lsusb command not available"
    fi
}

generate_hardware_report() {
    log_message "INFO" "Generating hardware report..."
    
    local report_file="/tmp/hardware_report_$(date +%Y%m%d_%H%M%S).txt"
    
    {
        echo "Hardware Diagnostic Report"
        echo "Generated: $(date)"
        echo "=============================="
        echo
        
        echo "System Information:"
        uname -a
        echo
        
        echo "CPU Information:"
        lscpu
        echo
        
        echo "Memory Information:"
        free -h
        cat /proc/meminfo | head -10
        echo
        
        echo "Storage Devices:"
        lsblk
        echo
        
        echo "Network Interfaces:"
        ip addr show
        echo
        
        echo "PCI Devices:"
        lspci
        echo
        
        echo "USB Devices:"
        lsusb 2>/dev/null || echo "lsusb not available"
        echo
        
        echo "Kernel Modules:"
        lsmod | head -20
        echo
        
        echo "System Load:"
        uptime
        echo
        
        echo "Disk Usage:"
        df -h
        echo
        
    } > "$report_file"
    
    log_message "SUCCESS" "Hardware report saved to: $report_file"
    
    echo "View report now? (y/N): "
    read -n 1 view_report
    echo
    
    if [[ $view_report =~ ^[Yy]$ ]]; then
        less "$report_file"
    fi
}

interactive_hardware_test() {
    echo -e "${BOLD}Hardware Diagnostics Tool${NC}"
    echo
    
    echo "Select test to run:"
    echo "1) Quick hardware overview"
    echo "2) Memory test"
    echo "3) CPU test"
    echo "4) Storage test"
    echo "5) Network test"
    echo "6) USB ports test"
    echo "7) Run all tests"
    echo "8) Generate hardware report"
    echo
    
    read -p "Select option (1-8): " test_option
    
    case $test_option in
        1)
            log_message "INFO" "Running quick hardware overview..."
            echo -e "${BOLD}System Overview:${NC}"
            echo "Hostname: $(hostname)"
            echo "Uptime: $(uptime -p)"
            echo "Kernel: $(uname -r)"
            echo "Architecture: $(uname -m)"
            echo
            lscpu | grep "Model name\|CPU(s):"
            free -h | grep "Mem:"
            df -h | grep "/$"
            ;;
        2) test_memory ;;
        3) test_cpu ;;
        4) test_storage ;;
        5) test_network ;;
        6) test_usb_ports ;;
        7)
            log_message "INFO" "Running comprehensive hardware test..."
            test_memory
            echo; test_cpu
            echo; test_storage
            echo; test_network
            echo; test_usb_ports
            ;;
        8) generate_hardware_report ;;
        *)
            log_message "ERROR" "Invalid option"
            return 1
            ;;
    esac
}

main() {
    interactive_hardware_test
}

main "$@"