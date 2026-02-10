#!/bin/bash

function main_menu() {
    while true; do
        clear
        echo "=== Main Menu ==="
        echo "1. Log"
        echo "2. Network"
        echo "3. File System Search"
        echo "4. Exit"
        read -p "Select an option (1-4): " choice

        case $choice in
            1) log_menu ;;
            2) network_menu ;;
            3) file_system_search_menu ;;
            4) exit ;;
            *) echo "Invalid option. Please choose a valid option." ;;
        esac

        # If the user selects 'Exit', break the loop and exit the script
        if [ "$choice" == "4" ]; then
            break
        fi
    done
}

function log_menu() {
    while true; do
        clear
        echo "=== Log Menu ==="
        echo "1. Apache Log"
        echo "2. Access Log"
        echo "3. Exim Logs"
        echo "4. System Log"
        echo "5. FTP Log"
        echo "6. MySQL Logs"
        echo "7. Back to Main Menu"
        read -p "Select an option (1-7): " log_choice

        case $log_choice in
            1) apache_log ;;
            2) access_log ;;
            3) exim_logs ;;
            4) system_logs ;;
            5) ftp_logs ;;
            6) mysql_logs ;;
            7) main_menu ;;
            *) echo "Invalid option. Please choose a valid option." ;;
        esac

        # If the user selects 'Back to Main Menu', break the loop and return to the main menu
        if [ "$log_choice" == "7" ]; then
            break
        fi
    done
}

#Apache Log Function
function apache_log() {
    while true; do
        clear
        echo "=== Apache Log ==="
        echo "1. Live Logs : Tail"
        echo "2. Archive logs:"
        echo "   1. Today"
        echo "   2. Yesterday"
        echo "   3. Custom"
        read -p "Select an option (1-3): " apache_option

        case $apache_option in
            1) tail_apache_log ;;
            2) archive_apache_log ;;
            3) custom_apache_log ;;
            *) echo "Invalid option. Please choose a valid option." ;;
        esac

        # If the user selects 'Back to Main Menu', break the loop and return to the main menu
        if [ "$apache_option" == "7" ]; then
            break
        fi
    done
}

# Tail Apache Log
function tail_apache_log() {
    clear
    echo "=== Tail Apache Log ==="
    echo "Enter the domain name" 
    read domain
    # Validate domain name
    if [ -z "$domain" ]; then
        echo "Domain name cannot be empty."
        return 1
    fi
    tail -n 10 /var/log/apache2/access.log | grep "$domain"
    read -p "Press Enter to return to the Apache Log Menu"
    apache_log
}

# Archive Apache Log
function archive_apache_log() {
    clear
    echo "=== Archive Apache Log ==="
    echo "1. Display today's archived logs"
    echo "2. Display yesterday's archived logs"
    echo "3. Display custom date archived logs"
    read -p "Select an option (1-3): " archive_option

    case $archive_option in
        1) display_archive_logs "today" ;;
        2) display_archive_logs "yesterday" ;;
        3) display_archive_logs "custom" ;;
        *) echo "Invalid option. Please choose a valid option." ;;
    esac

    read -p "Press Enter to return to the Apache Log Menu"
    apache_log
}

# Display Exim Archive
function display_archive_logs() {
    clear
    local archive_date=""
    case $1 in
        "today")
            archive_date=$(date "+%Y-%m-%d")
            ;;
        "yesterday")
            archive_date=$(date -d "yesterday" "+%Y-%m-%d")
            ;;
        "custom")
            read -p "Enter custom date (mm/dd/yy): " custom_date
            archive_date=$(date -d "$custom_date" "+%Y-%m-%d" 2>/dev/null)
            if [ -z "$archive_date" ]; then
                echo "Invalid date format. Exiting."
                return 1
            fi
            ;;
        *)
            echo "Invalid option. Exiting."
            return 1
            ;;
    esac

    echo "Enter the domain name:"
    read domain
    # Validate domain name
    if [ -z "$domain" ]; then
        echo "Domain name cannot be empty."
        return 1
    fi
    grep "$domain" /var/log/apache2/access.log | grep "$archive_date"
}

