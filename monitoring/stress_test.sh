#!/bin/bash
# Author: Nihar
# Description: URL-based stress testing and load generation tool.

# Set the number of times to iterate over the file URLs
num_iterations=10

# Iterate over the file URLs the specified number of times
for i in $(seq 1 $num_iterations); do
    # Iterate over the file URLs (Placeholder for your list of URLs)
    for url in $wp_file_urls; do
        user_agent=$(shuf -n 1 user_agents.txt 2>/dev/null || echo "Mozilla/5.0")
        ip_address=$(shuf -n 1 ip_addresses.txt 2>/dev/null || echo "127.0.0.1")

        headers="User-Agent: $user_agent\nX-Forwarded-For: $ip_address"

        echo "Stress testing URL: $url"
        hping3 -c 1 -S -p 80 --data "$headers" "$url" 2>/dev/null

        if [ $? -eq 0 ]; then
            hping3 -c 1 -S -p 80 --data "$headers" "$url" > "$(echo $url | rev | cut -d'/' -f 1 | rev)" 2>/dev/null
        else
            echo "Error requesting file at URL $url"
        fi
    done
    sleep 1
done
