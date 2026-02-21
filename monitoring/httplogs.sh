#!/bin/sh
# Author: Nihar
# Description: Real-time Apache access and error log tailer.

echo Domain?
read domain
grep $domain /usr/local/apache/logs/error_log
tail /var/log/apache2/error.log
tail -f $domain /var/log/apache2/error.log
tail -f $domain /usr/local/apache/logs/error_log
