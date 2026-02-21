#!/bin/bash
# Author: Nihar
# Description: System performance optimizer for Apache and MySQL.

# Function to calculate and set Apache MaxRequestWorkers
set_apache_max_request_workers() {
    echo "Calculating and setting Apache MaxRequestWorkers..."

    # Calculate total RSS of Apache processes
    total_rss=$(ps -C httpd -o rss= | awk '{sum += $1} END {print sum}')

    # Number of Apache processes
    num_processes=$(pgrep -c httpd)

    # Average RSS per Apache process
    average_rss=$(echo "scale=2; $total_rss / $num_processes" | bc)

    # Convert average RSS to MB
    average_rss_mb=$(echo "scale=2; $average_rss / 1024" | bc)

    # Total available memory in MB
    total_memory_mb=$(free -m | awk '/^Mem:/{print $2}')

    # Memory required for non-Apache processes in MB
    non_apache_memory_mb=2048

    # Remaining memory for Apache in MB
    remaining_memory_mb=$(echo "$total_memory_mb - $non_apache_memory_mb" | bc)

    # Average memory usage per Apache process in MB
    average_memory_per_process_mb=$(echo "scale=2; $remaining_memory_mb / $average_rss_mb" | bc)

    # Round up to nearest integer
    max_request_workers=$(echo "scale=0; $average_memory_per_process_mb / 1" | bc)

    # Confirm before setting MaxRequestWorkers
    echo "The recommended MaxRequestWorkers value is $max_request_workers."
    read -p "Do you want to proceed with this change? (y/n): " choice
    if [[ $choice == "y" ]]; then
        # Use WHM API to set MaxRequestWorkers
        whmapi1 set_tweaksetting key=apache_max_clients value=$max_request_workers

        echo "MaxRequestWorkers set to $max_request_workers"
    else
        echo "No changes made to MaxRequestWorkers."
    fi
}

# Function to optimize MySQL configuration
optimize_mysql() {
    echo "Optimizing MySQL configuration..."

    # Calculate total available memory in MB
    total_memory_mb=$(free -m | awk '/^Mem:/{print $2}')

    # Set MySQL configuration parameters based on available memory
    if [ "$total_memory_mb" -lt 2048 ]; then
        # For systems with less than 2GB RAM
        mysql_tweak_file="/etc/my.cnf"
        mysql_config_backup="/etc/my.cnf.backup"
        cp "$mysql_tweak_file" "$mysql_config_backup"

        # Modify MySQL configuration file
        sed -i 's/innodb_buffer_pool_size=.*/innodb_buffer_pool_size=256M/' "$mysql_tweak_file"
        sed -i 's/key_buffer=.*/key_buffer=16M/' "$mysql_tweak_file"

        echo "MySQL optimized for systems with less than 2GB RAM."
    else
        # For systems with 2GB RAM or more
        mysql_tweak_file="/etc/my.cnf"
        mysql_config_backup="/etc/my.cnf.backup"
        cp "$mysql_tweak_file" "$mysql_config_backup"

        # Modify MySQL configuration file
        sed -i 's/innodb_buffer_pool_size=.*/innodb_buffer_pool_size=512M/' "$mysql_tweak_file"
        sed -i 's/key_buffer=.*/key_buffer=32M/' "$mysql_tweak_file"

        echo "MySQL optimized for systems with 2GB RAM or more."
    fi

    # Confirm before restarting MySQL service
    read -p "Do you want to restart MySQL service to apply changes? (y/n): " choice
    if [[ $choice == "y" ]]; then
        # Restart MySQL service
        systemctl restart mysql
        echo "MySQL service restarted."
    else
        echo "No changes made to MySQL configuration."
    fi
}

# Function to optimize system swappiness
optimize_swappiness() {
    echo "Optimizing system swappiness..."

    # Confirm before setting swappiness
    read -p "Do you want to set swappiness to 10? (y/n): " choice
    if [[ $choice == "y" ]]; then
        # Set swappiness to 10
        sysctl vm.swappiness=10

        # Make the change permanent by updating /etc/sysctl.conf
        echo "vm.swappiness=10" >> /etc/sysctl.conf

        echo "Swappiness set to 10."
    else
        echo "No changes made to swappiness."
    fi
}

# Main script

# Check if the script is running with root privileges
if [ "$(id -u)" -ne 0 ]; then
    echo "Please run this script with sudo or as root."
    exit 1
fi

# Confirm before proceeding with optimizations
read -p "This script will optimize server performance. Do you want to continue? (y/n): " choice
if [[ $choice == "y" ]]; then
    # Optimize Apache MaxRequestWorkers
    set_apache_max_request_workers

    # Optimize MySQL configuration
    optimize_mysql

    # Optimize system swappiness
    optimize_swappiness

    echo "Server performance optimization complete."
else
    echo "Optimization cancelled. Exiting..."
fi
