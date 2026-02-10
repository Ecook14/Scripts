#! /bin/sh
echo Hello, Email?
read email
echo Please Enter the Google Authentication code associated with Aronstone.
read code
if [[ $code == 1 ]]
then
  cd /usr/local/src/
  wget http://www.rfxn.com/downloads/maldetect-current.tar.gz
  tar -xzf maldetect-current.tar.gz
  cd maldetect-*
  sh ./install.sh
  maldet -d && maldet -u
  maldet -b --scan-all
  maldet -b -r /home/
  maldet -e $(cat /usr/local/maldetect/sess/session.last) "$email"
else
  echo Enter the correct code. Come back later.
fi
