#!/bin/bash

# Usage: ./findfwd.sh [-u username]
TARGET_USER=""

while getopts "u:" opt; do
  case $opt in
    u) TARGET_USER="$OPTARG" ;;
    *) echo "Usage: $0 [-u username]"; exit 1 ;;
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
        # Fetch and parse forwarders for the user
        uapi --user=${USER} Email list_forwarders 2>/dev/null | awk -v username="$USER" '
            /domain:/  { domain=$2 }
            /dest:/    { dest=$2 }
            /forward:/ { 
                print "User: " username " | Domain: " domain " | Forwarder: " $2 " -> Destination: " dest
            }
        '
    fi
done
