#!/bin/bash
#
# Security Scanner
# Detect malware, rootkits, and security issues
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

scan_rootkits() {
    log_message "INFO" "Scanning for rootkits..."
    
    # Run chkrootkit if available
    if command -v chkrootkit >/dev/null 2>&1; then
        log_message "INFO" "Running chkrootkit scan..."
        local chkrootkit_output=$(sudo chkrootkit 2>/dev/null | grep -E "INFECTED|Possible")
        
        if [ -n "$chkrootkit_output" ]; then
            log_message "WARNING" "chkrootkit found potential issues:"
            echo "$chkrootkit_output"
        else
            log_message "SUCCESS" "chkrootkit scan completed - no issues found"
        fi
    else
        log_message "WARNING" "chkrootkit not available"
    fi
    
    # Run rkhunter if available
    if command -v rkhunter >/dev/null 2>&1; then
        log_message "INFO" "Running rkhunter scan..."
        
        # Update rkhunter database
        sudo rkhunter --update >/dev/null 2>&1 || true
        
        # Run scan
        local rkhunter_output=$(sudo rkhunter --check --sk --nocolors 2>/dev/null | grep -E "Warning|Infected")
        
        if [ -n "$rkhunter_output" ]; then
            log_message "WARNING" "rkhunter found potential issues:"
            echo "$rkhunter_output"
        else
            log_message "SUCCESS" "rkhunter scan completed - no issues found"
        fi
    else
        log_message "WARNING" "rkhunter not available"
    fi
}

check_suspicious_processes() {
    log_message "INFO" "Checking for suspicious processes..."
    
    # Check for processes with unusual names or behavior
    local suspicious_processes=$(ps aux | grep -E "\[.*\].*\[.*\]|[0-9]{8,}|\.\.\.|\s\.\s" | grep -v grep | head -10)
    
    if [ -n "$suspicious_processes" ]; then
        log_message "WARNING" "Found potentially suspicious processes:"
        echo "$suspicious_processes"
    else
        log_message "SUCCESS" "No obviously suspicious processes detected"
    fi
    
    # Check for processes running from /tmp
    local tmp_processes=$(lsof /tmp 2>/dev/null | grep -E "REG.*exe" | head -5)
    if [ -n "$tmp_processes" ]; then
        log_message "WARNING" "Found processes running from /tmp:"
        echo "$tmp_processes"
    fi
    
    # Check for high CPU usage processes
    log_message "INFO" "Checking CPU usage..."
    local high_cpu=$(ps aux --sort=-%cpu | head -5 | tail -4)
    echo "Top CPU processes:"
    echo "$high_cpu"
}

scan_network_connections() {
    log_message "INFO" "Scanning network connections..."
    
    # Check for unusual network connections
    log_message "INFO" "Active network connections:"
    
    # Show listening ports
    echo -e "${BOLD}Listening ports:${NC}"
    ss -tuln | grep LISTEN | while read line; do
        local port=$(echo "$line" | awk '{print $5}' | sed 's/.*://')
        local proto=$(echo "$line" | awk '{print $1}')
        echo "  $proto port $port"
    done
    echo
    
    # Show established connections
    echo -e "${BOLD}Established connections:${NC}"
    ss -tun | grep ESTAB | head -10 | while read line; do
        local local_addr=$(echo "$line" | awk '{print $4}')
        local remote_addr=$(echo "$line" | awk '{print $5}')
        echo "  $local_addr -> $remote_addr"
    done
    echo
    
    # Check for connections to suspicious ports
    local suspicious_connections=$(ss -tun | grep -E ":1337|:31337|:6667|:6697|:1234|:4444|:5555" | wc -l)
    if [ "$suspicious_connections" -gt 0 ]; then
        log_message "WARNING" "Found connections to potentially suspicious ports"
        ss -tun | grep -E ":1337|:31337|:6667|:6697|:1234|:4444|:5555"
    fi
}

