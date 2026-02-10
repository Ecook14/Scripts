#!/bin/bash

function view_logs() {
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
      grep $domain /usr/local/apache/logs/error_log
      tail -f $domain /var/log/apache2/error.log
      tail -f $domain /usr/local/apache/logs/error_log
      ;;
    2) 
      echo "Enter search term:"
      read search_term
      echo "Message log with search term $search_term:"
      grep -i $search_term /var/log/messages
      ;;
    3) 
      echo "Enter FTP user:"
      read ftp_user
      echo "FTP log for user $ftp_user:"
      grep $ftp_user /var/log/xferlog
      ;;
    4) 
      echo "Enter MySQL database name:"
      read mysql_db
      echo "MySQL log for database $mysql_db:"
      grep $mysql_db /var/log/mysqld.log
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
}

echo "Hello, name?"
read name
echo "Please Enter the Google Authentication code associated with $name."
read -s code

if [[ $code == 1 ]]; then
  view_logs
else
  echo "Enter the correct code. Come back later. Bye....$name."
fi