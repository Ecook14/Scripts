#! /bin/sh
echo Hello, name?
read name
echo Please Enter the Google Authentication code associated with $name.
read -s code
if [[ $code == 1 ]]
then
  echo Reporting Email
  read email
  echo Enter Location to start scan with....
  read loc
  cd /usr/local/src/
  wget http://www.rfxn.com/downloads/maldetect-current.tar.gz
  tar -xzf maldetect-current.tar.gz
  cd maldetect-*
  sh ./install.sh
  maldet -d && maldet -u
  maldet -b -r $loc
  maldet -e $(cat /usr/local/maldetect/sess/session.last) "$email"
else
  echo Enter the correct code. Come back later. Byeeee... $name
fi
