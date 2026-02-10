#!/bin/bash

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

    # Go back to main menu
    main_menu
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

    # Go back to main menu
    main_menu
}

# Function to display processes listening on a specific port using lsof
display_processes_listening_on_port() {
    local port="$1"

    echo "Displaying processes listening on port $port using lsof:"
    lsof -i :"$port"

    # Go back to main menu
    main_menu
}

# Function to display all listening ports using lsof
display_all_listening_ports() {
    echo "Displaying all listening ports using lsof:"
    lsof -i -P -n | grep LISTEN

    # Go back to main menu
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

    # Go back to main menu
    main_menu
}

# Function to change owner of a file or directory
change_owner() {
    echo "Enter the file/directory name: "
    read file
    echo "Enter the new owner: "
    read owner
    sudo chown "$owner" "$file"

    # Go back to main menu
    main_menu
}

# Function to change permissions of a file or directory
change_permissions() {
    echo "Enter the file/directory name: "
    read file
    echo "Enter the new permissions (in octal): "
    read permissions
    sudo chmod "$permissions" "$file"

    # Go back to main menu
    main_menu
}

# Function to display running processes
display_processes() {
    echo "### RUNNING PROCESSES ###"
    ps aux

    # Go back to main menu
    main_menu
}

# Function to display top CPU processes
display_top_processes() {
    echo "### TOP CPU PROCESSES ###"
    top -b -n 1 | head -n 20

    # Go back to main menu
    main_menu
}

# Function to view email-related logs
view_email_logs() {
    echo "Number of emails in queue:"
    exim -bpc

    echo "Checking for failed login attempts:"
    egrep -o 'dovecot_login[^ ]+' /var/log/exim_mainlog | sort | uniq -c | sort -nk 1

    echo "All emails:"
    exim -bpr | grep "<" | awk '{print $4}' | cut -d"<" -f2 | cut -d">" -f1 | sort -n | uniq -c | sort -n

    echo "Enter sender email:"
    read smail

    echo "Checking affected emails in logs:"
    grep "$smail" /var/log/exim_mainlog

    echo "Enter receiver email:"
    read rmail

    echo "Checking delivery logs:"
    less /var/log/exim_mainlog | grep "$rmail"

    echo "Enter Exim ID:"
    read eximid

    echo "Checking Exim ID in logs:"
    exigrep "$eximid" /var/log/exim_mainlog

    # Go back to main menu
    main_menu
}

# Function to view Apache error logs by domain
view_apache_logs() {
    echo "Hello, email?"
    read email
    echo "Please Enter the Google Authentication code associated with $email."
    read -s code
    if [[ $code == 1 ]]; then
        echo "Domain?"
        read domain
        grep "$domain" /usr/local/apache/logs/error_log
        tail /var/log/apache2/error.log
        tail -f "$domain" /var/log/apache2/error.log
        tail -f "$domain" /usr/local/apache/logs/error_log
    else  
        echo "Enter the correct code.Come back later. Bye....$email."
    fi

    # Go back to main menu
    main_menu
}

# Function to view various logs
view_logs() {
  echo "Select which log to view:"
  echo "1. Apache error log"
  echo "2. Message log"
  echo "3. FTP log"
  echo "4. MySQL log"
  echo "5. Outgoing logs"
  echo "6. Incoming logs"
  echo "7. Dovecot login log"

  read -p "Enter your choice: " choice

  case $choice in
    1) 
      echo "Enter Domain:"
      read domain
      echo "Apache error log for domain $domain:"
      grep "$domain" /usr/local/apache/logs/error_log
      tail -f "$domain" /var/log/apache2/error.log
      tail -f "$domain" /usr/local/apache/logs/error_log
      ;;
    2) 
      echo "Enter search term:"
      read search_term
      echo "Message log with search term $search_term:"
      grep -i "$search_term" /var/log/messages
      ;;
    3) 
      echo "Enter FTP user:"
      read ftp_user
      echo "FTP log for user $ftp_user:"
      grep "$ftp_user" /var/log/xferlog
      ;;
    4) 
      echo "Enter MySQL database name:"
      read mysql_db
      echo "MySQL log for database $mysql_db:"
      grep "$mysql_db" /var/log/mysqld.log
      ;;
    5) 
      echo "Enter date (format: YYYY-MM-DD):"
      read date
      echo "Enter start time (format: HH:MM:SS):"
      read start_time
      echo "Enter end time (format: HH:MM:SS):"
      read end_time
      echo "Outgoing logs between $date $start_time and $date $end_time:"
      tail -f /var/log/exim_mainlog | awk -v date="$date" -v start_time="$start_time" -v end_time="$end_time" '$0 > date " " start_time && $0 < date " " end_time && /<=/'
      ;;
    6) 
      echo "Enter date (format: YYYY-MM-DD):"
      read date
      echo "Enter start time (format: HH:MM:SS):"
      read start_time
      echo "Enter end time (format: HH:MM:SS):"
      read end_time
      echo "Incoming logs between $date $start_time and $date $end_time:"
      tail -f /var/log/exim_mainlog | awk -v date="$date" -v start_time="$start_time" -v end_time="$end_time" '$0 > date " " start_time && $0 < date " " end_time && /=>/'
      ;;
    7) 
      echo "Dovecot login log:"
      tail -f /var/log/dovecot-info.log | grep "dovecot_login"
      ;;
    *) 
      echo "Invalid choice"
      ;;
  esac

  # Go back to main menu
  main_menu
}

# Main menu function
main_menu() {
  echo "### MAIN MENU ###"
  echo "1. Check and Open Port"
  echo "2. Check and Delist IP"
  echo "3. Display Processes Listening on Port"
  echo "4. Display All Listening Ports"
  echo "5. Search Files"
  echo "6. Change Owner of File/Directory"
  echo "7. Change Permissions of File/Directory"
  echo "8. Display Running Processes"
  echo "9. Display Top CPU Processes"
  echo "10. View Email Logs"
  echo "11. View Apache Logs"
  echo "12. View Logs"
  echo "13. Exit"
  echo "Enter your choice: "
  read choice

  case $choice in
      1) 
          echo "Enter the port number to check:"
          read port

          check_and_open_port "$port"
          ;;
      2)
          echo "Enter the IP address to check and delist if blocked:"
          read ip

          check_and_delist_ip "$ip"
          ;;
      3)
          echo "Enter the port number to display processes listening on it:"
          read port

          display_processes_listening_on_port "$port"
          ;;
      4)
          display_all_listening_ports
          ;;
      5)
          search_files
          ;;
      6)
          change_owner
          ;;
      7)
          change_permissions
          ;;
      8)
          display_processes
          ;;
      9)
          display_top_processes
          ;;
      10)
          view_email_logs
          ;;
      11)
          view_apache_logs
          ;;
      12)
          view_logs
          ;;
      13)
          echo "Exiting..."
          exit 0
          ;;
      *)
          echo "Invalid choice."
          ;;
  esac
}

# Check the OS and set variables accordingly
if [ -f /etc/redhat-release ]; then
  OS=centos
  SERVICE=iptables
elif [ -f /etc/lsb-release ]; then
  OS=ubuntu
  SERVICE=ufw
else
  echo "Unsupported OS."
  exit 1
fi

# Start the main menu
main_menu
