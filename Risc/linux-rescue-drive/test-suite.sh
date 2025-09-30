#!/bin/bash
#
# Linux Rescue Drive Test Suite
# Comprehensive testing framework for validating rescue operations
#

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

TEST_LOG="/tmp/rescue_drive_tests_$(date +%Y%m%d_%H%M%S).log"
TESTS_PASSED=0
TESTS_FAILED=0
TESTS_TOTAL=0

log_test() {
    local level=$1
    local message=$2
    echo "$(date '+%Y-%m-%d %H:%M:%S') [$level] $message" >> "$TEST_LOG"
    
    case $level in
        "PASS") echo -e "${GREEN}[PASS]${NC} $message" ;;
        "FAIL") echo -e "${RED}[FAIL]${NC} $message" ;;
        "INFO") echo -e "${BLUE}[INFO]${NC} $message" ;;
        "WARN") echo -e "${YELLOW}[WARN]${NC} $message" ;;
    esac
}

run_test() {
    local test_name=$1
    local test_function=$2
    
    TESTS_TOTAL=$((TESTS_TOTAL + 1))
    echo -e "${CYAN}Running test: $test_name${NC}"
    
    if $test_function; then
        log_test "PASS" "$test_name"
        TESTS_PASSED=$((TESTS_PASSED + 1))
    else
        log_test "FAIL" "$test_name"
        TESTS_FAILED=$((TESTS_FAILED + 1))
    fi
    echo
}

# Test USB Creation Safety
test_usb_device_detection() {
    log_test "INFO" "Testing USB device detection safety..."
    
    # Check if the script correctly identifies removable devices
    local script_output=$(bash -c "source /data/Risc/linux-rescue-drive/create-usb.sh && show_safe_devices" 2>/dev/null)
    
    if echo "$script_output" | grep -q "FIXED DISK - BE CAREFUL"; then
        log_test "PASS" "Script correctly warns about fixed disks"
        return 0
    else
        log_test "FAIL" "Script does not properly warn about fixed disks"
        return 1
    fi
}

test_usb_verification() {
    log_test "INFO" "Testing USB verification logic..."
    
    # Test the verification function exists and has safety checks
    if grep -q "verify_usb_contents" /data/Risc/linux-rescue-drive/create-usb.sh; then
        if grep -q "mount.*mount_point" /data/Risc/linux-rescue-drive/create-usb.sh; then
            log_test "PASS" "USB verification function exists with mount checks"
            return 0
        else
            log_test "FAIL" "USB verification missing proper mount validation"
            return 1
        fi
    else
        log_test "FAIL" "USB verification function missing"
        return 1
    fi
}

# Test Boot Repair Safety
test_boot_repair_safety() {
    log_test "INFO" "Testing boot repair safety mechanisms..."
    
    # Check for dual-boot detection
    if grep -q "check_windows_dualboot" /data/Risc/linux-rescue-drive/autofix/safe-boot-repair.sh; then
        log_test "PASS" "Dual-boot detection present"
    else
        log_test "FAIL" "Missing dual-boot detection"
        return 1
    fi
    
    # Check for backup mechanism
    if grep -q "create_backup" /data/Risc/linux-rescue-drive/autofix/safe-boot-repair.sh; then
        log_test "PASS" "Backup mechanism present"
    else
        log_test "FAIL" "Missing backup mechanism"
        return 1
    fi
    
    # Check for rollback capability
    if grep -q "cleanup_on_error" /data/Risc/linux-rescue-drive/autofix/safe-boot-repair.sh; then
        log_test "PASS" "Error cleanup mechanism present"
        return 0
    else
        log_test "FAIL" "Missing error cleanup mechanism"
        return 1
    fi
}

test_filesystem_detection() {
    log_test "INFO" "Testing filesystem type detection..."
    
    local supported_fs=("ext2" "ext3" "ext4" "xfs" "btrfs" "ntfs")
    local detection_count=0
    
    for fs in "${supported_fs[@]}"; do
        if grep -q "$fs" /data/Risc/linux-rescue-drive/autofix/filesystem-repair.sh; then
            detection_count=$((detection_count + 1))
        fi
    done
    
    if [ "$detection_count" -ge 4 ]; then
        log_test "PASS" "Multiple filesystem types supported ($detection_count/6)"
        return 0
    else
        log_test "FAIL" "Insufficient filesystem support ($detection_count/6)"
        return 1
    fi
}

