#!/bin/bash
# Author: Nihar
# 🔥 High-speed disk usage analyzer for large VPS/DEDI systems with multiple user volumes

# === Colors ===
red=$(tput setaf 1)
gre=$(tput setaf 2)
yel=$(tput setaf 3)
vio=$(tput setaf 5)
cya=$(tput setaf 6)
res=$(tput sgr 0)

# === Setup ===
START=$(date +%s)
TARGET_DIRS="/ /home /home1 /home2 /var /opt /tmp /backup"
DISK_FILE="/tmp/diskusagedata.txt"
DIR_FILE="/tmp/diskusage.txt"

# === Clear Logs (Safe Pre-Truncation) ===
: > /var/log/btmp
: > /var/log/secure

# === Disk Usage Summary ===
tot=$(df -h | awk '/vda1|sda1/ {gsub("%", "", $5); print $5}')
echo -e "\nDisk usage of the server is at: $red $tot% $res\n"

# === Top Directory Usage ===
echo -e "\n$cya Top Disk consuming Directories:\n ----------------------------------------\n"
for dir in $TARGET_DIRS; do
    [ -d "$dir" ] || continue
    echo -e "\nScanning $yel$dir$res ..."
    du -xh --max-depth=1 "$dir" 2>/dev/null | sort -rh | head -3
done

# === Top Large Files (200MB+) ===
echo -e "\n$gre Top Files consuming disk space:\n ----------------------------------------\n"
find $TARGET_DIRS -type f -size +200M 2>/dev/null \
    | sort | uniq | while read -r file; do
        du -h "$file" 2>/dev/null
    done | sort -rh | head -n 5 | tee "$DISK_FILE"

# === Top Large Directories ===
echo -e "\n$vio Top Directories consuming disk space:\n ---------------------------------------------\n"
find $TARGET_DIRS -mindepth 1 -maxdepth 3 -type d 2>/dev/null | while read -r dir; do
    size=$(du -s "$dir" 2>/dev/null | awk '{print $1}')
    echo "$size $dir"
done | sort -nr | head -5 | awk '{printf "%.1f MB\t%s\n", $1/1024, $2}' | tee "$DIR_FILE"

# === Suggestions ===
echo -e "\n$yel----------\nSUGGESTIONS:\n----------\n"

if grep -Eq 'backup|\.tar|\.zip|\.gz' "$DISK_FILE"; then
    echo -e "$gre You can remove/archive the following files after confirmation:\n----------------------------------------"
    grep -Ei 'backup|tar|zip|gz' "$DISK_FILE" | head -5
    echo -e "----------------------------------------"
fi

if grep -qi "log" "$DISK_FILE"; then
    echo -e "$yel Log files that could be truncated safely:\n----------------------------------------"
    grep -i 'log' "$DISK_FILE" | head -3
    echo -e "----------------------------------------"
fi

if grep -qi "mail" "$DIR_FILE" && ! grep -qi "cpanel" "$DIR_FILE"; then
    echo -e "$yel Mail directories with high usage:\n----------------------------------------"
    grep -i 'mail' "$DIR_FILE" | head -3
    echo -e "----------------------------------------"
fi

# === Warning ===
echo -e "$red\n Important Note:\n\n^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^"
echo " Do not delete logs directly — truncate with 'echo > filename' when possible."
echo " Refer:"
echo " https://computingforgeeks.com/how-to-empty-truncate-log-files-in-linux/"
echo " https://www.cyberciti.biz/faq/remove-log-files-in-linux-unix-bsd/"
echo -e "^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^\n$res"

# === Runtime ===
END=$(date +%s)
echo -e "\n$gre Total Runtime: $((END - START)) seconds $res"

# === Cleanup ===
rm -f "$DISK_FILE" "$DIR_FILE"
