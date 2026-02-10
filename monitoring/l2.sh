#! /bin/sh

echo "Select which log to view:"
echo "1. Apache error log"
echo "2. Message log"
echo "3. FTP log"
echo "4. MySQL log"
echo "5. Outgoing logs"
echo "6. Incoming logs"
echo "7. Dovecot login log"
echo "8. Plesk mail log"

read -p "Enter your choice: " choice

case $choice in
  1) 
    echo "Enter Domain:"
    read domain
    echo "Apache error log for domain $domain:"
    if [ ! -f "/usr/local/apache/logs/error_log" ]; then
      echo "Error log file not found"
    else
      grep $domain /usr/local/apache/logs/error_log
      tail -f $domain /var/log/apache2/error.log
      tail -f $domain /usr/local/apache/logs/error_log
    fi
    ;;
  2) 
    echo "Enter search term:"
    read search_term
    echo "Message log with search term $search_term:"
    if [ ! -f "/var/log/messages" ]; then
      echo "Message log file not found"
    else
      grep -i $search_term /var/log/messages
    fi
    ;;
  3) 
    echo "Enter FTP user:"
    read ftp_user
    echo "FTP log for user $ftp_user:"
    if [ ! -f "/var/log/xferlog" ]; then
      echo "FTP log file not found"
    else
      grep $ftp_user /var/log/xferlog
    fi
    ;;
  4) 
    echo "Enter MySQL database name:"
    read mysql_db
    echo "MySQL log for database $mysql_db:"
    if [ ! -f "/var/log/mysqld.log" ]; then
      echo "MySQL log file not found"
    else
      grep $mysql_db /var/log/mysqld.log
    fi
    ;;
  5) 
    echo "Outgoing logs:"
    if [ ! -f "/var/log/exim_mainlog" ]; then
      echo "Outgoing log file not found"
    else
      tail -f /var/log/exim_mainlog | grep "<= "
    fi
    ;;
  6) 
    echo "Incoming logs:"
    if [ ! -f "/var/log/exim_mainlog" ]; then
      echo "Incoming log file not found"
    else
      tail -f /var/log/exim_mainlog | grep "=> "
    fi
    ;;
  7) 
    echo "Dovecot login log:"
    if [ ! -f "/var/log/dovecot-info.log" ]; then
      echo "Dovecot log file not found"
    else
      tail -f /var/log/dovecot-info.log | grep "dovecot_login"
    fi
    ;;
  8)
    echo "Plesk mail log:"
    if [ ! -f "/usr/local/psa/var/log/maillog" ]; then
      echo "Plesk mail log file not found"
    else
      mailq | grep -c "^[A-F0-9]"
      echo "Email with Highest Mailq"
      mailq | grep ^[A-F0-9] | cut -c 42-80 | sort | uniq -c | sort -n | tail
      grep 'email' /usr/local/psa/var/log/maillog | cut -d ' ' -f 6 | grep -f - /usr/local/psa/var/log/maillog
    fi
    ;;
  *) 
    echo "Invalid choice"
    ;;
esac
