#! /bin/sh

echo Hello, name?
read name
echo Please Enter the Google Authentication code associated with $name.
read -s code

if [[ $code == 1 ]]
then
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
      echo "Outgoing logs:"
      tail -f /var/log/exim_mainlog | grep "<= "
      ;;
    6) 
      echo "Incoming logs:"
      tail -f /var/log/exim_mainlog | grep "=> "
      ;;
    7) 
      echo "Dovecot login log:"
      tail -f /var/log/dovecot-info.log | grep "dovecot_login"
      ;;
    *) 
      echo "Invalid choice"
      ;;
  esac

else
  echo "Enter the correct code. Come back later. Byeee....$name"
fi