# Access Log Function
function access_log() {
    clear
    echo "=== Access Log ==="
    echo "1. Live Logs : Tail"
    echo "2. Archive logs:"
    echo "   1. Today"
    echo "   2. Yesterday"
    echo "   3. Custom"
    read -p "Select an option (1-3): " access_option

    case $access_option in
        1) tail_access_log ;;
        2) archive_access_log ;;
        3) custom_access_log ;;
        *) echo "Invalid option. Please choose a valid option." ;;
    esac
}

function tail_access_log() {
    clear
    echo "=== Tail Access Log ==="
    echo "Enter the Cpanel username:"
    read cpanelusername
    tail -n 10 /usr/local/cpanel/logs/access_log | grep "$cpanelusername"
    read -p "Press Enter to return to the Access Log Menu"
    access_log
}

function archive_access_log() {
    clear
    echo "=== Archive Access Log ==="
    echo "1. Display today's archived logs"
    echo "2. Display yesterday's archived logs"
    echo "3. Display custom date archived logs"
    read -p "Select an option (1-3): " archive_option

    case $archive_option in
        1) display_access_archive "today" ;;
        2) display_access_archive "yesterday" ;;
        3) display_access_archive "custom" ;;
        *) echo "Invalid option. Please choose a valid option." ;;
    esac

    read -p "Press Enter to return to the Access Log Menu"
    access_log
}

function display_access_archive() {
    local archive_date=""
    case $1 in
        "today")
            archive_date=$(date "+%Y-%m-%d")
            ;;
        "yesterday")
            archive_date=$(date -d "yesterday" "+%Y-%m-%d")
            ;;
        "custom")
            read -p "Enter custom date (mm/dd/yy): " custom_date
            archive_date=$(date -d "$custom_date" "+%Y-%m-%d" 2>/dev/null)
            if [ -z "$archive_date" ]; then
                echo "Invalid date format. Exiting."
                exit 1
            fi
            ;;
        *)
            echo "Invalid option. Exiting."
            exit 1
            ;;
    esac

    echo "Enter the Cpanel username:"
    read cpanelusername
    grep "$cpanelusername" /usr/local/cpanel/logs/access_log | grep "$archive_date"
}

# Exim Logs Function
function exim_logs() {
    clear
    echo "=== Exim Logs ==="
    echo "1. Live Logs : Tail"
    echo "2. Archive logs:"
    echo "   1. Today"
    echo "   2. Yesterday"
    echo "   3. Custom"
    echo "3. View Exim Mainlog"
    echo "4. View Queue Size"
    echo "5. View Dovecot Login Counts"
    echo "6. View Sender Domains"
    echo "7. Back to Log Menu"
    read -p "Select an option (1-7): " exim_option

    case $exim_option in
        1) tail_exim_log ;;
        2) archive_exim_log ;;
        3) custom_exim_log ;;
        4) view_exim_mainlog ;;
        5) view_queue_size ;;
        6) view_dovecot_login_counts ;;
        7) view_sender_domains ;;
        8) log_menu ;;
        *) echo "Invalid option. Please choose a valid option." ;;
    esac
}

# Tail Exim Log
function tail_exim_log() {
    clear
    echo "=== Tail Exim Log ==="
    read -p "Enter the domain or email: " domain_email
    tail -n 10 /var/log/exim_mainlog | grep "$domain_email"
    read -p "Press Enter to return to the Exim Logs Menu"
    exim_logs
}

# Archive Exim Log
function archive_exim_log() {
    clear
    echo "=== Archive Exim Log ==="
    echo "1. Display today's archived logs"
    echo "2. Display yesterday's archived logs"
    echo "3. Display custom date archived logs"
    read -p "Select an option (1-3): " archive_option

    case $archive_option in
        1) display_exim_archive "today" ;;
        2) display_exim_archive "yesterday" ;;
        3) display_exim_archive "custom" ;;
        *) echo "Invalid option. Please choose a valid option." ;;
    esac

    read -p "Press Enter to return to the Exim Logs Menu"
    exim_logs
}

