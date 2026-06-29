#!/bin/bash

# Usage: ./findfwd.sh [-u username]
TARGET_USER=""

while getopts "u:" opt; do
  case $opt in
    u) TARGET_USER="$OPTARG" ;;
    *) echo "Usage: $0 [-u username]"; exit 1 ;;
  esac
done

if [ -n "$TARGET_USER" ]; then
    USERS="$TARGET_USER"
else
    USERS=$(/bin/ls -1 /var/cpanel/users)
fi

echo "--- Server Forwarding Report ---"

for USER in $USERS; do
    if [ -f "/var/cpanel/users/$USER" ]; then
        # Use awk to clean %40, map dest->forward, and pipe through 'sort -u' for unique results
        uapi --user=${USER} Email list_forwarders 2>/dev/null | awk '
            /dest:/    { gsub(/%40/, "@", $2); dest=$2 }
            /forward:/ { 
                gsub(/%40/, "@", $2); 
                print dest " -> " $2 
            }
        ' | sort -u
    fi
done
