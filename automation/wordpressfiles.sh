#!/bin/bash
# Author: Nihar
# Description: WordPress database management and configuration tool.

# Define authentication credentials
valid_password="1"
max_attempts=3
attempt=1

while [ $attempt -le $max_attempts ]; do
    # Ask the user to enter their username
    read -p "Enter your username: " username

    # Ask the user to enter their password without displaying it on the screen
    read -s -p "Enter your password: " password
    echo

    # Check if the entered credentials match the valid ones
    if [[ "$password" == "$valid_password" ]]; then
        echo "Authentication successful. Access granted."
        read -p "Enter Database user" dbuser
        read -p "Database name?" dbname
        read -p "SQL file with Location?" dbfile
	  read -p "Password" dbpass
       mySQL -u $dbuser -p $dbpass $dbname < $dbfile 
        exit 0
    else
        # Invalid authentication
        echo "Authentication failed. Access denied."
        ((attempt++))
        if [ $attempt -le $max_attempts ]; then
            echo "You have $((max_attempts - attempt + 1)) attempt(s) left."
        else
            echo "Maximum authentication attempts reached. Exiting."
            exit 1
        fi
    fi
done