# Display Exim Archive
function display_exim_archive() {
    clear
    local archive_date=""
    case $1 in
        "today") archive_date=$(date "+%Y-%m-%d") ;;
        "yesterday") archive_date=$(date -d "yesterday" "+%Y-%m-%d") ;;
        "custom")
            read -p "Enter custom date (mm/dd/yy): " custom_date
            archive_date=$(date -d "$custom_date" "+%Y-%m-%d" 2>/dev/null)
            if [ -z "$archive_date" ]; then
                echo "Invalid date format. Exiting."
                exit 1
            fi
            ;;
        *) echo "Invalid option. Exiting." ;;
    esac

    read -p "Enter the domain or email: " domain_email
    grep "$domain_email" /var/log/exim_mainlog | grep "$archive_date"
    read -p "Press Enter to return to the Exim Logs Menu"
    exim_logs
}

# View Exim Mainlog
function view_exim_mainlog() {
    clear
    echo "=== View Exim Mainlog ==="
    read -p "Enter the domain or email: " domain_email
    grep "$domain_email" /var/log/exim_mainlog
    read -p "Press Enter to return to the Exim Logs Menu"
    exim_logs
}

# View Queue Size
function view_queue_size() {
    clear
    echo "=== View Queue Size ==="
    exim -bpc
    read -p "Press Enter to return to the Exim Logs Menu"
    exim_logs
}

# View Dovecot Login Counts
function view_dovecot_login_counts() {
    clear
    echo "=== View Dovecot Login Counts ==="
    egrep -o 'dovecot_login[^ ]+' /var/log/exim_mainlog | sort | uniq -c | sort -nk 1
    read -p "Press Enter to return to the Exim Logs Menu"
    exim_logs
}

# View Sender Domains
function view_sender_domains() {
    clear
    echo "=== View Sender Domains ==="
    exim -bpr | grep "<" | awk {'print $4'} | cut -d"<" -f2 | cut -d">" -f1 | sort -n | uniq -c | sort -n
    read -p "Press Enter to return to the Exim Logs Menu"
    exim_logs
}

# System Log
function system_logs() {
    clear
    echo "=== System Logs ==="
    echo "1. Search Systemlogs (Message log)"
    echo "2. Archive logs:"
    echo "   1. Yesterday"
    echo "   2. Today"
    echo "   3. Custom"
    echo "3. Back to Log Menu"
    read -p "Select an option (1-3): " system_option

    case $system_option in
        1) search_system_logs ;;
        2) archive_system_logs ;;
        3) log_menu ;;
        *) echo "Invalid option. Please choose a valid option." ;;
    esac
}

# Search System Logs
function search_system_logs() {
    clear
    echo "=== Search Systemlogs (Message log) ==="
    read -p "Please enter the search keyword: " search_keyword
    grep "$search_keyword" /var/log/messages
    read -p "Press Enter to return to the System Logs Menu"
    system_logs
}

# Archive System Logs
function archive_system_logs() {
    clear
    echo "=== Archive System Logs ==="
    echo "1. Yesterday"
    echo "2. Today"
    echo "3. Custom"
    read -p "Select an option (1-3): " archive_option

    case $archive_option in
        1) display_system_archive "yesterday" ;;
        2) display_system_archive "today" ;;
        3) display_system_archive "custom" ;;
        *) echo "Invalid option. Please choose a valid option." ;;
    esac

    read -p "Press Enter to return to the System Logs Menu"
    system_logs
}

# Display System Archive
function display_system_archive() {
    clear
    local start_date=""
    local end_date=""

    case $1 in
        "yesterday")
            start_date=$(date -d "yesterday" "+%Y-%m-%d")
            end_date=$(date -d "yesterday" "+%Y-%m-%d")
            ;;
        "today")
            start_date=$(date "+%Y-%m-%d")
            end_date=$(date "+%Y-%m-%d")
            ;;
        "custom")
            read -p "Please enter your start date (YYYY-MM-DD): " start_date
            read -p "Please enter your end date (YYYY-MM-DD): " end_date
            ;;
        *)
            echo "Invalid option. Exiting."
            exit 1
            ;;
    esac

    echo "Start Date: $start_date"
    echo "End Date: $end_date"
    read -p "Enter the search keyword: " search_keyword
    # Logic to display logs within specified date range
    grep -E "^($start_date|$end_date).*${search_keyword}" /var/log/messages
    read -p "Press Enter to return to the System Logs Menu"
    system_logs
}

