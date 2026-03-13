#!/bin/bash

# Check if a username was provided
if [ -z "$1" ]; then
    echo "Usage: $0 <cpanel_username>"
    exit 1
fi

USER=$1
BLOCK_FILE="/etc/blockeddomains"

echo "--- Re-enabling email for user: $USER ---"

# 1. Unsuspend outgoing email via WHM API
echo "Step 1: Unsuspending outgoing email..."
whmapi1 unsuspend_outgoing_email user=$USER

# 2. Remove user domains from the custom blocklist
echo "Step 2: Removing domains from $BLOCK_FILE..."
if [ -f "$BLOCK_FILE" ]; then
    # Get all domains associated with the user
    DOMAINS=$(grep ": $USER$" /etc/userdomains | cut -d: -f1)
    
    for DOMAIN in $DOMAINS; do
        # Use sed to delete lines matching the exact domain
        sed -i "/^$DOMAIN$/d" "$BLOCK_FILE"
        echo "   Removed: $DOMAIN"
    done
fi

# 3. Rebuild and Restart Exim to apply changes
echo "Step 3: Rebuilding Exim config and restarting..."
/scripts/buildeximconf
/scripts/restartsrv_exim

echo "--- Done! Email functionality restored for $USER ---"
