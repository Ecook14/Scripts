#!/bin/bash

echo "Hello, what is your name?"
read name

echo "Please enter the Google authentication code associated with $name:"
read -s code

if [ "$code" = "1" ]; then
    echo "Please enter the email address to send the report to:"
    read email
    
    echo "Enter the location to start the scan with (e.g. /home/user):"
    read loc
    
    # Download and install maldet
    cd /usr/local/src/
    wget http://www.rfxn.com/downloads/maldetect-current.tar.gz
    tar -xzf maldetect-current.tar.gz
    cd maldetect-*
    sh install.sh
    
    # Update and scan
    maldet -d && maldet -u
    maldet -b -r "$loc"
    
    # Email the report
    session=$(cat /usr/local/maldetect/sess/session.last)
    maldet -e "$session" "$email"
    
    echo "Scan complete. Report sent to $email"
else
    echo "Incorrect code entered. Please come back later. Goodbye, $name"
fi
