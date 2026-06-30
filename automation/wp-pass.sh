#!/bin/bash

# Ensure running as root
if [[ $EUID -ne 0 ]]; then
   echo "This script must be run as root." 
   exit 1
fi

# 1. Acquire Domain name
read -p "Enter the Domain name: " TARGET_DOMAIN

# 2. Fetch the document root from cPanel userdata
DOCROOT=$(grep "^$TARGET_DOMAIN:" /etc/userdatadomains | cut -d: -f2 | awk -F'==' '{print $5}' | xargs)

if [ -z "$DOCROOT" ]; then
    echo "Error: Could not find domain '$TARGET_DOMAIN' in /etc/userdatadomains."
    exit 1
fi

echo "Found document root: $DOCROOT"

# 3. List available users directly from MySQL (Bypassing WordPress PHP)
echo "--- Fetching user list directly from database ---"
DB_NAME=$(grep "DB_NAME" "$DOCROOT/wp-config.php" | cut -d"'" -f4)
DB_USER=$(grep "DB_USER" "$DOCROOT/wp-config.php" | cut -d"'" -f4)
DB_PASS=$(grep "DB_PASSWORD" "$DOCROOT/wp-config.php" | cut -d"'" -f4)
DB_HOST=$(grep "DB_HOST" "$DOCROOT/wp-config.php" | cut -d"'" -f4)
PREFIX=$(grep "\$table_prefix" "$DOCROOT/wp-config.php" | cut -d"'" -f2)

mysql -u "$DB_USER" -p"$DB_PASS" -h "$DB_HOST" "$DB_NAME" -e "SELECT user_login, display_name, user_email FROM ${PREFIX}users;" 2>/dev/null
echo "---------------------------------------------"

# 4. Acquire WordPress Username
read -p "Enter the WordPress username to reset: " WP_USER

# 5. Generate a random password
NEW_PASS=$(openssl rand -base64 12)

# 6. Update the WordPress user
# We continue to use wp-cli for the update as it is safer for database integrity
wp user update "$WP_USER" --user_pass="$NEW_PASS" --path="$DOCROOT" --allow-root --skip-plugins --skip-themes --skip-packages

if [ $? -eq 0 ]; then
    echo "===================================================="
    echo "SUCCESS: Password updated for user '$WP_USER'"
    echo "New Password: $NEW_PASS"
    echo "===================================================="
else
    echo "ERROR: Failed to update password. Please verify the username exists."
fi
