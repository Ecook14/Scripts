#!/bin/bash
echo "===== SECURITY SCAN START ====="
date
echo

#########################################
# FAST NUCLEAR.X86 SCAN (PRIORITY)
#########################################
echo "[0] QUICK SCAN: nuclear.x86"
echo "→ Searching common malware locations..."
find /tmp /var/tmp /dev/shm /usr/local/bin /usr/bin /root -type f -name "nuclear.x86" 2>/dev/null

echo
echo "→ Fast grep for nuclear.x86 references..."
grep -R "nuclear.x86" /var /usr/local/cpanel /root 2>/dev/null | head -n 40
echo


#########################################
# LOGIN INVESTIGATION
#########################################
echo "[1] Suspicious SSH logins"
grep -iE "Failed|Accepted" /var/log/secure | tail -n 40
echo

echo "[2] cPanel/WHM login log anomalies"
grep -iE "FAILED|error|root" /usr/local/cpanel/logs/login_log | tail -n 40
echo


#########################################
# CRON PERSISTENCE
#########################################
echo "[3] Suspicious cron entries"
grep -R "wget\|curl\|bash -i\|sh -i\|nuclear\|miner\|xmrig" /etc/cron* /var/spool/cron 2>/dev/null
echo


#########################################
# SSH PERSISTENCE
#########################################
echo "[4] Unauthorized keys"
grep -R "ssh-rsa\|ssh-ed25519" /root/.ssh /home/*/.ssh 2>/dev/null | \
grep -v "your-known-good-key" 
echo


#########################################
# SUSPICIOUS USERS
#########################################
echo "[5] Extra ROOT accounts"
awk -F: '($3==0){print "[!] ROOT ACCOUNT →", $1}' /etc/passwd
echo


#########################################
# WEBSITE INJECTION SCAN
#########################################
echo "[6] Infected website files (show ONLY infected files)"
grep -RIl \
    -e "base64_decode" \
    -e "eval(" \
    -e "gzinflate" \
    -e "shell_exec" \
    -e "bitcoin" \
    -e "btc" \
    -e "miner" \
    -e "nuclear" \
    /home/*/public_html 2>/dev/null | head -n 50
echo


#########################################
# MALWARE PROCESSES & NETWORK
#########################################
echo "[7] Malware-like processes"
ps aux | egrep "nuclear|xmrig|kinsing|kdevtmpfs|udevd|watchdog" --color
echo

echo "[8] Suspicious network connections"
ss -tulpn | egrep "87.121|45.148|3333|5555|7777" --color
echo


#########################################
# FINAL
#########################################
echo "===== SECURITY SCAN COMPLETE ====="
