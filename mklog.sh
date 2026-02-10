#!/bin/bash

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
        
        # Recreate log files with touch command
        sudo touch /var/log/apache2 /var/log/boot.log /var/log/btmp /var/log/chkservd.log \
        /var/log/cloud-init.log /var/log/cron /var/log/dcpumon /var/log/dmesg /var/log/exim_mainlog \
        /var/log/exim_paniclog /var/log/exim_rejectlog /var/log/firewalld /var/log/grubby /var/log/maillog \
        /var/log/messages /var/log/mysqld.log /var/log/named /var/log/ppp /var/log/secure /var/log/tuned \
        /var/log/wp-toolkit /var/log/wtmp /var/log/xferlog.offsetftpsep /var/log/yum.log

        # Set permissions and ownership for the log files
        sudo chown root:root /var/log/apache2 /var/log/boot.log /var/log/btmp /var/log/chkservd.log \
        /var/log/cloud-init.log /var/log/cron /var/log/dcpumon /var/log/dmesg /var/log/exim_mainlog \
        /var/log/exim_paniclog /var/log/exim_rejectlog /var/log/firewalld /var/log/grubby /var/log/maillog \
        /var/log/messages /var/log/mysqld.log /var/log/named /var/log/ppp /var/log/secure /var/log/tuned \
        /var/log/wp-toolkit /var/log/wtmp /var/log/xferlog.offsetftpsep /var/log/yum.log

        sudo chmod 644 /var/log/apache2 /var/log/boot.log /var/log/btmp /var/log/chkservd.log \
        /var/log/cloud-init.log /var/log/cron /var/log/dcpumon /var/log/dmesg /var/log/exim_mainlog \
        /var/log/exim_paniclog /var/log/exim_rejectlog /var/log/firewalld /var/log/grubby /var/log/maillog \
        /var/log/messages /var/log/mysqld.log /var/log/named /var/log/ppp /var/log/secure /var/log/tuned \
        /var/log/wp-toolkit /var/log/wtmp /var/log/xferlog.offsetftpsep /var/log/yum.log

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
