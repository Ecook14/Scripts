#!/bin/bash
# Author: Nihar
# Description: MySQL database import utility.

read -p "Enter Database user: " dbuser
read -p "Database name: " dbname
read -p "SQL file with Location: " dbfile
read -p "Password: " dbpass
mysql -u "$dbuser" -p"$dbpass" "$dbname" < "$dbfile"
