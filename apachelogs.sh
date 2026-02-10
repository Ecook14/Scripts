#! /bin/sh
echo Hello, email?
read email
echo Please Enter the Google Authentication code associated with $email.
read -s code
if [[ $code == 1 ]]
then
  echo Domain?
  read domain
  grep $domain /usr/local/apache/logs/error_log
  tail /var/log/apache2/error.log
  tail -f $domain /var/log/apache2/error.log
  tail -f $domain /usr/local/apache/logs/error_log
else  
  echo Enter the correct code.Come back later. Byyyy....$email.
fi