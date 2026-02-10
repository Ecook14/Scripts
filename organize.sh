#!/bin/bash

echo "Organizing Scripts..."

# Create directories if they don't exist
mkdir -p security monitoring automation

# Security
mv centos_hardening.sh security/ 2>/dev/null
mv abuse.sh security/ 2>/dev/null
mv findemailspam.sh security/ 2>/dev/null
mv icmaldet.sh security/ 2>/dev/null

# Monitoring
mv adlog.sh monitoring/ 2>/dev/null
mv "adlog(1).sh" monitoring/ 2>/dev/null
mv adlog1.sh monitoring/ 2>/dev/null
mv l2.sh monitoring/ 2>/dev/null
mv plesk_health.sh monitoring/ 2>/dev/null
mv CPUload.sh monitoring/ 2>/dev/null
mv diskusage.sh monitoring/ 2>/dev/null
mv ec.pl monitoring/ 2>/dev/null
mv logs.sh monitoring/ 2>/dev/null
mv apachelogs.sh monitoring/ 2>/dev/null

# Automation
mv optimize.sh automation/ 2>/dev/null
mv maxworker.sh automation/ 2>/dev/null
mv zabixconfig.sh automation/ 2>/dev/null
mv wordpressfiles.sh automation/ 2>/dev/null
mv swiss.sh automation/ 2>/dev/null
mv swiss1.sh automation/ 2>/dev/null
mv porta.sh automation/ 2>/dev/null
mv "porta (1).sh" automation/ 2>/dev/null
mv permfix.sh automation/ 2>/dev/null
mv permfix1.sh automation/ 2>/dev/null
mv mailish.sh automation/ 2>/dev/null
mv mailish1.sh automation/ 2>/dev/null
mv mailish2.sh automation/ 2>/dev/null

echo "Done! Files moved."
