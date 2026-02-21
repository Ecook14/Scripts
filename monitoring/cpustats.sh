#!/bin/bash
# Author: Nihar
# Description: Real-time CPU performance and I/O wait monitor.

# Default thresholds
IO_WAIT_THRESHOLD=10
CPU_IDLE_THRESHOLD=25
SWAP_USAGE_THRESHOLD=100

# Function to check if a command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to install required packages
install_requirements() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
    fi

    echo "Detected distribution: ${ID:-Unknown}"
    echo "1. Ubuntu/Debian"
    echo "2. CentOS/Rocky/AlmaLinux"
    echo "3. Manual selection"
    read -p "Select your distribution (1/2/3): " distro_choice

    case $distro_choice in
        1|Ubuntu|Debian)
            packages=(bc iotop vmstat)
            for pkg in "${packages[@]}"; do
                if ! command_exists "$pkg"; then
                    echo "Installing $pkg..."
                    sudo apt update
                    sudo apt install -y "$pkg"
                else
                    echo "$pkg is already installed."
                fi
            done
            ;;
        2|CentOS|Rocky|AlmaLinux)
            packages=(bc iotop vmstat)
            sudo yum install -y epel-release
            for pkg in "${packages[@]}"; do
                if ! command_exists "$pkg"; then
                    echo "Installing $pkg..."
                    sudo yum install -y "$pkg"
                else
                    echo "$pkg is already installed."
                fi
            done
            ;;
        3)
            echo "1. Ubuntu/Debian"
            echo "2. CentOS/Rocky/AlmaLinux"
            read -p "Select your distribution manually (1/2): " manual_choice
            case $manual_choice in
                1)
                    packages=(bc iotop vmstat)
                    for pkg in "${packages[@]}"; do
                        if ! command_exists "$pkg"; then
                            echo "Installing $pkg..."
                            sudo apt update
                            sudo apt install -y "$pkg"
                        else
                            echo "$pkg is already installed."
                        fi
                    done
                    ;;
                2)
                    packages=(bc iotop vmstat)
                    sudo yum install -y epel-release
                    for pkg in "${packages[@]}"; do
                        if ! command_exists "$pkg"; then
                            echo "Installing $pkg..."
                            sudo yum install -y "$pkg"
                        else
                            echo "$pkg is already installed."
                        fi
                    done
                    ;;
                *)
                    echo "Invalid selection."
                    exit 1
                    ;;
            esac
            ;;
        *)
            echo "Invalid selection."
            exit 1
            ;;
    esac
}

# Prompt user to adjust thresholds
adjust_thresholds() {
    read -p "Current I/O wait threshold ($IO_WAIT_THRESHOLD%): " input
    IO_WAIT_THRESHOLD=${input:-$IO_WAIT_THRESHOLD}

    read -p "Current CPU idle threshold ($CPU_IDLE_THRESHOLD%): " input
    CPU_IDLE_THRESHOLD=${input:-$CPU_IDLE_THRESHOLD}

    read -p "Current swap usage threshold ($SWAP_USAGE_THRESHOLD MB): " input
    SWAP_USAGE_THRESHOLD=${input:-$SWAP_USAGE_THRESHOLD}
}

# Backup configurations (example: sysctl)
backup_config() {
    echo "Backing up configurations..."
    sudo cp /etc/sysctl.conf /etc/sysctl.conf.bak
    echo "Backup completed: /etc/sysctl.conf.bak"
}

# Final approval before applying changes
apply_changes() {
    echo "Review the suggested changes:"
    echo "I/O wait threshold: $IO_WAIT_THRESHOLD%"
    echo "CPU idle threshold: $CPU_IDLE_THRESHOLD%"
    echo "Swap usage threshold: $SWAP_USAGE_THRESHOLD MB"

    read -p "Proceed with these changes? (y/n): " confirm
    if [[ $confirm == [yY] ]]; then
        echo "Applying changes..."
        # Example: Applying sysctl changes (customize as needed)
        # sudo sysctl -p
        echo "Changes applied."
    else
        echo "Changes not applied."
    fi
}

# Step 1: Check I/O wait and CPU idle time
check_system() {
    output=$(top -b -n1 | grep 'Cpu(s)')
    io_wait=$(echo "$output" | awk '{print $10}' | sed 's/%//')
    cpu_idle=$(echo "$output" | awk '{print $8}' | sed 's/%//')

    echo "I/O Wait: $io_wait%"
    echo "CPU Idle: $cpu_idle%"

    if (( $(echo "$io_wait < $IO_WAIT_THRESHOLD" | bc -l) )) && (( $(echo "$cpu_idle < $CPU_IDLE_THRESHOLD" | bc -l) )); then
        echo "Low I/O wait and low CPU idle time detected."
        echo "Checking CPU user time..."
        top -b -n1 | head -n 12 | tail -n +8 | sort -k9 -n -r | head -5
    elif (( $(echo "$io_wait < $IO_WAIT_THRESHOLD" | bc -l) )) && (( $(echo "$cpu_idle >= $CPU_IDLE_THRESHOLD" | bc -l) )); then
        echo "Low I/O wait and high CPU idle time detected."
        echo "Check applications for specific slowness or external issues."
    elif (( $(echo "$io_wait >= $IO_WAIT_THRESHOLD" | bc -l) )); then
        echo "High I/O wait detected."
        echo "Checking swap usage..."
        swap_used=$(free -m | awk '/Swap/{print $3}')
        echo "Swap Used: $swap_used MB"
        if (( swap_used > $SWAP_USAGE_THRESHOLD )); then
            echo "High swap usage detected."
            echo "Consider adding RAM or optimizing memory usage."
        else
            echo "Low swap usage. Checking I/O hogs with iotop..."
            iotop -b -n1 -o | head -5
        fi
    elif (( $(echo "$cpu_idle < $CPU_IDLE_THRESHOLD" | bc -l) )); then
        echo "Low CPU idle time. Checking memory usage..."
        top -b -n1 | head -n 12 | tail -n +8 | sort -k10 -n -r | head -5
    else
        echo "System seems normal. No significant issues detected."
    fi
}

# Main script
install_requirements
adjust_thresholds
backup_config
check_system
apply_changes

# Additional tips
echo -e "\nAdditional Tips:"
echo "1. Use vmstat for historical metrics:"
echo "   Run: vmstat 1 for real-time metrics."
echo "2. Track disk I/O latency and compare with IOPS to identify potential issues."
echo "3. Increasing I/O latency can indicate failing disks or bad sectors."
echo "4. Monitor historical performance graphs to identify trends and anomalies."