check_file_integrity() {
    log_message "INFO" "Checking system file integrity..."
    
    # Check for world-writable files in system directories
    log_message "INFO" "Scanning for world-writable system files..."
    local world_writable=$(find /etc /usr/bin /usr/sbin -type f -perm -002 2>/dev/null | head -5)
    
    if [ -n "$world_writable" ]; then
        log_message "WARNING" "Found world-writable system files:"
        echo "$world_writable"
    else
        log_message "SUCCESS" "No world-writable system files found"
    fi
    
    # Check for SUID files
    log_message "INFO" "Checking SUID files..."
    local unusual_suid=$(find /usr /bin /sbin -type f -perm -4000 2>/dev/null | grep -v -E "sudo|su|passwd|mount|umount|ping|gpasswd|newgrp" | head -10)
    
    if [ -n "$unusual_suid" ]; then
        log_message "WARNING" "Found unusual SUID files:"
        echo "$unusual_suid"
    else
        log_message "SUCCESS" "No unusual SUID files detected"
    fi
    
    # Check for files in /tmp with execute permissions
    local tmp_executables=$(find /tmp -type f -executable 2>/dev/null | head -5)
    if [ -n "$tmp_executables" ]; then
        log_message "WARNING" "Found executable files in /tmp:"
        echo "$tmp_executables"
    fi
}

scan_user_accounts() {
    log_message "INFO" "Scanning user accounts for security issues..."
    
    # Check for users with UID 0 (root privileges)
    local root_users=$(awk -F: '$3 == 0 && $1 != "root" {print $1}' /etc/passwd)
    if [ -n "$root_users" ]; then
        log_message "ERROR" "Found non-root users with UID 0:"
        echo "$root_users"
    else
        log_message "SUCCESS" "No unauthorized root accounts found"
    fi
    
    # Check for users without passwords
    local no_password_users=$(sudo awk -F: '$2 == "" {print $1}' /etc/shadow 2>/dev/null | grep -v "^#")
    if [ -n "$no_password_users" ]; then
        log_message "WARNING" "Found users without passwords:"
        echo "$no_password_users"
    fi
    
    # Check for unusual home directories
    log_message "INFO" "Checking home directories..."
    while IFS=: read -r username _ uid _ _ home _; do
        if [ "$uid" -ge 1000 ] && [ "$uid" -le 60000 ]; then
            if [ -d "$home" ]; then
                # Check for hidden files that might be suspicious
                local hidden_executables=$(find "$home" -name ".*" -type f -executable 2>/dev/null | wc -l)
                if [ "$hidden_executables" -gt 10 ]; then
                    log_message "WARNING" "User $username has many hidden executable files ($hidden_executables)"
                fi
            fi
        fi
    done < /etc/passwd
}

check_system_logs() {
    log_message "INFO" "Analyzing system logs for security events..."
    
    # Check for failed login attempts
    local failed_logins=$(grep "Failed password" /var/log/auth.log 2>/dev/null | wc -l || echo "0")
    if [ "$failed_logins" -gt 50 ]; then
        log_message "WARNING" "High number of failed login attempts: $failed_logins"
        echo "Recent failed attempts:"
        grep "Failed password" /var/log/auth.log 2>/dev/null | tail -5 || echo "No auth.log available"
    fi
    
    # Check for privilege escalation attempts
    local sudo_failures=$(grep "sudo.*FAILED" /var/log/auth.log 2>/dev/null | wc -l || echo "0")
    if [ "$sudo_failures" -gt 10 ]; then
        log_message "WARNING" "Multiple sudo failures detected: $sudo_failures"
    fi
    
    # Check kernel messages for security issues
    local kernel_warnings=$(dmesg | grep -iE "segfault|killed|oom|attack|intrusion" | wc -l)
    if [ "$kernel_warnings" -gt 0 ]; then
        log_message "WARNING" "Found $kernel_warnings security-related kernel messages"
        echo "Recent kernel security messages:"
        dmesg | grep -iE "segfault|killed|oom|attack|intrusion" | tail -5
    fi
}

