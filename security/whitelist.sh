#!/bin/bash
# Author: Nihar
# Description: Dynamic IP whitelisting for server firewalls.
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
