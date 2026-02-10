#!/bin/bash
RED='\033[01;31m'
GREEN='\033[01;32m'
RESET='\033[0m'
clear
echo -e "$GREEN*************************************************************$RESET"
echo -e " Cpanel Hardening Script "
echo -e "$GREEN*************************************************************$RESET"

#Installing chkrootkit
sleep 2;
clear
echo -e "$GREEN************Installing Chkrootkit************$RESET"
cd /usr/local/src/
wget ftp://ftp.pangeia.com.br/pub/seg/pac/chkrootkit.tar.gz
tar -zxvf chkrootkit.tar.gz
cd /usr/local/src/chkrootkit*
make sense
mkdir /usr/local/chkrootkit
mv -vf * /usr/local/chkrootkit/
echo -e "$GREEN************instalation complete************$RESET"
echo -e "$GREEN*************************************************************$RESET"

#Fetching Email id
/bin/grep CONTACTEMAIL /etc/wwwacct.conf | awk '{print $2}' | grep @
chk_email=$?
if [ $chk_email -eq 0 ]; then EMAIL=$(/bin/grep CONTACTEMAIL /etc/wwwacct.conf | awk '{print $2}')
else
EMAIL=contactemail
fi

#setup chkrootkit weekly cron.
echo -e "$GREEN************setting up chkroot weekly cron************$RESET"
sleep 2;
cat > /etc/cron.weekly/chkrootkit_cron.sh << EOF
#!/bin/bash
/usr/local/chkrootkit/chkrootkit -q | mail -s "ChrootKit Scan Report of server: $HOSTNAME" $EMAIL
EOF
chmod +x /etc/cron.weekly/chkrootkit_cron.sh
echo -e "$GREEN************done************$RESET"
sleep 2;

#restart crond
echo -e "$GREEN************restarting service crond************$RESET"
/etc/init.d/crond restart
echo -e "$GREEN*************************************************************$RESET"
sleep 2
clear

#service tweaks
echo -e "$GREEN************Tweaking services************$RESET"
service pcscd stop
chkconfig pcscd off
service portmap stop
chkconfig portmap off
service nfslock stop
chkconfig nfslock off
service rpcidmapd stop
chkconfig rpcidmapd off
service yum-updatesd stop
chkconfig yum-updatesd off
service avahi-daemon stop
chkconfig avahi-daemon off
service autofs stop
chkconfig autofs off
service acpid stop
chkconfig acpid off
service atd stop
chkconfig atd off
service gpm stop
chkconfig gpm off
service haldaemon stop
chkconfig haldaemon off
service hidd stop
chkconfig hidd off
service irqbalance stop
chkconfig irqbalance off
service auditd stop
chkconfig auditd off
service xfs stop
chkconfig xfs off
service cups stop
chkconfig cups off
service bluetooth stop
chkconfig bluetooth off
service anacron stop
chkconfig anacron off
echo -e "$GREEN************tweaked different services************$RESET"
echo -e "$GREEN*************************************************************$RESET"
sleep 2
clear

#Apache Changes -
cp /var/cpanel/conf/apache/local /var/cpanel/conf/apache/local.backup
cat > /var/cpanel/conf/apache/local << EOF
---
"main":
"directory":
"options":
"directive": 'options'
"item":
"options": 'ExecCGI FollowSymLinks IncludesNOEXEC Indexes SymLinksIfOwnerMatch'
"fileetag":
"item":
"fileetag": 'None'
"serversignature":
"item":
"serversignature": 'Off'
"servertokens":
"item":
"servertokens": 'ProductOnly'
"traceenable":
"item":
"traceenable": 'Off'
EOF
#Rebuild httpd conf
/scripts/rebuildhttpdconf
#restart apache
/usr/local/cpanel/scripts/restartsrv_httpd

