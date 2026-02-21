#!/bin/bash
# Author: Nihar
# Description: Corrects directory and file permissions for user home directories.

echo "Hello, what is your email?"
read email

echo "Home name example home1, home2?"
read hom
echo "User name?"
read user
echo "Fixing Directory permissions"
find /$hom/$user/public_html -type d -exec chmod 755 {} ";"
echo "Directory Permission fixed"
echo "Fixing Files permission"
find /$hom/$user/public_html -type f -exec chmod 644 {} ";"
echo "Files permission fixed"