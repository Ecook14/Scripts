#!/bin/bash

if [[ $EUID -ne 0 ]]; then
   echo "This script must be run as root." 
   exit 1
fi

read -p "Enter the Domain name: " TARGET_DOMAIN
DOCROOT=$(grep "^$TARGET_DOMAIN:" /etc/userdatadomains | cut -d: -f2 | awk -F'==' '{print $5}' | xargs)

if [ -z "$DOCROOT" ]; then
    echo "Error: Domain not found."
    exit 1
fi

# 1. Fetch DB Credentials
DB_NAME=$(grep "DB_NAME" "$DOCROOT/wp-config.php" | cut -d"'" -f4)
DB_USER=$(grep "DB_USER" "$DOCROOT/wp-config.php" | cut -d"'" -f4)
DB_PASS=$(grep "DB_PASSWORD" "$DOCROOT/wp-config.php" | cut -d"'" -f4)
DB_HOST=$(grep "DB_HOST" "$DOCROOT/wp-config.php" | cut -d"'" -f4)
PREFIX=$(grep "\$table_prefix" "$DOCROOT/wp-config.php" | cut -d"'" -f2)

# 2. List Users
echo "--- Current Users ---"
mysql -u "$DB_USER" -p"$DB_PASS" -h "$DB_HOST" "$DB_NAME" -e "SELECT user_login, user_email FROM ${PREFIX}users;" 2>/dev/null

read -p "Enter the WordPress username to reset: " WP_USER
NEW_PASS=$(openssl rand -base64 12)

# 3. Direct Database Update
# We use MD5() which WordPress accepts and upgrades upon next login
mysql -u "$DB_USER" -p"$DB_PASS" -h "$DB_HOST" "$DB_NAME" -e "UPDATE ${PREFIX}users SET user_pass = MD5('$NEW_PASS') WHERE user_login = '$WP_USER';"

if [ $? -eq 0 ]; then
    echo "===================================================="
    echo "SUCCESS: Password updated for user '$WP_USER'"
    echo "New Password: $NEW_PASS"
    echo "===================================================="
else
    echo "ERROR: Failed to update database."
fi
