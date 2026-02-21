#!/bin/bash
# Author: Nihar
# Description: Firewall port configuration utility for CentOS and Ubuntu.

if [ -f /etc/redhat-release ]; then
  OS=centos
elif [ -f /etc/lsb-release ]; then
  OS=ubuntu
else
  echo "Unsupported OS."
  exit 1
fi

echo "Enter the port number to open:"
read port

if [ "$OS" == "centos" ]; then
  iptables -A INPUT -p tcp --dport "$port" -j ACCEPT
  service iptables save
  service iptables restart
elif [ "$OS" == "ubuntu" ]; then
  ufw allow "$port"
fi

echo "Port $port opened successfully."
