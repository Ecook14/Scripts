#!/bin/bash
# Author: Nihar
# Description: Comprehensive system maintenance and troubleshooting menu.

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

        if [ "$choice" == "4" ]; then
            break
        fi
    done
}

function log_menu() {
    while true; do
        clear
        echo "=== Log Menu ==="
        echo "1. Apache/HTTP Logs"
        echo "2. Cpanel Access Log"
        echo "3. Exim/Mail Logs"
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
            7) return ;;
            *) echo "Invalid option." ;;
        esac
    done
}

function apache_log() {
    clear
    echo "=== Apache Log ==="
    echo "Enter the domain name:" 
    read domain
    if [ -z "$domain" ]; then
        echo "Domain name cannot be empty."
        return 1
    fi
    tail -n 10 /var/log/apache2/access.log | grep "$domain"
    read -p "Press Enter to return..."
}

function access_log() {
    clear
    echo "=== Access Log ==="
    echo "Enter the Cpanel username:"
    read cpanelusername
    tail -n 10 /usr/local/cpanel/logs/access_log | grep "$cpanelusername"
    read -p "Press Enter to return..."
}

function exim_logs() {
    clear
    echo "=== Exim Logs ==="
    echo "1. Tail Exim Log"
    echo "2. View Queue Size"
    echo "3. Dovecot Login Counts"
    echo "4. Sender Domains"
    read -p "Select an option: " exim_opt
    case $exim_opt in
        1)
            read -p "Enter the domain or email: " domain_email
            tail -n 10 /var/log/exim_mainlog | grep "$domain_email"
            ;;
        2) exim -bpc ;;
        3) egrep -o 'dovecot_login[^ ]+' /var/log/exim_mainlog | sort | uniq -c | sort -nk 1 ;;
        4) exim -bpr | grep "<" | awk {'print $4'} | cut -d"<" -f2 | cut -d">" -f1 | sort | uniq -c | sort -n ;;
    esac
    read -p "Press Enter to return..."
}

function system_logs() {
    clear
    echo "=== System Logs ==="
    read -p "Enter the search keyword: " search_keyword
    grep "$search_keyword" /var/log/messages | tail -n 20
    read -p "Press Enter to return..."
}

function ftp_logs() {
    clear
    read -p "Please enter the FTP Username: " ftp_username
    grep "$ftp_username" /var/log/vsftpd.log | tail -n 20
    read -p "Press Enter to return..."
}

function mysql_logs() {
    clear
    read -p "Please enter the MySQL Database/Username: " mysql_database
    grep "$mysql_database" /var/log/mysql/error.log | tail -n 20
    read -p "Press Enter to return..."
}

function network_menu() {
    while true; do
        clear
        echo "=== Network Menu ==="
        echo "1. Check and Open Port"
        echo "2. Check and Delist IP"
        echo "3. Display All Listening Ports"
        echo "4. Display Top CPU Processes"
        echo "5. Back"
        read -p "Select an option (1-5): " net_opt
        case $net_opt in
            1)
                read -p "Port: " port
                nc -zv localhost "$port" &>/dev/null && echo "Port $port is open" || echo "Port $port is closed"
                ;;
            2)
                read -p "IP: " ip
                iptables -nL | grep "$ip" && echo "IP $ip is blocked" || echo "IP $ip is not blocked"
                ;;
            3) lsof -i -P -n | grep LISTEN ;;
            4) top -b -n 1 | head -n 20 ;;
            5) return ;;
        esac
        read -p "Press Enter to continue..."
    done
}

function file_system_search_menu() {
    while true; do
        clear
        echo "=== File System Search Menu ==="
        echo "1. Search for Files"
        echo "2. Change Owner"
        echo "3. Change Permissions"
        echo "4. Back"
        read -p "Select an option: " fs_opt
        case $fs_opt in
            1)
                read -p "Enter the search path: " path
                read -p "Enter the filename pattern: " pattern
                sudo find "$path" -name "$pattern" | head -n 20
                ;;
            2)
                read -p "Enter the file/directory: " file
                read -p "Enter the new owner: " owner
                sudo chown "$owner" "$file"
                ;;
            3)
                read -p "Enter the file/directory: " file
                read -p "Enter the new permissions: " permissions
                sudo chmod "$permissions" "$file"
                ;;
            4) return ;;
        esac
        read -p "Press Enter to continue..."
    done
}

main_menu
