# 📖 Exhaustive Operational Manual: Unified Ops Core

This document is the definitive guide to every file and function within the Unified Ops Core library. It is designed for senior SREs who require full technical transparency of their automation stack.

---

## 🛠️ [1] Primary Triage & Response
These tools are the first line of defense during active incidents.

### 🎮 `automation/maintenance_menu.sh`
**Functions:**
- `Log Sub-menu`: View Apache, System (messages), Exim, and MySQL logs.
- `Network Sub-menu`: Check connectivity (ping), DNS lookups, and port listening status.
- `File System Search`: Rapid `find` based search for files/directories.
- `Consolidation`: Merged logic from `adlog.sh` and `l2.sh`.

### 💓 `monitoring/plesk_health.sh`
**Functions:**
- `System Snapshot`: CPU load, memory pressure, and uptime auditing.
- `Plesk Services`: Health checks for `sw-cp-server`, `psa-dns`, and `nginx`.
- `Web & DB Health`: Scans for slow MySQL queries and Apache/Nginx bottlenecks.
- `Network Triage`: Detects socket-level anomalies and port listening health.

---

## 🏗️ [2] Infrastructure & Automation Module (`/automation`)

### 📦 Application & Service Management
- **`wordpressfiles.sh`**: WordPress-specific automation. Handles database imports, `.htaccess` validation, and user configuration prompts.
- **`zbxsetup.sh`**: Deploy Zabbix Agent2 with a single command. Handles repo setup, firewall rules, and service persistence.
- **`log_fixer.sh`**: Rescues a server after disk-full events. Recreates essential logs and restores proper `root:root` ownership/permissions.

### 🔧 Optimization & Tuning
- **`optimize.sh`**: Multi-layer performance tuning. Optimizes Apache `MaxRequestWorkers` and MySQL buffer pools.
- **`maxworker.sh`**: Calculates optimal Apache worker settings specifically for memory-constrained VPS environments.
- **`sslrewrite.sh`**: Generates high-performance `RewriteCond` rules for `.htaccess` to enforce HTTPS without overhead.

### 🛠️ General Utilities
- **`swiss.sh`**: The ultimate utility tool. Sub-functions:
    - `check_and_open_port`: OS-aware firewall port opening (CentOS/Ubuntu).
    - `check_and_delist_ip`: Interactive delisting from `iptables` or `ufw`.
    - `display_processes`: Deep-port analysis using `lsof`.
- **`dbim.sh`**: Non-interactive MySQL import utility.
- **`permfix.sh`**: Corrects directory (755) and file (644) permissions across home directories.
- **`mailish.sh`**: Audits Exim mail queue, checks for failed login attempts (dovecot), and summarizes sender volume.
- **`porta.sh`**: Auditor for closed/open ports with automated opening capability.

---

## 🛰️ [3] Observability & Monitoring Module (`/monitoring`)

### 📈 Performance Telemetry
- **`cpustats.sh`**: Real-time monitor with high-visibility alerts for I/O Wait, Mem/Swap pressure, and CPU saturation.
- **`sysmon.sh`**: Sets up background `atop` persistence and `inotify` file-system watchers.
- **`ec.pl`**: High-performance Perl engine for Exim stats. 
    - **Flags:** `--shours` (start hour window), `--days`, `--reseller` (filter by reseller), `--ips` (IMAP/POP IP tracking).

### 🩺 Health & Reporting
- **`health/monthly_report.sh`**: Generates a professional monthly digest. Includes rootkit scans (chkrootkit), login audits, and disk usage deltas.
- **`adlog.sh`**: Interactive log menu with tailing support for all major service logs.
- **`httplogs.sh`**: Fast domain-specific tailer for Apache/Nginx error logs.
- **`disk_analyzer.sh`**: Scans the root filesystem for the top 20 largest directories and files.

### 🧪 Load Testing
- **`stress_test.sh`**: Simulates HTTP load benchmarks. Iterates through URL lists with varied User-Agents to verify WAF/Rate-limit resilience.

---

## 🛡️ [4] Security & Forensics Module (`/security`)

### 🧱 System Policy
- **`hardening.sh`**: Implements the "Goshield Core" baseline. Installs `chkrootkit`, configures `CSF`, secures SSH (port/root login), and hardens PHP/Nginx/Apache.
- **`portsetup.sh`**: Interactive or automated firewall port setup for CentOS and Ubuntu stacks.

### 🔍 Threat Detection
- **`icmaldet.sh`**: Automates Linux Malware Detect (LMD) workflows. Runs deep scans in the background via `screen` and emails reports.
- **`spamcheck.sh`**: SRE script for identifying outgoing spam bursts. Tracks mail volume by user and date window.
- **`whitelist.sh`**: Simplified delisting for trusted IPs across the entire firewall stack.
- **`abuse_report.sh`**: Incident evidence collection. Packages logs/cPanel data, syncs via `rsync` to a remote server, and sets up protected access URLs.

---
**Standardized for Resilience.** Built by Nihar.
