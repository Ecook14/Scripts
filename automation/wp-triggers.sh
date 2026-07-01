#!/bin/bash

# Ensure running as root
if [[ $EUID -ne 0 ]]; then
   echo "This script must be run as root." 
   exit 1
fi

# 1. Domain Discovery
read -p "Enter the Domain name: " TARGET_DOMAIN
DOCROOT=$(grep "^$TARGET_DOMAIN:" /etc/userdatadomains | cut -d: -f2 | awk -F'==' '{print $5}' | xargs)

if [ -z "$DOCROOT" ] || [ ! -d "$DOCROOT" ]; then
    echo "Error: Could not determine valid document root for $TARGET_DOMAIN."
    exit 1
fi

WP_CONFIG="$DOCROOT/wp-config.php"

if [ ! -f "$WP_CONFIG" ]; then
    echo "Error: wp-config.php not found at $WP_CONFIG"
    exit 1
fi

echo "--- Processing WordPress Site: $TARGET_DOMAIN ---"
echo "Path: $WP_CONFIG"

# 2. Extract DB Credentials
db_name=$(grep "define.*'DB_NAME'" "$WP_CONFIG" | cut -d\' -f4)
db_user=$(grep "define.*'DB_USER'" "$WP_CONFIG" | cut -d\' -f4)
db_pass=$(grep "define.*'DB_PASSWORD'" "$WP_CONFIG" | cut -d\' -f4)
db_host=$(grep "define.*'DB_HOST'" "$WP_CONFIG" | cut -d\' -f4)
table_prefix=$(grep "\$table_prefix" "$WP_CONFIG" | cut -d\' -f2)

if [[ -z "$db_name" ]]; then
    echo "Error: Could not extract database credentials."
    exit 1
fi

# 3. List and Remove Triggers
echo "--- Checking for Triggers in $db_name ---"

# Fetch triggers (returns only names)
triggers=$(mysql -u "$db_user" -p"$db_pass" -h "$db_host" -D "$db_name" -N -s -e "SHOW TRIGGERS;" 2>/dev/null | awk '{print $1}')

if [ -z "$triggers" ]; then
    echo "No triggers found."
else
    echo "Triggers identified:"
    echo "$triggers"
    
    read -p "Do you want to remove ALL these triggers? (y/N): " confirm
    if [[ "$confirm" =~ ^[Yy]$ ]]; then
        for trigger_name in $triggers; do
            echo "Dropping trigger: $trigger_name..."
            mysql -u "$db_user" -p"$db_pass" -h "$db_host" -D "$db_name" -e "DROP TRIGGER IF EXISTS $trigger_name;"
        done
        echo "Cleanup complete."
    else
        echo "Operation aborted."
    fi
fi