#Disable the dangerous php functions.
echo -e "$GREEN************disabling dangerous php functions************$RESET"
cp /usr/local/lib/php.ini /usr/local/lib/php.ini.backup
replace -s "disable_functions =" "disable_functions = symlink,shell_exec,exec,proc_close,proc_open,popen,system,dl,passthru,escapeshellarg,escapeshellcmd," -- /usr/local/lib/php.ini
echo -e "$GREEN************Done!************$RESET"
#restarting Apache
echo -e "$GREEN************restarting apache************$RESET"
sleep 2;
/etc/init.d/httpd restart
echo -e "$GREEN*************************************************************$RESET"
clear
sleep 2

#Enabling Shell Fork Bomb Protection
echo -e "$GREEN************Enabling Shell Fork Bomb Protection************$RESET";
perl -I/usr/local/cpanel -MCpanel::LoginProfile -le 'print [Cpanel::LoginProfile::install_profile('limits')]->[1];'
sleep 2
echo -e "$GREEN************ Done ************$RESET";
echo -e "$GREEN*************************************************************$RESET"
clear
sleep 2

#FTP hardening + Enabling passive port range
echo -e "$GREEN************FTP Hardening************$RESET"
sleep 2
sed -i '/NoAnonymous/s/no/yes/2' /var/cpanel/conf/pureftpd/main
sed -i '/AnonymousCantUpload/s/no/yes/2' /var/cpanel/conf/pureftpd/main
sed -i '/RootPassLogins/s/yes/no/' /var/cpanel/conf/pureftpd/main
echo "PassivePortRange: 30000 50000" >> /var/cpanel/conf/pureftpd/main #Enabling passive port range
sleep 2
echo -e "$GREEN************Restarting FTP************$RESET"
/usr/local/cpanel/scripts/setupftpserver pure-ftpd --force
/scripts/restartsrv_pureftpd
echo -e "$GREEN************Done************$RESET"
sleep 2
clear

#Setting SSH Legal Message
echo -e "$GREEN***********Setting SSH Legal Message*************$RESET"
sleep 2
cp /etc/motd /etc/motd.backup
cat >> /etc/motd <<EOF
###############################################################################################################################################
###############################################################################################################################################
ALERT!!!!!!!!!!!!! You are entering a secured area! Your IP and login information have been recorded. System administration has been notified.

This system is restricted to authorized access only. All activities on this system are recorded and logged.
###############################################################################################################################################
###############################################################################################################################################
EOF
echo -e "$GREEN************Done************$RESET"
sleep 2
clear

#Disable direct root login and Creating new wheel user
echo -e "$GREEN************creating new wheel user - admin************$RESET"
sleep 2
useradd admin
yum -y install expect

#To set length of password
mkpasswd -l 12 admin > /root/.admin_pass
sleep 2
usermod -G wheel admin
echo -e "$GREEN ******* Wheel user - admin created *******$RESET"
sleep 2

#backup sshd.conf
cp /etc/ssh/sshd_config /etc/ssh/sshd_config.backup
replace -s "#PermitRootLogin yes" "PermitRootLogin no" -- /etc/ssh/sshd_config
cat >> /etc/ssh/sshd_config <<EOF
AllowUsers admin
EOF
echo -e "$GREEN**************Wheel user Created***************$RESET"
sleep 2

#restarting sshd
echo -e "$GREEN************Restarting sshd************$RESET"
sleep 2
/etc/init.d/sshd restart
echo -e "$GREEN*************************************************************$RESET"
sleep 2
clear
#Changing default ssh port.
echo -e "$GREEN************Changing default ssh port************$RESET"
sleep 2;
replace -s "#Port 22" "Port 1243" -- /etc/ssh/sshd_config
echo -e "$GREEN************ssh port updated. Restarting sshd************$RESET"
/etc/init.d/sshd restart
echo -e "$GREEN*************************************************************$RESET"
sleep 2;
clear;

#updating resolve.conf
echo -e "$GREEN************updating resolv.conf************$RESET"
sleep 2;
mv /etc/resolv.conf /etc/resolv.conf.backup
cat > /etc/resolv.conf <<EOF
nameserver 8.8.8.8
nameserver 8.8.4.4
EOF
echo -e "$GREEN************resolv.conf updated************$RESET"
echo -e "$GREEN*************************************************************$RESET"
sleep 2;
clear

