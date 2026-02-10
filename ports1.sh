#!/bin/bash

# Check the OS and set variables accordingly
if [ -f /etc/redhat-release ]; then
  OS=centos
  SERVICE=iptables
elif [ -f /etc/lsb-release ]; then
  OS=ubuntu
  SERVICE=ufw
else
  echo "Unsupported OS."
  exit 1
fi

echo "Hello, what is your name?"
read name

echo "Please enter the Google Authentication code associated with $name."
read -s code

if [[ $code == 1 ]]; then

    echo "Enter the port number to open:"
    read port

    echo "Checking current $SERVICE status:"
    service $SERVICE status

    echo "Starting $SERVICE service:"
    service $SERVICE start

    echo "Checking for existing rule for port $port:"
    iptables -nL | grep "#port"

    echo "Checking for ongoing port 25:"
    iptables -nL | grep 25

    echo "Displaying all iptables rules:"
    iptables -nL

    echo "Allowing incoming traffic on port $port:"
    if [ "$OS" == "centos" ]; then
        iptables -A INPUT -p tcp --dport "$port" -j ACCEPT
    elif [ "$OS" == "ubuntu" ]; then
        ufw allow "$port"
    fi

    echo "Saving $SERVICE rules:"
    if [ "$OS" == "centos" ]; then
        service $SERVICE save
    elif [ "$OS" == "ubuntu" ]; then
        ufw reload
    fi

    echo "Adding a rule for port $port to iptables:"
    if [ "$OS" == "centos" ]; then
        iptables -I INPUT -p tcp -m state --state NEW -m tcp --dport "$port" -j ACCEPT
    fi

    echo "Displaying open ports using netstat:"
    netstat -ltnp | grep -w "$port"

    echo "Displaying processes listening on port $port using lsof:"
    lsof -i :"$port"

    echo "Displaying all listening ports using lsof:"
    lsof -i -P -n | grep LISTEN

    echo "Displaying processes using port $port using fuser:"
    fuser "$port"/tcp

    echo "Final checks:"

    echo "Open ports using netstat:"
    netstat -ltnp | grep -w ":$port"

    echo "$SERVICE rules:"
    if [ "$OS" == "centos" ]; then
        iptables -nL | grep "$port"
    elif [ "$OS" == "ubuntu" ]; then
        ufw status | grep "$port"
    fi

    echo "Listening ports using netstat:"
    netstat -antp | grep LISTEN | grep "$port"

else
    echo "Incorrect code entered. Please come back later. Goodbye $name."
fi