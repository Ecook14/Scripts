#!/bin/bash

# Usage: ./findfwd.sh [-u username] [-d domain]
TARGET_USER=""
TARGET_DOMAIN=""

while getopts "u:d:" opt; do
  case $opt in
    u) TARGET_USER="$OPTARG" ;;
    d) TARGET_DOMAIN="$OPTARG" ;;
    *) echo "Usage: $0 [-u username] [-d domain]"; exit 1 ;;
  esac
done

# Define the user list
if [ -n "$TARGET_USER" ]; then
    USERS="$TARGET_USER"
else
    USERS=$(/bin/ls -1 /var/cpanel/users)
fi

echo "--- Server Forwarding Report ---"

for USER in $USERS; do
    if [ -f "/var/cpanel/users/$USER" ]; then
        # Use --output=json for reliable parsing if available, 
        # but sticking to standard UAPI output, we adjust the awk filter:
        uapi --user=${USER} Email list_forwarders 2>/dev/null | awk -v target_d="$TARGET_DOMAIN" '
            /domain:/ { domain=$2 }
            /dest:/   { dest=$2 }
            /forward:/ { 
                fwd=$2; 
                if (target_d == "" || domain == target_d) {
                    print "User: " ENVIRON["USER"] " | Domain: " domain " | " fwd " -> " dest
                }
            }
        '
    fi
done
