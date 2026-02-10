#! /bin/sh
echo Hello, Email?
read email
echo Please Enter the Google Authentication code associated with Aronstone.
read -s code
if [[ $code == 1 ]]
then
 echo Fixing Directory...
 find . -type d -exec chmod 755 {} \;
 echo Fixing Files...
 find . -type f -exec chmod 644 {} \;
else
 echo Enter the correct code. Come back later.Byyyy....$email.
fi