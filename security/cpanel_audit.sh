#!/bin/bash
# cPanel CVE-2026-41940 Compromise Scanner
# Author: ChatGPT
# Version: 1.0

OUT="/root/cpanel_forensic_$(date +%F_%H-%M).log"

echo "======================================================" | tee -a $OUT
echo "   cPanel / WHM Forensic Scan - CVE-2026-41940        " | tee -a $OUT
echo "======================================================" | tee -a $OUT
echo "Date: $(date)" | tee -a $OUT
echo "" | tee -a $OUT

#########################################
# LOGIN CHECKS
#########################################
echo "### LOGIN HISTORY (last -a)" | tee -a $OUT
last -a | head -50 | tee -a $OUT
echo "" | tee -a $OUT

echo "### /var/log/secure (failed/success SSH)" | tee -a $OUT
grep -Ei "failed|invalid|root|accepted" /var/log/secure | tail -200 | tee -a $OUT
echo "" | tee -a $OUT

echo "### cPanel/WHM login log" | tee -a $OUT
grep -Ei "failed|succeeded|password" /usr/local/cpanel/logs/login_log | tail -200 | tee -a $OUT
echo "" | tee -a $OUT

#########################################
# CRON PERSISTENCE CHECK
#########################################
echo "### ROOT CRONTAB" | tee -a $OUT
crontab -l 2>/dev/null | tee -a $OUT
echo "" | tee -a $OUT

echo "### /etc/cron.* directories" | tee -a $OUT
ls -lah /etc/cron* | tee -a $OUT
echo "" | tee -a $OUT

echo "### Suspicious cron files" | tee -a $OUT
find /etc/cron* -type f -exec grep -HiE "wget|curl|bash|sh|python|perl" {} \; | tee -a $OUT
echo "" | tee -a $OUT

#########################################
# SSH PERSISTENCE / ROOT KEYS
#########################################
echo "### ROOT AUTHORIZED_KEYS" | tee -a $OUT
if [[ -f /root/.ssh/authorized_keys ]]; then
    cat /root/.ssh/authorized_keys | tee -a $OUT
else
    echo "No authorized_keys file found" | tee -a $OUT
fi
echo "" | tee -a $OUT

#########################################
# USER ENUMERATION CHECK
#########################################
echo "### NEW USERS (last 7 days)" | tee -a $OUT
find /home -maxdepth 1 -type d -ctime -7 | tee -a $OUT
echo "" | tee -a $OUT

echo "### /etc/passwd Users" | tee -a $OUT
cat /etc/passwd | tee -a $OUT
echo "" | tee -a $OUT

echo "### Suspicious system users (UID < 1000 except known)" | tee -a $OUT
awk -F: '$3 < 1000 && $1!="root" && $1!="daemon" && $1!="bin" && $1!="sync" {print $0}' /etc/passwd | tee -a $OUT
echo "" | tee -a $OUT

#########################################
# MALWARE / BACKDOOR SEARCH
#########################################
echo "### Searching for nuclear.x86" | tee -a $OUT
find / -type f -name "nuclear.x86" 2>/dev/null | tee -a $OUT
echo "" | tee -a $OUT

echo "### Searching for suspicious ELF binaries" | tee -a $OUT
find / -type f -exec file {} \; | grep -Ei "ELF" | grep -Ei "tmp|var|cache|home" | tee -a $OUT
echo "" | tee -a $OUT

echo "### Searching for miner scripts / payloads" | tee -a $OUT
grep -RHiE "xmrig|minerd|crypto|wallet|stratum|hash" / 2>/dev/null | tee -a $OUT
echo "" | tee -a $OUT

#########################################
# WEBSITE CHECK FOR RANSOM/CRYPTO SIGNS
#########################################
echo "### Scanning websites for Bitcoin / ransom keywords" | tee -a $OUT
grep -RHiE "bitcoin|btc|wallet|ransom|pay" /home/*/public_html 2>/dev/null | tee -a $OUT
echo "" | tee -a $OUT

echo "### Modified index files in last 72 hours" | tee -a $OUT
find /home -type f -iname "index.*" -mtime -3 | tee -a $OUT
echo "" | tee -a $OUT

echo "======================================================" | tee -a $OUT
echo "Scan Completed. Report saved at: $OUT"
echo "======================================================"