# FTP Logs Function
function ftp_logs() {
    clear
    echo "=== FTP Logs ==="
    read -p "Please enter the FTP Username: " ftp_username
    echo "1. Archive logs:"
    echo "   1. Yesterday"
    echo "   2. Today"
    echo "   3. Custom"
    echo "2. Back to Log Menu"
    read -p "Select an option (1-2): " ftp_option

    case $ftp_option in
        1) archive_ftp_logs ;;
        2) log_menu ;;
        *) echo "Invalid option. Please choose a valid option." ;;
    esac
}

# Archive FTP Logs
function archive_ftp_logs() {
    clear
    echo "=== Archive FTP Logs ==="
    echo "1. Yesterday"
    echo "2. Today"
    echo "3. Custom"
    read -p "Select an option (1-3): " archive_option

    case $archive_option in
        1) display_ftp_archive "yesterday" ;;
        2) display_ftp_archive "today" ;;
        3) display_ftp_archive "custom" ;;
        *) echo "Invalid option. Please choose a valid option." ;;
    esac

    read -p "Press Enter to return to the FTP Logs Menu"
    ftp_logs
}

# Display FTP Archive
function display_ftp_archive() {
    clear
    local start_date=""
    local end_date=""

    case $1 in
        "yesterday")
            start_date=$(date -d "yesterday" "+%Y-%m-%d")
            end_date=$(date -d "yesterday" "+%Y-%m-%d")
            ;;
        "today")
            start_date=$(date "+%Y-%m-%d")
            end_date=$(date "+%Y-%m-%d")
            ;;
        "custom")
            read -p "Please enter your start date (YYYY-MM-DD): " start_date
            read -p "Please enter your end date (YYYY-MM-DD): " end_date
            ;;
        *)
            echo "Invalid option. Exiting."
            exit 1
            ;;
    esac

    echo "Start Date: $start_date"
    echo "End Date: $end_date"

    # Logic to display FTP logs within specified date range
    # Replace the path below with the actual path to FTP logs
    read -p "Enter the search keyword: " ftpusername
    grep -E "^($start_date|$end_date).*${ftpusername}" /var/log/vsftpd.log
    read -p "Press Enter to return to the FTP Logs Menu"
    ftp_logs
}


# MySQL Logs Function
function mysql_logs() {
    clear
    echo "=== MySQL Logs ==="
    read -p "Please enter the MySQL Database/Username: " mysql_database
    echo "1. Archive logs"
    echo "2. Back to Log Menu"
    read -p "Select an option (1-2): " mysql_option

    case $mysql_option in
        1) archive_mysql_logs ;;
        2) log_menu ;;
        *) echo "Invalid option. Please choose a valid option." ;;
    esac
}

# Archive MySQL Logs
function archive_mysql_logs() {
    clear
    echo "=== Archive MySQL Logs ==="
    echo "1. Yesterday"
    echo "2. Today"
    echo "3. Custom"
    read -p "Select an option (1-3): " archive_option

    case $archive_option in
        1) display_mysql_archive "yesterday" ;;
        2) display_mysql_archive "today" ;;
        3) display_mysql_archive "custom" ;;
        *) echo "Invalid option. Please choose a valid option." ;;
    esac

    read -p "Press Enter to return to the MySQL Logs Menu"
    mysql_logs
}

# Display MySQL Archive
function display_mysql_archive() {
    clear
    local start_date=""
    local end_date=""

    case $1 in
        "yesterday")
            start_date=$(date -d "yesterday" "+%Y-%m-%d")
            end_date=$(date -d "yesterday" "+%Y-%m-%d")
            ;;
        "today")
            start_date=$(date "+%Y-%m-%d")
            end_date=$(date "+%Y-%m-%d")
            ;;
        "custom")
            read -p "Please enter your start date (YYYY-MM-DD): " start_date
            read -p "Please enter your end date (YYYY-MM-DD): " end_date
            ;;
        *)
            echo "Invalid option. Exiting."
            exit 1
            ;;
    esac

    echo "Start Date: $start_date"
    echo "End Date: $end_date"

    read -p "Enter the search keyword (username/database): " search_keyword

    # Logic to display MySQL logs including the search keyword within specified date range
    # Replace the path below with the actual path to MySQL logs
    grep -E "^($start_date|$end_date).*${search_keyword}" /var/log/mysql/error.log

    read -p "Press Enter to return to the MySQL Logs Menu"
    mysql_logs
}


