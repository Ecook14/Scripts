#!/bin/bash
# Author: Nihar
# Description: Recreates and sets permissions for common system log files.

echo "Recreating log files with touch command..."

# Recreate log files with touch command
sudo touch /var/log/apache2 /var/log/boot.log /var/log/btmp /var/log/chkservd.log \
/var/log/cloud-init.log /var/log/cron /var/log/dcpumon /var/log/dmesg /var/log/exim_mainlog \
/var/log/exim_paniclog /var/log/exim_rejectlog /var/log/firewalld /var/log/grubby /var/log/maillog \
/var/log/messages /var/log/mysqld.log /var/log/named /var/log/ppp /var/log/secure /var/log/tuned \
/var/log/wp-toolkit /var/log/wtmp /var/log/xferlog.offsetftpsep /var/log/yum.log

# Set permissions and ownership for the log files
sudo chown root:root /var/log/apache2 /var/log/boot.log /var/log/btmp /var/log/chkservd.log \
/var/log/cloud-init.log /var/log/cron /var/log/dcpumon /var/log/dmesg /var/log/exim_mainlog \
/var/log/exim_paniclog /var/log/exim_rejectlog /var/log/firewalld /var/log/grubby /var/log/maillog \
/var/log/messages /var/log/mysqld.log /var/log/named /var/log/ppp /var/log/secure /var/log/tuned \
/var/log/wp-toolkit /var/log/wtmp /var/log/xferlog.offsetftpsep /var/log/yum.log

sudo chmod 644 /var/log/apache2 /var/log/boot.log /var/log/btmp /var/log/chkservd.log \
/var/log/cloud-init.log /var/log/cron /var/log/dcpumon /var/log/dmesg /var/log/exim_mainlog \
/var/log/exim_paniclog /var/log/exim_rejectlog /var/log/firewalld /var/log/grubby /var/log/maillog \
/var/log/messages /var/log/mysqld.log /var/log/named /var/log/ppp /var/log/secure /var/log/tuned \
/var/log/wp-toolkit /var/log/wtmp /var/log/xferlog.offsetftpsep /var/log/yum.log

echo "Log files recreated and permissions set."
