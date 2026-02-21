#!/bin/bash
# Author: Nihar
# Description: High-level disk usage and large file analyzer.

# Colors
red=$(tput setaf 1)
gre=$(tput setaf 2)
yel=$(tput setaf 3)
vio=$(tput setaf 5)
cya=$(tput setaf 6)
res=$(tput sgr 0)

START=$(date +%s)
TARGET_DIRS="/ /home /home1 /home2 /var /opt /tmp /backup"

# Disk Usage Summary
tot=$(df -h / | tail -n 1 | awk '{print $5}' | sed 's/%//')
echo -e "\nDisk usage of the root partition is at: $red $tot% $res\n"

# Top Directory Usage
echo -e "\n$cya Top Disk consuming Directories:\n ----------------------------------------\n"
for dir in $TARGET_DIRS; do
    [ -d "$dir" ] || continue
    echo -e "Scanning $yel$dir$res ..."
    du -xh --max-depth=1 "$dir" 2>/dev/null | sort -rh | head -3
done

# Top Large Files (200MB+)
echo -e "\n$gre Top Files consuming disk space (>200MB):\n ----------------------------------------\n"
find $TARGET_DIRS -type f -size +200M 2>/dev/null | xargs du -h 2>/dev/null | sort -rh | head -n 5

echo -e "\n$red Important Note:$res"
echo " Do not delete logs directly — truncate with 'echo > filename' when possible."

END=$(date +%s)
echo -e "\n$gre Total Runtime: $((END - START)) seconds $res"
