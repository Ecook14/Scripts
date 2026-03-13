#!/bin/bash

# Check if a username was provided
if [ -z "$1" ]; then
    echo "Usage: $0 <cpanel_username>"
    exit 1
fi

USER=$1
BLOCK_FILE="/etc/blockeddomains"

echo "--- Processing user: $USER ---"

# 1. Suspend outgoing email via WHM API
echo "Step 1: Suspending outgoing email..."
whmapi1 suspend_outgoing_email user=$USER

# 2. Get all domains for the user and add to blocklist
echo "Step 2: Adding domains to $BLOCK_FILE..."
touch $BLOCK_FILE
# Extracts domains from the cPanel user-to-domain mapping file
DOMAINS=$(grep ": $USER$" /etc/userdomains | cut -d: -f1)

for DOMAIN in $DOMAINS; do
    if ! grep -q "^$DOMAIN$" $BLOCK_FILE; then
        echo "$DOMAIN" >> $BLOCK_FILE
        echo "   Added: $DOMAIN"
    fi
done

# 3. Configure Exim (One-time setup for the blocklist logic)
echo "Step 3: Checking Exim configuration..."
LOCAL_CONF="/etc/exim.conf.local"
touch $LOCAL_CONF

# Add the domainlist definition if it doesn't exist
if ! grep -q "blocked_domains" $LOCAL_CONF; then
    echo "Adding domainlist definition to $LOCAL_CONF"
    echo "domainlist blocked_domains = lsearch;$BLOCK_FILE" >> $LOCAL_CONF
    
    # Add the rejection router
    echo "Adding rejection router..."
    echo "@ROUTERSTART@" >> $LOCAL_CONF
    echo "reject_blocked_domains:" >> $LOCAL_CONF
    echo "  driver = redirect" >> $LOCAL_CONF
    echo "  domains = +blocked_domains" >> $LOCAL_CONF
    echo "  allow_fail" >> $LOCAL_CONF
    echo "  data = :fail: Delivery to this domain is currently disabled." >> $LOCAL_CONF
fi

# 4. Rebuild and Restart Exim
echo "Step 4: Rebuilding Exim config and restarting..."
/scripts/buildeximconf
/scripts/restartsrv_exim

echo "--- Done! Email is now disabled for $USER ---"
