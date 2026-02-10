# Legacy Server Administration Scripts

A collection of shell, Perl, and Python scripts for managing Linux servers (cPanel, Plesk, CentOS).

> [!NOTE]
> **Modern Replacement**: These scripts are being migrated to a unified Go CLI tool located in [`Go/ops-cli`](./Go/ops-cli). New development should happen there.

## 📂 Script Categories

### 🛡️ Security & Hardening
- **`centos_hardening.sh`**: Comprehensive server hardening (SSH, FTP, firewall).
- **`abuse.sh`**: Automates data collection logs/evidence for compromised accounts.
- **`findemailspam.sh`**: Forensics tool for tracking spam sources in Exim.

### 📊 Monitoring & Logging
- **`ec.pl`**: ("Email Count") Advanced Perl script for Exim log analysis and stats.
- **`adlog.sh`** / **`l2.sh`**: Interactive menu-driven log viewers (Apache, MySQL, System).
- **`apachelogs.sh`**: Quick tail for specific domain error logs.
- **`NFS.sh`**: Network File System and general utility menu.

### 🚀 Optimization & Health
- **`optimize.sh`**: Auto-tunes Apache (`MaxRequestWorkers`) and MySQL based on RAM.
- **`maxworker.sh`**: Similar to optimize.sh, specifically for Apache workers.
- **`plesk_health.sh`**: Deep health check for Plesk environments.
- **`CPUload.sh`**: Diagnoses high load (CPU vs I/O wait).
- **`diskusage.sh`**: Fast disk space analyzer finding large files/dirs.
- **`zabixconfig.sh`**: Zabbix Agent2 installer and configuration.

### 🛠️ Utilities
- **`wordpressfiles.sh`**: Database import helper.
- **`Script Initialization Phase.txt`**: Documentation on monitoring setup.

## ⚠️ Usage Status
Most scripts require `root` privileges. Some include a legacy "Google Auth" check (hardcoded to `1`).