scan_malware_signatures() {
    log_message "INFO" "Scanning for known malware signatures..."
    
    # Simple signature-based detection for common Linux malware
    local malware_patterns=(
        "/tmp/.*\.sh.*bitcoin"
        "/tmp/.*miner"
        "/tmp/.*\.so\..*"
        ".*xmrig.*"
        ".*cryptonight.*"
        ".*stratum.*"
    )
    
    for pattern in "${malware_patterns[@]}"; do
        local matches=$(find /tmp /var/tmp -name "*" -type f 2>/dev/null | grep -E "$pattern" || true)
        if [ -n "$matches" ]; then
            log_message "WARNING" "Found potential malware matching pattern '$pattern':"
            echo "$matches"
        fi
    done
    
    # Check for cryptocurrency miners
    local crypto_processes=$(ps aux | grep -iE "xmrig|cpuminer|cgminer|bfgminer|ethminer" | grep -v grep)
    if [ -n "$crypto_processes" ]; then
        log_message "WARNING" "Found potential cryptocurrency mining processes:"
        echo "$crypto_processes"
    fi
    
    # Check for botnet-related processes
    local botnet_processes=$(ps aux | grep -iE "\.onion|tor.*proxy|irc.*bot" | grep -v grep)
    if [ -n "$botnet_processes" ]; then
        log_message "WARNING" "Found potential botnet-related processes:"
        echo "$botnet_processes"
    fi
}

generate_security_report() {
    log_message "INFO" "Generating security scan report..."
    
    local report_file="/tmp/security_report_$(date +%Y%m%d_%H%M%S).txt"
    
    {
        echo "Security Scan Report"
        echo "Generated: $(date)"
        echo "=============================="
        echo
        
        echo "System Information:"
        uname -a
        echo "Uptime: $(uptime -p)"
        echo
        
        echo "User Accounts:"
        cat /etc/passwd | wc -l | xargs echo "Total users:"
        awk -F: '$3 >= 1000 && $3 <= 60000 {print $1}' /etc/passwd | wc -l | xargs echo "Regular users:"
        echo
        
        echo "Network Status:"
        ss -tuln | grep LISTEN | wc -l | xargs echo "Listening ports:"
        ss -tun | grep ESTAB | wc -l | xargs echo "Active connections:"
        echo
        
        echo "Process Information:"
        ps aux | wc -l | xargs echo "Total processes:"
        ps aux --sort=-%cpu | head -5
        echo
        
        echo "File System Security:"
        find /etc /usr/bin /usr/sbin -type f -perm -002 2>/dev/null | wc -l | xargs echo "World-writable system files:"
        find /usr /bin /sbin -type f -perm -4000 2>/dev/null | wc -l | xargs echo "SUID files:"
        echo
        
    } > "$report_file"
    
    log_message "SUCCESS" "Security report saved to: $report_file"
    
    echo "View report now? (y/N): "
    read -n 1 view_report
    echo
    
    if [[ $view_report =~ ^[Yy]$ ]]; then
        less "$report_file"
    fi
}

interactive_security_scan() {
    echo -e "${BOLD}Security Scanner${NC}"
    echo
    
    echo "Select security scan type:"
    echo "1) Quick security overview"
    echo "2) Rootkit scan"
    echo "3) Process analysis"
    echo "4) Network security scan"
    echo "5) File integrity check"
    echo "6) User account audit"
    echo "7) System log analysis"
    echo "8) Malware signature scan"
    echo "9) Comprehensive security scan"
    echo "10) Generate security report"
    echo
    
    read -p "Select option (1-10): " scan_option
    
    case $scan_option in
        1)
            log_message "INFO" "Quick security overview..."
            check_suspicious_processes
            scan_user_accounts
            ;;
        2) scan_rootkits ;;
        3) check_suspicious_processes ;;
        4) scan_network_connections ;;
        5) check_file_integrity ;;
        6) scan_user_accounts ;;
        7) check_system_logs ;;
        8) scan_malware_signatures ;;
        9)
            log_message "INFO" "Running comprehensive security scan..."
            scan_rootkits
            check_suspicious_processes
            scan_network_connections
            check_file_integrity
            scan_user_accounts
            check_system_logs
            scan_malware_signatures
            ;;
        10) generate_security_report ;;
        *)
            log_message "ERROR" "Invalid option"
            return 1
            ;;
    esac
}

main() {
    interactive_security_scan
}

main "$@"