echo -e "$GREEN**************Done!***************$RESET"
echo -e "$GREEN*************************************************************$RESET"
sleep 2;
clear

#Hardening named.conf
echo -e "$GREEN************Setting up named.conf ************$RESET"
cp /etc/named.conf /etc/named.conf.backup
sed -i '18i version "[null]";' /etc/named.conf
#sed -i '19i recursion no;' /etc/named.conf
#sed -i '32i category lame-servers { null; };' /etc/named.conf
echo -e "$GREEN************Done************$RESET"
sleep 2
echo -e "$GREEN************Restarting named service************$RESET"
sleep 3
/etc/init.d/named restart
echo -e "$GREEN************Done************$RESET"
sleep 5
clear

#Installing CSF
echo -e "$GREEN************Installing CSF************$RESET"
sleep 2
cd /usr/local/src/
rm -fv csf.tgz
wget https://download.configserver.com/csf.tgz
tar -xzvf csf.tgz
cd /usr/local/src/csf/
sh install.sh
#backup csf.conf
cp /etc/csf/csf.conf /etc/csf/csf.conf.backup
#replace new ssh port in csf.conf
sed -i '/PORTS_sshd/s/22/1243/' /etc/csf/csf.conf
#Turn off CSF TESTING mode
sed -i '/TESTING/s/1/0/' /etc/csf/csf.conf
#Enable RESTRICT_SYSLOG in CSF
sed -i '69s/0/3/' /etc/csf/csf.conf
#Enable LF_SCRIPT_ALERT in csf
sed -i '/LF_SCRIPT_ALERT/s/0/1/' /etc/csf/csf.conf
#Enable passive port range in CSF.conf
sed -i '/^TCP_IN/ s/2087/2087,30000:50000/g' /etc/csf/csf.conf
sed -i '/^TCP_OUT/ s/2087/2087,30000:50000/g' /etc/csf/csf.conf
sed -i '/^TCP6_IN/ s/2087/2087,30000:50000/g' /etc/csf/csf.conf
sed -i '/^TCP6_OUT/ s/2087/2087,30000:50000/g' /etc/csf/csf.conf

echo -e "$GREEN************Whitelisting IP's in CSF************$RESET"

cat >> /etc/csf/csf.ignore <<EOF

115.110.127.198
122.15.255.69
115.110.71.146
122.15.181.197
111.93.159.50
220.227.162.29
EOF
csf -a 115.110.127.198 "HGI support"
csf -a 122.15.255.69 "HGI support"
csf -a 115.110.71.146 "HGI support"
csf -a 122.15.181.197 "HGI support"
csf -a 111.93.159.50 "HGI support"
csf -a 220.227.162.29 "HGI support"
/scripts/cphulkdwhitelist 115.110.127.198
/scripts/cphulkdwhitelist 122.15.255.69
/scripts/cphulkdwhitelist 115.110.71.146
/scripts/cphulkdwhitelist 122.15.181.197
/scripts/cphulkdwhitelist 111.93.159.50
/scripts/cphulkdwhitelist 220.227.162.29

echo -e "$GREEN************Whitelisted all our support IP************$RESET"

echo -e "$GREEN*************************************************************$RESET"

clear
echo -e "$GREEN*****************Restarting CSF. Please wait!*****************$RESET"
sleep 2
csf -r
echo -e "$GREEN************CSF restarted successfully************$RESET"

echo -e "$GREEN************CSF Installed and Enabled ************$RESET"
echo -e "$GREEN*************************************************************$RESET"

clear

sleep 2;

#enable cphulkd
#echo -e "$GREEN************Enabling cPhulkd************$RESET"
#/usr/local/cpanel/bin/cphulk_pam_ctl --enable
#echo -e "************cPhulkd Enabled************"
#echo -e "$GREEN*************************************************************$RESET"
#sleep 2
#clear
#whitelisting IP's in cphulkd
#echo -e "$GREEN************Whitelisting IP's in cphulkd************$RESET"
#sleep 2;
#/scripts/cphulkdwhitelist 115.114.59.182
#/scripts/cphulkdwhitelist 115.114.17.146
#/scripts/cphulkdwhitelist 115.249.14.65
#/scripts/cphulkdwhitelist 115.254.83.21
#echo -e "$GREEN************Done************$RESET"
#echo -e "$GREEN*************************************************************$RESET"
#sleep 2;
#clear

