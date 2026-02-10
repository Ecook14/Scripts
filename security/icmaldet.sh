#!/bin/bash

function run_maldet_scan() {
    echo "Please enter the email address to send the report to:"
    read email

    echo "Enter the location to start the scan with (e.g. /home/user):"
    read loc

    if ! command -v screen &> /dev/null; then
        echo "screen not found. Installing..."
        if command -v apt &> /dev/null; then
            sudo apt install -y screen
        elif command -v yum &> /dev/null; then
            sudo yum install -y screen
        else
            echo "Unable to install screen. Please install it manually and run the script again."
            exit 1
        fi
    fi
    cd /usr/local/src/ || exit 1
    wget http://www.rfxn.com/downloads/maldetect-current.tar.gz
    tar -xzf maldetect-current.tar.gz

    # Use a more specific pattern to match the extracted folder
    cd "$(ls -d maldetect-* | head -n 1)" || exit 1
    sh install.sh

    # Update maldet configuration for email alerts
    sed -i 's/email_alert="0"/email_alert="1"/' /usr/local/maldetect/conf.maldet
    sed -i "s/email_addr=\"you@domain.com\"/email_addr=\"$email\"/" /usr/local/maldetect/conf.maldet

    # Start maldet scan in a screen session
    screen -dmS maldet_scan

    screen_commands=(
        "maldet -d && maldet -u"
        "maldet -b -r \"$loc\""
        "session=\$(cat /usr/local/maldetect/sess/session.last)"
        "maldet -e \"\$session\""
        "echo \"Scan complete. Report sent to $email\""
    )

    for cmd in "${screen_commands[@]}"; do
        screen -S maldet_scan -X stuff "$cmd"$'\n'
    done

    echo "Scan initiated. Check your email for the report later."
}

run_maldet_scan