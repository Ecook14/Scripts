#!/bin/bash

echo "Hello, what is your name?"
read name

echo "Please enter the Google Authentication code associated with $name."
read -s code

if [[ $code == 1 ]]; then

    echo "Number of emails in queue:"
    exim -bpc

    echo "Checking for failed login attempts:"
    egrep -o 'dovecot_login[^ ]+' /var/log/exim_mainlog | sort | uniq -c | sort -nk 1

    echo "All emails:"
    exim -bpr | grep "<" | awk '{print $4}' | cut -d"<" -f2 | cut -d">" -f1 | sort -n | uniq -c | sort -n

    echo "Do you want to search in the archive log? (y/n)"
    read answer

    if [[ $answer == "y" ]]; then
        echo "Enter email address to search:"
        read email
        echo "Searching in archive log..."
        zgrep $email /var/log/exim_mainlog-*.gz
        
        echo "Enter receiver email:"
        read rmail
        echo "Checking delivery logs:"
        zgrep $rmail /var/log/exim_mainlog-*.gz
        
        echo "Enter Exim ID:"
        read eximid
        echo "Checking Exim ID in logs:"
        zgrep $eximid /var/log/exim_mainlog-*.gz
    else
        echo "Enter sender email:"
        read smail
        echo "Checking affected emails in logs:"
        grep $smail /var/log/exim_mainlog

        echo "Enter receiver email:"
        read rmail
        echo "Checking delivery logs:"
        grep $rmail /var/log/exim_mainlog

        echo "Enter Exim ID:"
        read eximid
        echo "Checking Exim ID in logs:"
        grep $eximid /var/log/exim_mainlog
    fi

else
    echo "Incorrect code entered. Please come back later. Goodbye $name."
fi