#Clamav Installation
echo -e "$GREEN************Installing Clamav************$RESET"
/scripts/update_local_rpm_versions --edit target_settings.clamav installed
/scripts/check_cpanel_rpms --fix --targets=clamav
echo -e "$GREEN************Done************$RESET"
echo -e "$GREEN*************************************************************$RESET"
echo -e "$GREEN************Creating clamscan weekly cron************$RESET "
sleep 2;
cat > /etc/cron.weekly/clamscan.cron <<EOF
rm -f /root/infections
awk '!/nobody/{print 222 | "sort | uniq" }' /etc/userdomains | sort | uniq > /root/userslist
for i in QQQcat /root/userslistQQQ; do /usr/local/cpanel/3rdparty/bin/clamscan -i -r /home/III 2>>/dev/null; done >> /root/infections
EOF
sed -i 's/QQQ/`/g' /etc/cron.weekly/clamscan.cron
sed -i 's/222/$2/g' /etc/cron.weekly/clamscan.cron
sed -i 's/III/$i/g' /etc/cron.weekly/clamscan.cron

chmod +x /etc/cron.weekly/clamscan.cron

echo -e "$GREEN************Done************$RESET"
echo -e "$GREEN*************************************************************$RESET"
sleep 3
clear
#restart crond
echo -e "$GREEN************restarting service crond************$RESET"
/etc/init.d/crond restart
echo -e "$GREEN*************************************************************$RESET"
sleep 2
clear
#cpupdate
echo -e "$GREEN************updating /etc/cpupdate.conf************$RESET"
sleep 2
cp /etc/cpupdate.conf /etc/cpupdate.conf.backup
cat > /etc/cpupdate.conf << EOF
CPANEL=release
RPMUP=daily
SARULESUP=daily
STAGING_DIR=/usr/local/cpanel
UPDATES=daily
EOF
echo -e "$GREEN************Done************$RESET"
echo -e "$GREEN*************************************************************$RESET"
sleep 2

#running upcp
echo -e "$GREEN************ Running UPCP Now!. Please Wait for 30-40 minutes!!************$RESET"
echo -e "$GREEN*************************************************************$RESET"
sleep 5
/scripts/upcp --force
echo -e "$GREEN************Done************$RESET"
echo -e "$GREEN*************************************************************$RESET"
sleep 5
clear

#Running Yum update
echo -e "$GREEN************ Updating your server softwares!. Please wait for few minutes.************$RESET"
sleep 5
yum -y update
echo -e "$GREEN************Done************$RESET"
echo -e "$GREEN*************************************************************$RESET"
sleep 3
clear

# Adding motd
echo "#############################################################################################
#                             Managed VPS/Dedicated Server                                  #
#                      All connections are monitored and recorded                           #
#                 Disconnect IMMEDIATELY if you are not an authorized user!                 #
#############################################################################################
" > /etc/motd

#Enable SSH Alerts in .bashrc
cp /root/.bashrc /root/bashrc_backup
cat >> /root/.bashrc << EOF
echo 'ALERT - Root Shell Access ($HOSTNAME) on:' QQQdateQQQ QQQwhoQQQ | mail -s "Alert: Root Access from QQQwho | cut -d'(' -f2 | cut -d')' -f1QQQ" $EMAIL
EOF
sed -i 's/QQQ/`/g' /root/.bashrc

#Securing TMP Directory
echo -e "$GREEN************Securing TMP directory************$RESET"
sleep 3
#backup fstab
cp /etc/fstab /etc/fstab.backup
echo -e "$GREEN************backup of /etc/fstab taken************$RESET"
sed -i /tmpDSK/d /etc/fstab
cat >> /etc/fstab << EOF
/usr/tmpDSK /tmp ext3 noauto,noexec,rw 0 0
EOF

