#!/bin/bash
wget http://162.241.117.143/monthly_check/month.sh
d=$(date +%Y%m%d)
sh /root/month.sh > month_result_$d_temp.txt;sed '2d' /root/month_result_$d_temp.txt > /root/month_result_$d.txt
receiver=managedserveralerts@hostgator.in


m() {
   to_addr="$receiver"
/usr/sbin/sendmail  "$to_addr" < /root/month_result_$d.txt
}

   m "$receiver"
rm /root/month_result_$d_temp.txt
