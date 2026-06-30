#!/bin/bash

# Ensure running as root
if [[ $EUID -ne 0 ]]; then
   echo "This script must be run as root." 
   exit 1
fi

# 1. Acquire inputs from operator
read -p "Enter the Domain name: " TARGET_DOMAIN
read -p "Enter the WordPress username: " WP_USER

# 2. Fetch the document root from cPanel userdata
DOCROOT=$(grep "^$TARGET_DOMAIN:" /etc/userdatadomains | cut -d: -f2 | awk -F'==' '{print $5}' | xargs)

if [ -z "$DOCROOT" ]; then
    echo "Error: Could not find domain '$TARGET_DOMAIN' in /etc/userdatadomains."
    exit 1
fi

echo "Found document root: $DOCROOT"

# 3. Generate a random password
NEW_PASS=$(openssl rand -base64 12)

# 4. Update the WordPress user
# --skip-plugins and --skip-themes prevent errors if a broken plugin interferes with WP-CLI
wp user update "$WP_USER" --user_pass="$NEW_PASS" --path="$DOCROOT" --skip-plugins --skip-themes --allow-root

if [ $? -eq 0 ]; then
    echo "----------------------------------------------------"
    echo "Success! Password updated for user: $WP_USER"
    echo "New Password: $NEW_PASS"
    echo "----------------------------------------------------"
else
    echo "Error: Failed to update password. Ensure the username '$WP_USER' exists in this installation."
fi