#//////////////////////////////#
# Function to check if a port is closed and open it if necessary
check_and_open_port() {
    local port="$1"

    echo "Checking if port $port is closed..."
    nc -zv localhost "$port" &>/dev/null

    if [ $? -eq 0 ]; then
        echo "Port $port is already open."
    else
        echo "Port $port is closed. Opening it..."
        if [ "$OS" == "centos" ]; then
            iptables -A INPUT -p tcp --dport "$port" -j ACCEPT
        elif [ "$OS" == "ubuntu" ]; then
            ufw allow "$port"
        fi
    fi
}

# Function to check if an IP address is blocked and delist it if necessary
check_and_delist_ip() {
    local ip="$1"

    echo "Checking if IP $ip is blocked..."
    if [ "$OS" == "centos" ]; then
        blocked=$(iptables -nL | grep "$ip")
    elif [ "$OS" == "ubuntu" ]; then
        blocked=$(ufw status | grep "$ip")
    fi

    if [ -z "$blocked" ]; then
        echo "IP $ip is not blocked."
    else
        echo "IP $ip is blocked. Delisting it..."
        if [ "$OS" == "centos" ]; then
            iptables -D INPUT -s "$ip" -j DROP
        elif [ "$OS" == "ubuntu" ]; then
            ufw delete deny from "$ip"
        fi
    fi
}

# Function to display processes listening on a specific port using lsof
display_processes_listening_on_port() {
    local port="$1"

    echo "Displaying processes listening on port $port using lsof:"
    lsof -i :"$port"
}

# Function to display all listening ports using lsof
display_all_listening_ports() {
    echo "Displaying all listening ports using lsof:"
    lsof -i -P -n | grep LISTEN
}

# Function to display running processes
display_processes() {
    echo "### RUNNING PROCESSES ###"
    ps aux
}

# Function to display top CPU processes
display_top_processes() {
    echo "### TOP CPU PROCESSES ###"
    top -b -n 1 | head -n 20
}

# Network Menu Function
function network_menu() {
    clear
    echo "=== Network Menu ==="
    echo "1. Check and Open Port"
    echo "2. Check and Delist IP"
    echo "3. Display Processes Listening on Port"
    echo "4. Display All Listening Ports"
    echo "5. Display Running Processes"
    echo "6. Display Top CPU Processes"
    echo "7. Back to Main Menu"
    read -p "Select an option (1-7): " network_option

    case $network_option in
        1) check_and_open_port_menu ;;
        2) check_and_delist_ip_menu ;;
        3) display_processes_listening_on_port_menu ;;
        4) display_all_listening_ports ;;
        5) display_processes ;;
        6) display_top_processes ;;
        7) main_menu ;;
        *) echo "Invalid option. Please choose a valid option." ;;
    esac

    read -p "Press Enter to return to the Main Menu"
    main_menu
}

# Function to search for files by various criteria
search_files() {
    echo "Enter the search path: "
    read path
    echo "Enter the filename or pattern to search: "
    read pattern
    echo "### SEARCH RESULTS FOR $pattern IN $path ###"
    sudo find "$path" -name "$pattern"
}

# Function to change owner of a file or directory
change_owner() {
    echo "Enter the file/directory name: "
    read file
    echo "Enter the new owner: "
    read owner
    sudo chown "$owner" "$file"
}

# Function to change permissions of a file or directory
change_permissions() {
    echo "Enter the file/directory name: "
    read file
    echo "Enter the new permissions (in octal): "
    read permissions
    sudo chmod "$permissions" "$file"
}

# File System Search Menu Function
function file_system_search_menu() {
    clear
    echo "=== File System Search Menu ==="
    echo "1. Search for Files"
    echo "2. Change Owner of a File/Directory"
    echo "3. Change Permissions of a File/Directory"
    echo "4. Back to Main Menu"
    read -p "Select an option (1-4): " fs_search_option

    case $fs_search_option in
        1) search_files ;;
        2) change_owner ;;
        3) change_permissions ;;
        4) main_menu ;;
        *) echo "Invalid option. Please choose a valid option." ;;
    esac

    read -p "Press Enter to return to the Main Menu"
    main_menu
}

# Start the script by calling the main menu function
main_menu