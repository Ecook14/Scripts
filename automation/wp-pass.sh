#!/bin/bash

# Ensure running as root
if [[ $EUID -ne 0 ]]; then
   echo "This script must be run as root." 
   exit 1
fi

# 1. Acquire Domain name
read -p "Enter the Domain name: " TARGET_DOMAIN

# 2. Fetch the document root from cPanel userdata
# xargs is used to trim whitespace
DOCROOT=$(grep "^$TARGET_DOMAIN:" /etc/userdatadomains | cut -d: -f2 | awk -F'==' '{print $5}' | xargs)

if [ -z "$DOCROOT" ]; then
    echo "Error: Could not find domain '$TARGET_DOMAIN' in /etc/userdatadomains."
    exit 1
fi

echo "Found document root: $DOCROOT"

# 3. List available users for verification
echo "--- Fetching user list for $TARGET_DOMAIN ---"
wp user list --path="$DOCROOT" --allow-root --skip-plugins --format=table --fields=user_login,display_name,user_email
echo "---------------------------------------------"

# 4. Acquire WordPress Username
read -p "Enter the WordPress username to reset: " WP_USER

# 5. Generate a random password
NEW_PASS=$(openssl rand -base64 12)

# 6. Update the WordPress user
# --skip-plugins and --skip-themes prevent interference from faulty code
wp user update "$WP_USER" --user_pass="$NEW_PASS" --path="$DOCROOT" --allow-root --skip-plugins --skip-themes

if [ $? -eq 0 ]; then
    echo "===================================================="
    echo "SUCCESS: Password updated for user '$WP_USER'"
    echo "New Password: $NEW_PASS"
    echo "===================================================="
else
    echo "ERROR: Failed to update password. Please verify the username exists."
fi
