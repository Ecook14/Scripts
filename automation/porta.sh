#!/bin/bash

# Function to check if a port is closed and open it if necessary
check_and_open_port() {
    local port="$1"

    echo "Checking if port $port is closed..."
    nc -zv localhost "$port" &>/dev/null

    if [ $? -eq 0 ]; then
        echo "Port $port is already open."
    else
        echo "Port $port is closed. Opening it..."
        if [ "$OS" == "centos" ]; then
            iptables -A INPUT -p tcp --dport "$port" -j ACCEPT
        elif [ "$OS" == "ubuntu" ]; then
            ufw allow "$port"
        fi
    fi
}

# Function to check if an IP address is blocked and delist it if necessary
check_and_delist_ip() {
    local ip="$1"

    echo "Checking if IP $ip is blocked..."
    if [ "$OS" == "centos" ]; then
        blocked=$(iptables -nL | grep "$ip")
    elif [ "$OS" == "ubuntu" ]; then
        blocked=$(ufw status | grep "$ip")
    fi

    if [ -z "$blocked" ]; then
        echo "IP $ip is not blocked."
    else
        echo "IP $ip is blocked. Delisting it..."
        if [ "$OS" == "centos" ]; then
            iptables -D INPUT -s "$ip" -j DROP
        elif [ "$OS" == "ubuntu" ]; then
            ufw delete deny from "$ip"
        fi
    fi
}

# Function to display processes listening on a specific port using lsof
display_processes_listening_on_port() {
    local port="$1"

    echo "Displaying processes listening on port $port using lsof:"
    lsof -i :"$port"
}

# Function to display all listening ports using lsof
display_all_listening_ports() {
    echo "Displaying all listening ports using lsof:"
    lsof -i -P -n | grep LISTEN
}

# Main script

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

echo "Enter the port number to check:"
read port

check_and_open_port "$port"

display_processes_listening_on_port "$port"

display_all_listening_ports

echo "Enter the IP address to check and delist if blocked:"
read ip

check_and_delist_ip "$ip"
