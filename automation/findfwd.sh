#!/bin/bash

# Usage: ./script.sh [-u username]

TARGET_USER=""

while getopts "u:d:" opt; do
  case $opt in
    u) TARGET_USER="$OPTARG" ;;
    *) echo "Usage: $0 [-u username] [-d domain]"; exit 1 ;;
  esac
done

# Define the user list to iterate over
if [ -n "$TARGET_USER" ]; then
    USERS="$TARGET_USER"
else
    USERS=$(/bin/ls -1 /var/cpanel/users)
fi

echo "--- Server Forwarding Report ---"

for USER in $USERS; do
    # Verify the user file exists to prevent errors
    if [ -f "/var/cpanel/users/$USER" ]; then
        # Fetch forwarders
        # We output in format: User: Domain -> Destination
        uapi --user=${USER} Email list_forwarders 2>/dev/null | awk -v user="$USER"  '
            $1 == "domain:" {domain=$2}
            $1 == "dest:" {dest=$2}
            $1 == "forward:" {
                if (target_d == "" || domain == target_d) {
                    print user " [" domain "]: " $2 " -> " dest
                }
            }
        '
    fi
done