# Test Error Handling
test_error_logging() {
    log_test "INFO" "Testing error logging mechanisms..."
    
    local scripts_with_logging=0
    local total_scripts=0
    
    for script in /data/Risc/linux-rescue-drive/autofix/*.sh; do
        total_scripts=$((total_scripts + 1))
        if grep -q "LOG_FILE\|log_message\|>.*log" "$script"; then
            scripts_with_logging=$((scripts_with_logging + 1))
        fi
    done
    
    local logging_percentage=$((scripts_with_logging * 100 / total_scripts))
    
    if [ "$logging_percentage" -ge 80 ]; then
        log_test "PASS" "Good logging coverage ($logging_percentage%)"
        return 0
    else
        log_test "FAIL" "Poor logging coverage ($logging_percentage%)"
        return 1
    fi
}

test_network_safety() {
    log_test "INFO" "Testing network repair safety..."
    
    # Check for backup of network configuration
    if grep -q "backup\|\.backup" /data/Risc/linux-rescue-drive/autofix/network-repair.sh; then
        log_test "PASS" "Network configuration backup mechanism present"
    else
        log_test "FAIL" "Missing network configuration backup"
        return 1
    fi
    
    # Check for connectivity testing before changes
    if grep -q "ping.*test\|connectivity.*test" /data/Risc/linux-rescue-drive/autofix/network-repair.sh; then
        log_test "PASS" "Connectivity testing present"
        return 0
    else
        log_test "WARN" "Limited connectivity testing"
        return 0  # Warning, not failure
    fi
}

# Test Script Dependencies
test_script_dependencies() {
    log_test "INFO" "Testing script dependencies..."
    
    local missing_deps=()
    local critical_tools=("mount" "umount" "lsblk" "blkid" "dd" "sync")
    
    for tool in "${critical_tools[@]}"; do
        if ! command -v "$tool" >/dev/null 2>&1; then
            missing_deps+=("$tool")
        fi
    done
    
    if [ ${#missing_deps[@]} -eq 0 ]; then
        log_test "PASS" "All critical dependencies available"
        return 0
    else
        log_test "FAIL" "Missing dependencies: ${missing_deps[*]}"
        return 1
    fi
}

# VM Testing Simulation
test_vm_compatibility() {
    log_test "INFO" "Testing VM compatibility indicators..."
    
    # Check if running in VM
    local is_vm=0
    
    if [ -f /proc/cpuinfo ]; then
        if grep -qi "hypervisor\|vmware\|virtualbox\|qemu\|kvm" /proc/cpuinfo; then
            is_vm=1
        fi
    fi
    
    if dmesg 2>/dev/null | grep -qi "virtual\|vmware\|qemu\|kvm"; then
        is_vm=1
    fi
    
    if [ "$is_vm" -eq 1 ]; then
        log_test "INFO" "Running in virtual environment - good for testing"
        
        # Check for VM-specific adaptations in scripts
        if grep -q "virtual\|vm\|qemu\|kvm" /data/Risc/linux-rescue-drive/autofix/*.sh; then
            log_test "PASS" "Scripts contain VM awareness"
        else
            log_test "WARN" "Scripts lack VM-specific adaptations"
        fi
        return 0
    else
        log_test "INFO" "Running on physical hardware"
        return 0
    fi
}

# Test Documentation Completeness
test_documentation() {
    log_test "INFO" "Testing documentation completeness..."
    
    local doc_files=("README.md" "CHANGELOG.md" "LICENSE")
    local missing_docs=()
    
    for doc in "${doc_files[@]}"; do
        if [ ! -f "/data/Risc/linux-rescue-drive/$doc" ]; then
            missing_docs+=("$doc")
        fi
    done
    
    if [ ${#missing_docs[@]} -eq 0 ]; then
        log_test "PASS" "All documentation files present"
    else
        log_test "FAIL" "Missing documentation: ${missing_docs[*]}"
        return 1
    fi
    
    # Check README completeness
    local readme_sections=("Features" "Usage" "Installation" "Requirements")
    local missing_sections=()
    
    for section in "${readme_sections[@]}"; do
        if ! grep -q "$section" /data/Risc/linux-rescue-drive/README.md; then
            missing_sections+=("$section")
        fi
    done
    
    if [ ${#missing_sections[@]} -eq 0 ]; then
        log_test "PASS" "README contains all essential sections"
        return 0
    else
        log_test "WARN" "README missing sections: ${missing_sections[*]}"
        return 0  # Warning, not failure
    fi
}

# Security Test
test_security_measures() {
    log_test "INFO" "Testing security measures..."
    
    local security_score=0
    
    # Check for privilege escalation protection
    if grep -q "sudo.*-n\|EUID\|whoami" /data/Risc/linux-rescue-drive/autofix/*.sh; then
        security_score=$((security_score + 1))
        log_test "PASS" "Privilege checking present"
    fi
    
    # Check for input validation
    if grep -qE "\[\[.*=~|\-z.*\$|test.*\-[bfdr]" /data/Risc/linux-rescue-drive/autofix/*.sh; then
        security_score=$((security_score + 1))
        log_test "PASS" "Input validation present"
    fi
    
    # Check for path sanitization
    if grep -qE "realpath|readlink.*-f|basename|dirname" /data/Risc/linux-rescue-drive/autofix/*.sh; then
        security_score=$((security_score + 1))
        log_test "PASS" "Path sanitization present"
    fi
    
    if [ "$security_score" -ge 2 ]; then
        log_test "PASS" "Adequate security measures ($security_score/3)"
        return 0
    else
        log_test "FAIL" "Insufficient security measures ($security_score/3)"
        return 1
    fi
}

# Performance Test
test_performance_indicators() {
    log_test "INFO" "Testing performance considerations..."
    
    # Check for progress indicators
    if grep -q "progress\|status.*progress" /data/Risc/linux-rescue-drive/*.sh; then
        log_test "PASS" "Progress indicators present"
    else
        log_test "WARN" "Limited progress indicators"
    fi
    
    # Check for timeout mechanisms
    if grep -qE "timeout|sleep.*[0-9]" /data/Risc/linux-rescue-drive/autofix/*.sh; then
        log_test "PASS" "Timeout mechanisms present"
        return 0
    else
        log_test "WARN" "Limited timeout handling"
        return 0  # Warning, not failure
    fi
}

# Create Test Scenarios
create_test_scenarios() {
    log_test "INFO" "Creating test scenarios..."
    
    echo "Test Scenarios for Manual Validation:"
    echo "===================================="
    echo
    echo "1. GRUB Corruption Test:"
    echo "   - In VM: sudo rm /boot/grub/grub.cfg"
    echo "   - Boot rescue drive and run boot repair"
    echo "   - Verify GRUB menu regenerated correctly"
    echo
    echo "2. Filesystem Error Test:"
    echo "   - In VM: Create filesystem errors with 'dd if=/dev/zero of=/dev/sdaX bs=1024 count=10'"
    echo "   - Boot rescue drive and run filesystem check"
    echo "   - Verify errors detected and repaired"
    echo
    echo "3. Network Configuration Test:"
    echo "   - Corrupt /etc/resolv.conf and network interfaces"
    echo "   - Run network repair utility"
    echo "   - Verify connectivity restored"
    echo
    echo "4. Dual-boot Safety Test:"
    echo "   - Create VM with Windows and Linux partitions"
    echo "   - Run boot repair on Linux partition"
    echo "   - Verify Windows partition untouched"
    echo
    echo "5. USB Safety Test:"
    echo "   - Run USB creator with various device types"
    echo "   - Verify proper warnings for fixed disks"
    echo "   - Test USB verification after creation"
    
    return 0
}

# Mock Broken System Tests
test_broken_system_detection() {
    log_test "INFO" "Testing broken system detection capabilities..."
    
    # Test filesystem detection in various states
    local detection_mechanisms=()
    
    if grep -q "lsblk.*FSTYPE" /data/Risc/linux-rescue-drive/autofix/*.sh; then
        detection_mechanisms+=("lsblk")
    fi
    
    if grep -q "blkid" /data/Risc/linux-rescue-drive/autofix/*.sh; then
        detection_mechanisms+=("blkid")
    fi
    
    if grep -q "fstab" /data/Risc/linux-rescue-drive/autofix/*.sh; then
        detection_mechanisms+=("fstab")
    fi
    
    if [ ${#detection_mechanisms[@]} -ge 2 ]; then
        log_test "PASS" "Multiple detection mechanisms: ${detection_mechanisms[*]}"
        return 0
    else
        log_test "FAIL" "Insufficient detection mechanisms: ${detection_mechanisms[*]}"
        return 1
    fi
}

# Main Test Runner
run_all_tests() {
    echo -e "${BOLD}${CYAN}Linux Rescue Drive Test Suite${NC}"
    echo "=============================="
    echo "Test log: $TEST_LOG"
    echo
    
    # Core Safety Tests
    run_test "USB Device Detection Safety" test_usb_device_detection
    run_test "USB Verification Logic" test_usb_verification
    run_test "Boot Repair Safety Mechanisms" test_boot_repair_safety
    run_test "Filesystem Type Detection" test_filesystem_detection
    
    # Error Handling Tests
    run_test "Error Logging Coverage" test_error_logging
    run_test "Network Repair Safety" test_network_safety
    run_test "Script Dependencies" test_script_dependencies
    
    # Compatibility Tests
    run_test "VM Compatibility" test_vm_compatibility
    run_test "Broken System Detection" test_broken_system_detection
    
    # Quality Tests
    run_test "Documentation Completeness" test_documentation
    run_test "Security Measures" test_security_measures
    run_test "Performance Indicators" test_performance_indicators
    
    # Generate test scenarios
    run_test "Test Scenario Generation" create_test_scenarios
    
    # Test Summary
    echo
    echo -e "${BOLD}Test Summary${NC}"
    echo "============"
    echo "Total tests: $TESTS_TOTAL"
    echo -e "Passed: ${GREEN}$TESTS_PASSED${NC}"
    echo -e "Failed: ${RED}$TESTS_FAILED${NC}"
    
    local success_rate=$((TESTS_PASSED * 100 / TESTS_TOTAL))
    echo "Success rate: ${success_rate}%"
    
    echo
    echo "Detailed test log: $TEST_LOG"
    
    if [ "$TESTS_FAILED" -eq 0 ]; then
        echo -e "${GREEN}${BOLD}All tests passed! ✓${NC}"
        return 0
    else
        echo -e "${RED}${BOLD}Some tests failed. Please review and fix issues.${NC}"
        return 1
    fi
}

# Interactive Test Mode
interactive_tests() {
    while true; do
        echo
        echo -e "${CYAN}Select test category:${NC}"
        echo "1) Safety Tests"
        echo "2) Error Handling Tests" 
        echo "3) Compatibility Tests"
        echo "4) Quality Tests"
        echo "5) Run All Tests"
        echo "6) View Test Log"
        echo "7) Generate Manual Test Scenarios"
        echo "q) Quit"
        echo
        
        read -p "Select option: " choice
        
        case $choice in
            1)
                run_test "USB Device Detection" test_usb_device_detection
                run_test "Boot Repair Safety" test_boot_repair_safety
                ;;
            2)
                run_test "Error Logging" test_error_logging
                run_test "Network Safety" test_network_safety
                ;;
            3)
                run_test "VM Compatibility" test_vm_compatibility
                run_test "Broken System Detection" test_broken_system_detection
                ;;
            4)
                run_test "Documentation" test_documentation
                run_test "Security Measures" test_security_measures
                ;;
            5)
                run_all_tests
                ;;
            6)
                if [ -f "$TEST_LOG" ]; then
                    echo "Viewing test log..."
                    less "$TEST_LOG"
                else
                    echo "No test log available yet"
                fi
                ;;
            7)
                create_test_scenarios
                ;;
            q|Q)
                echo "Exiting test suite"
                exit 0
                ;;
            *)
                echo "Invalid option"
                ;;
        esac
    done
}

main() {
    if [ "$1" = "--interactive" ]; then
        interactive_tests
    else
        run_all_tests
    fi
}

main "$@"