#Configuring WHM Backup System
echo -e "$GREEN************Enabling and Configuring advanced cpanel Backup Configuration Sytem ************$RESET"
cp /var/cpanel/backups/config /var/cpanel/backups/config.backup
echo -e "$GREEN************ Backup existing config file ************$RESET"
sleep 3

cat > /var/cpanel/backups/config << EOF
---
BACKUPACCTS: 'yes'
BACKUPBWDATA: 'yes'
BACKUPDAYS: 0,2,5
BACKUPDIR: /backup
BACKUPENABLE: 'yes'
BACKUPFILES: 'yes'
BACKUPLOGS: 'no'
BACKUPMOUNT: 'no'
BACKUPSUSPENDEDACCTS: 'no'
BACKUPTYPE: compressed
BACKUP_DAILY_ENABLE: 'yes'
BACKUP_DAILY_RETENTION: 4
BACKUP_MONTHLY_DATES: 1
BACKUP_MONTHLY_ENABLE: 'no'
BACKUP_MONTHLY_RETENTION: 1
BACKUP_WEEKLY_DAY: 0
BACKUP_WEEKLY_ENABLE: 'no'
BACKUP_WEEKLY_RETENTION: 4
ERRORTHRESHHOLD: 3
GZIPRSYNCOPTS: --rsyncable
KEEPLOCAL: 1
LINKDEST: 0
LOCALZONESONLY: 'no'
MAXIMUM_TIMEOUT: 2700
MYSQLBACKUP: accounts
POSTBACKUP: 'no'
PREBACKUP: -1
PSQLBACKUP: 'no'
EOF
sleep 3
echo -e "$GREEN************ Backup Configuration Done ************$RESET"
echo -e "$GREEN*************************************************************$RESET"
sleep 3
mount -a
echo -e "$GREEN************Done************$RESET"
echo -e "$GREEN*************************************************************$RESET"
echo -e "$GREEN*************************************************************$RESET"
echo -e " Server Hardening completed "
echo -e "$GREEN*************************************************************$RESET"
clear
echo -e "$RED
The following steps have been done as part of server hardening.
1. Secured DNS server.
2. Secured php by disabling dangerous php functions.
3. Installed and configured - Config Server Firewall. Please provide us your IP address so that we can white-list the same in the firewall.
4. Enabled Login Failure Daemon.
5. Disabled unwanted services.
6. Enabled Shell Fork Bomb Protection
7. FTP Hardening : Disable anonymous ftp and root ftp in this server.
8. TMP directory hardening.
9. Enable SSH alerts.
10. Updated all server software's.


Hello <Customer>,

We have completed the following tasks for your Managed server.
Server hardening
Added your server to our monitoring system

As a part of Server hardening, we have performed the following tasks

1.  Secured the DNS server.
2.  Secured PHP by disabling dangerous php functions.
3.  Configured Config Server Firewall
4.  Enable Login Failure Daemon
5.  Disable unwanted services
6.  Enabled Shell Fork Bomb Protection
7.  FTP Hardening : Disable anonymous ftp and root ftp in this server
8.  TMP directory hardening
9.  Enabled SSH alerts
10. Updated all server software's
11. Disabled ping request to your server
12. Installed MOD_EVASIVE  
13. Disabled direct root access to the server and created a wheel user for ssh access
14. Changed the default SSH port to  1243
15. Installed ClamAV and scheduled to scan the server on weekly basis for malicious files
16. Installed Netdata to monitor the server performance

Please use the following details to access the server. 

<specify the login details - Use SF code option to highlight the login details>

Kindly update us with your public IP address or IP range so we can whitelist the same on the server.

Important note:
To monitor your servers continuously, please notify us if you are changing the root password or SSH port
We've whitelisted the below given Support IP addresses. Please don't remove them from the server firewall
115.110.127.198
122.15.255.69
115.110.71.146
182.73.214.22
111.93.159.50
220.227.162.29
162.241.117.143

Please let us know if you have any questions. 


Have a nice day.  $RESET"

#removing files in /usr/local/src/
rm -rf /usr/local/src/*

