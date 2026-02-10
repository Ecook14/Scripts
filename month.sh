#!/bin/bash
IFCONFIG='/sbin/ifconfig'
NETSTAT='/bin/netstat'
CUT='/bin/cut'
AWK='/bin/awk'
GREP='/bin/grep'
EGREP='/bin/egrep'
ECHO='/bin/echo'
${ECHO} "Subject: $HOSTNAME - Monthly server health report"
echo -e "-------------------------------System Information----------------------------"
echo -e "Hostname:\t\t"`hostname`
echo -e "uptime:\t\t\t"`uptime | awk '{print $3,$4}' | sed 's/,//'`
echo -e "Kernel:\t\t\t"`uname -r`
echo -e "Architecture:\t\t"`arch`
echo ""
echo -e "-------------------------------WebServer Uptime-----------------------------"
v=/bin/cat /etc/redhat-release > /dev/null 2>&1
if v=6
then
systemctl status httpd | grep -Po ".*; \K(.*)(?= ago)"
else
systemctl status httpd | grep -i uptime
fi
echo ""
echo -e "-------------------------------MySQL Uptime---------------------------------"
m=$(mysql -V 2>/dev/null| awk '{print $5}'| cut -d. -f-2)
echo "MySQL Version: $m"
mysqladmin  version | grep -i uptime
echo ""

echo -e "-------------------------------Disk Usage >80%-------------------------------"
df -h  /
echo ""

echo "----------------------------Failed/blocked server login attempts---------------"
sshu=$(grep sshd /var/log/secure |grep Accept | grep -v 67.20 | awk {'print $9, $11'})
if [ -z "$sshu" ]; then
echo -en "* No unauthorized ssh login attempts found\n"
else
echo -en "* Server has accepted ssh sessions from the following IPs/Users:\n"
grep sshd /var/log/secure |grep Accept | grep -v 67.20 | awk {'print $9, $11'} | grep '[0-9].[0-9]' |sort -n |uniq
fi
echo ""
echo ""
sshe=$(grep Failed /var/log/secure | wc -l)
echo -en "Number of unauthorized access blocked: $sshe"
echo ""
echo ""
#echo "----------------------------Load Average ------------------------------------------"
#echo "----------------------------------------------------------------------------------"
#echo "|Average:         CPU     %user     %nice   %system   %iowait    %steal     %idle  |"
#echo "----------------------------------------------------------------------------------"
#for file in `ls -tr /var/log/sa/sa* | grep -v sar`
#do
#dat=`sar -f $file | head -n 1 | awk '{print $4}'`
#echo -n $dat
#sar -f $file  | grep -i Average | sed "s/Average://"
#done
#echo "+----------------------------------------------------------------------------------+"
#for file in `ls -tr /var/log/sa/sa* | grep -v sar`
#do
#        sar -f $file | head -n 1 | awk '{print $4}'
#        echo "-----------"
#        sar -u -f $file | awk '/Average:/{printf("CPU Average: %.2f%\n"), 100 - $4}'
#        printf "\n"
#done


rm -rf /usr/local/src/manage
mkdir /usr/local/src/manage
servermanage=/usr/local/src/manage
cd $servermanage
scan=$servermanage/log.sm

scans(){
${ECHO} "working"
cd $servermanage
${ECHO} -e "~~~~~~~~~~~~~~~~~~Detecting-Linux-RootKit~~~~~~~~~~~~~~~~~~\n"
/usr/local/chkrootkit/chkrootkit -V >$servermanage/chkver 2>&1
if ! `${GREP} -q ".52" $servermanage/chkver`
then
rm -rf /usr/local/chkrootkit/
wget http://$SOURCEIP/softwares/chkrootkit.tar.gz
tar xzf chkrootkit.tar.gz
mv chkrootkit-0.52 /usr/local/chkrootkit
cd /usr/local/chkrootkit
make sense
wait
fi

${ECHO} -en "\nChkrootkit is scanning the machine. Please wait...\n"
cd /usr/local/chkrootkit
./chkrootkit -q > $servermanage/sm-chkrootkit.log
wait

cd $servermanage
${ECHO} -en "\n\n~~~~~~~~~~~~~~~~~~Detecting-Linux-RootKit~~~~~~~~~~~~~~~~~~\n"

if ! `/usr/local/bin/rkhunter -V|${GREP} -q "1.4.6"`
then
wget http://$SOURCEIP/softwares/rkhunter-1.4.6.tar.gz
tar xzf rkhunter-1.4.6.tar.gz
cd rkhunter-*
rm -f /etc/rkhunter.conf
./installer.sh --layout default --install
wait
fi

${ECHO} -en "\nRkhunter is Running in the Server. Please wait...\n"
/usr/local/bin/rkhunter --update
/usr/local/bin/rkhunter -c --sk -q --summary > $servermanage/sm-rkhunter.log 2>&1
wait
} # scans END #

cd $servermanage

#${ECHO} -en "\nInitiating Linux-RootKit-->Scanning...\n"
scans >> $scan 2>&1

${ECHO} " Server RootKit Scanned"
if [ -f /usr/local/etc/ma-exclude-scan ]
then ${ECHO} " CHKRootkit / RKHunter - [Skipped]"
else

${ECHO} " CHK result:"
if [ $(${GREP} -i infect $servermanage/sm-chkrootkit.log |${GREP} -v 465 | ${GREP} -v "/sbin/init"|${GREP} -v passwd| wc -l) != "0" ]; then
${ECHO} "Chkrootkit scan result:-
$(${GREP} -i infect $servermanage/sm-chkrootkit.log| ${GREP} -v 465 | ${GREP} -v "/sbin/init"|${GREP} -v passwd)"
else
${ECHO} "    CHK-rootkit scan done, no infected files were detected."
fi
${ECHO} "************************************"

cd $servermanage

${ECHO} " RK result:"
sed -n '/Rootkit checks/,/Suspect applications/p' $servermanage/sm-rkhunter.log | sed -e '/The system checks took/,+10d'
fi
rm -f /root/month.sh
#${ECHO} "***************"
