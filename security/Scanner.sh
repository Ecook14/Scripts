#!/bin/bash
echo "===== SECURITY SCAN START ====="
date
echo

##############################
# LOGIN INVESTIGATION
##############################
echo "[1] Last logins"
last -a | head -n 50
echo

echo "[2] SSH brute-force / anomalies"
grep -i "Failed" /var/log/secure | tail -n 50
grep -i "Accepted" /var/log/secure | tail -n 50
echo

echo "[3] cPanel/WHM login log"
cat /usr/local/cpanel/logs/login_log | tail -n 50
echo

##############################
# CRON PERSISTENCE
##############################
echo "[4] User crontab"
crontab -l 2>/dev/null
echo

echo "[5] System cron directories"
ls -la /etc/cron.*
echo

##############################
# SSH PERSISTENCE
##############################
echo "[6] Root authorized_keys"
cat /root/.ssh/authorized_keys 2>/dev/null
echo

echo "[7] All user authorized_keys"
find /home /root -maxdepth 3 -name "authorized_keys" -exec echo "FILE {}" \; -exec cat {} \;
echo

##############################
# NEW USERS
##############################
echo "[8] Suspicious system accounts"
awk -F: '($3 == 0) {print "[!] Extra ROOT account →", $1}' /etc/passwd
echo

echo "[9] Full passwd listing"
cat /etc/passwd
echo

##############################
# MALWARE INDICATORS
##############################
echo "[10] Searching for nuclear.x86"
find / -type f -name "nuclear.x86" 2>/dev/null
grep -r "nuclear.x86" / 2>/dev/null | head -n 50
echo

echo "[11] Suspicious processes"
ps aux | egrep "nuclear|xmrig|kdevtmpfs|kinsing|udevd|systemd-network" --color
echo

echo "[12] Suspicious network connections"
ss -tulpn | egrep "87.121.84.78|45.148.120.23|3333|5555|7777" --color
echo

##############################
# WEBSITE / DOMAIN CHECK
##############################
echo "[13] Searching for bitcoin-miner injections"
grep -R "bitcoin\|btc\|miner\|nuclear" /home/*/public_html 2>/dev/null | head -n 40
echo

echo "===== SECURITY SCAN COMPLETE ====="
