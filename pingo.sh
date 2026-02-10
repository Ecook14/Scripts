#!/bin/bash

# Set the number of times to iterate over the file URLs
num_iterations=10

# Iterate over the file URLs the specified number of times
for i in `seq 1 $num_iterations`; do
    # Iterate over the file URLs
    for url in wp_file_urls; do
        # Select a random user agent and IP address
        user_agent=`shuf -n 1 user_agents.txt`
        ip_address=`shuf -n 1 ip_addresses.txt`

        # Set the request headers
        headers="User-Agent: $user_agent\nX-Forwarded-For: $ip_address"

        # Send an HTTP GET request to the server to retrieve the file, using the selected user agent and IP address
        hping3 -c 1 -S -p 80 --data "$headers" $url

        # Check the status code of the response
        if [ $? -eq 0 ]; then
            # The request was successful, so save the contents of the file to a local file
            hping3 -c 1 -S -p 80 --data "$headers" $url > `echo $url | rev | cut -d'/' -f 1 | rev`
        else
            # The request was not successful, so print an error message
            echo "Error requesting file at URL $url"
    done

    # Pause for 1 second before making the next set of requests
    sleep 1
done