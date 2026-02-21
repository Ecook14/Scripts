#!/bin/bash
# Author: Nihar
# Description: Monthly server health, security, and integrity report.
#

IFCONFIG='/sbin/ifconfig'
NETSTAT='/bin/netstat'
CUT='/bin/cut'
AWK='/bin/awk'
GREP='/bin/grep'
EGREP='/bin/egrep'
ECHO='/bin/echo'

RECEIVER="managedserveralerts@hostgator.in"
DATE_STR=$(date +%Y%m%d)
LOG_FILE="/root/month_result_${DATE_STR}.txt"

{
    ${ECHO} "Subject: $HOSTNAME - Monthly server health report"
    echo -e "-------------------------------System Information----------------------------"
    echo -e "Hostname:\t\t$(hostname)"
    echo -e "Uptime:\t\t\t$(uptime | awk '{print $3,$4}' | sed 's/,//')"
    echo -e "Kernel:\t\t\t$(uname -r)"
    echo -e "Architecture:\t\t$(arch)"
    echo ""
    
    echo "-------------------------------WebServer Uptime-----------------------------"
    systemctl status httpd 2>/dev/null | grep -i uptime || echo "HTTPD Status: Not found"
    echo ""

    echo "-------------------------------MySQL Uptime---------------------------------"
    m=$(mysql -V 2>/dev/null | awk '{print $5}' | cut -d. -f-2)
    echo "MySQL Version: $m"
    mysqladmin version 2>/dev/null | grep -i uptime || echo "MySQL Status: Not found"
    echo ""

    echo "-------------------------------Disk Usage >80%-------------------------------"
    df -h / | grep -v Filesystem
    echo ""

    echo "----------------------------Failed/blocked server login attempts---------------"
    sshu=$(grep sshd /var/log/secure 2>/dev/null | grep Accept | grep -v 67.20 | awk '{print $9, $11}')
    if [ -z "$sshu" ]; then
        echo "* No unauthorized ssh login attempts found"
    else
        echo "* Server has accepted ssh sessions from:"
        grep sshd /var/log/secure 2>/dev/null | grep Accept | grep -v 67.20 | awk '{print $9, $11}' | sort | uniq
    fi
    echo ""
    sshe=$(grep Failed /var/log/secure 2>/dev/null | wc -l)
    echo "Number of unauthorized access attempts blocked: $sshe"
    echo ""

    # Rootkit Scanning logic from month.sh
    echo "--- Initiating Rootkit Scan ---"
    if [ -d /usr/local/chkrootkit ]; then
        cd /usr/local/chkrootkit && ./chkrootkit -q | grep -i infect || echo "No chkrootkit infections."
    fi
    if command -v rkhunter >/dev/null 2>&1; then
        rkhunter --update >/dev/null 2>&1
        rkhunter -c --sk -q --summary | sed -n '/Rootkit checks/,/Suspect applications/p'
    fi
} > "$LOG_FILE"

/usr/sbin/sendmail "$RECEIVER" < "$LOG_FILE"
echo "Monthly health report sent to $RECEIVER"
rm -f "$LOG_FILE"
