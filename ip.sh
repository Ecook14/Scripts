#!/bin/bash

# Define authentication credentials
passw="1"

# Ask the user to enter their username
read -p "Enter your username: " username

# Ask the user to enter their password without displaying it on the screen
read -s -p "Enter your password: " pass
echo

# Check if the entered credentials match the valid ones
if [[ "$pass" == "$passw" ]]; then
    # Valid authentication
    echo "Authentication successful."
    
    # List all deny, reject, blacklisted, blocked, and dropped IPs
    echo "Listing all deny, reject, blacklisted, blocked, and dropped IPs:"
    iptables -L INPUT -v -n | grep -E '(REJECT|DROP|blacklist)' | awk '{print $8}' | sort -u

    # Prompt the user to input the IP to whitelist
    read -p "Enter the IP to whitelist: " ip_to_whitelist

    # Whitelist the specified IP
    iptables -D INPUT -s $ip_to_whitelist -j DROP
    iptables -D INPUT -s $ip_to_whitelist -j REJECT
    # Add your whitelist rule here (e.g., ACCEPT)
    iptables -A INPUT -s $ip_to_whitelist -j ACCEPT

    echo "IP $ip_to_whitelist has been whitelisted and removed from relevant rules."

else
    # Invalid authentication
    echo "Authentication failed. Access denied."
fi