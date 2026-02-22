# 📖 Exhaustive Operational Manual: Unified Ops Core

The definitive field guide to every script in this library. Intended for SREs who need full technical transparency of the automation stack before running anything.

> [!IMPORTANT]
> All scripts require **operator input** — domain names, IP addresses, file paths — to function. Always read the script before first use on a production system.

---

## 🏥 Primary Triage Tools

These are the first tools opened during an active incident.

---

### `automation/maintenance_menu.sh` — Primary Triage Hub

An interactive menu-driven command center for incident triage. Use this as the starting point for any incident.

```bash
bash automation/maintenance_menu.sh
```

**Sub-menus available:**
- Log viewer (Apache, Exim, MySQL, System messages)
- Network diagnostics (ping, DNS, port status)
- File system search (`find` wrapper)
- Service status checks

---

### `automation/swiss.sh` — Multi-Tool Utility

Interactive 13-option menu for the most common ad-hoc ops tasks. Auto-detects OS (`CentOS`/`Ubuntu`) and selects the correct firewall tool (`iptables` / `ufw`).

```bash
bash automation/swiss.sh
```

**Available options:**

| # | Function | Description |
|:---|:---|:---|
| 1 | Check and Open Port | Tests if a port is open; opens it in firewall if closed |
| 2 | Check and Delist IP | Checks if an IP is blocked; removes block if found |
| 3 | Processes on Port | `lsof -i :<PORT>` — shows what's listening on a specific port |
| 4 | All Listening Ports | `lsof -i -P -n \| grep LISTEN` |
| 5 | Search Files | `find <PATH> -name <PATTERN>` |
| 6 | Change Owner | `chown <OWNER> <FILE>` |
| 7 | Change Permissions | `chmod <MODE> <FILE>` |
| 8 | Running Processes | `ps aux` |
| 9 | Top CPU Processes | `top -b -n 1 \| head -20` |
| 10 | Email Logs | Exim queue count, failed Dovecot logins, per-sender volume, Exim ID trace |
| 11 | Apache Logs | Domain-specific Apache error log tail |
| 12 | View Logs | 7-category log viewer (Apache, Messages, FTP, MySQL, Outgoing mail, Incoming mail, Dovecot) |
| 13 | Exit | — |

---

## 🛡️ Security Module (`security/`)

---

### `security/hardening.sh` — cPanel/WHM Server Baseline

**One-shot hardening script** for a fresh cPanel/WHM server. Runs sequentially through ~16 hardening tasks. **Read carefully before running** — it makes permanent system changes.

```bash
bash security/hardening.sh
```

**Tasks performed (in order):**

| # | Task | Detail |
|:---|:---|:---|
| 1 | Install `chkrootkit` | Built from source in `/usr/local/src/`, installed to `/usr/local/chkrootkit/`. Weekly cron set up to email reports. |
| 2 | Disable unnecessary services | Stops and disables 15 services: `pcscd`, `portmap`, `nfslock`, `rpcidmapd`, `yum-updatesd`, `avahi-daemon`, `autofs`, `acpid`, `atd`, `gpm`, `haldaemon`, `hidd`, `irqbalance`, `xfs`, `cups`, `bluetooth`, `anacron` |
| 3 | Harden Apache | Sets `ServerTokens ProductOnly`, `ServerSignature Off`, `TraceEnable Off`, `FileETag None`. Rebuilds httpd config. |
| 4 | Disable PHP dangerous functions | Adds to `php.ini` `disable_functions`: `symlink`, `shell_exec`, `exec`, `proc_close`, `proc_open`, `popen`, `system`, `dl`, `passthru`, `escapeshellarg`, `escapeshellcmd` |
| 5 | PHP Fork Bomb Protection | Installs cPanel limits profile via `Cpanel::LoginProfile` |
| 6 | FTP Hardening | Disables anonymous FTP, disables root FTP logins, enables passive port range `30000–50000` in `pure-ftpd` |
| 7 | SSH Legal Banner | Appends unauthorized-access warning to `/etc/motd` |
| 8 | Disable Direct Root SSH | Creates `admin` wheel user with a 12-char random password (saved to `/root/.admin_pass`), sets `PermitRootLogin no` in `sshd_config` |
| 9 | Change SSH Port | Changes default port from `22` to `1243` in `sshd_config` |
| 10 | Update resolv.conf | Sets nameservers to `8.8.8.8` and `8.8.4.4` |
| 11 | Harden named.conf | Hides BIND version string (`version "[null]"`) |
| 12 | Install & Configure CSF | Installs `csf`, disables `TESTING` mode, updates SSH port to `1243`, enables `RESTRICT_SYSLOG`, enables `LF_SCRIPT_ALERT`, opens FTP passive ports `30000:50000`. Whitelists 6 support IPs. |
| 13 | Install ClamAV | Via cPanel RPM tools. Creates weekly cron to scan all accounts and email results to root. |
| 14 | Enable SSH Alerts | Appends to `/root/.bashrc` to email an alert on every root shell login. |
| 15 | Secure `/tmp` | Mounts `/tmp` with `noexec` via `/etc/fstab` entry. |
| 16 | Configure WHM Backups | Sets compressed daily backups (Mon/Wed/Sat), 4-day retention, saved to `/backup`. |

**Backups created for:** `sshd_config`, `php.ini`, `named.conf`, `csf.conf`, `motd`, `.bashrc`, `fstab`, WHM backup config, Apache local config.

---

### `security/spamcheck.sh` — Exim Spam Investigation

Interactive script for diagnosing outgoing spam and Exim queue abuse.

```bash
bash security/spamcheck.sh
```

**Actions:**
- Count current Exim queue depth
- List top senders by queue volume
- Flush all queued mail from a specific sender address
- Check delivery status by Exim message ID
- Search mail logs for a specific sender or domain

---

### `security/abuse_report.sh` — Abuse Evidence Collector

Collects domain-specific evidence into a package for abuse reporting.

```bash
bash security/abuse_report.sh
# Prompts for: domain name, output destination
```

**Collects:** Apache domain logs, Exim logs filtered by domain, cPanel account data.

---

### `security/icmaldet.sh` — ImunifyAV / Maldet Scan

Triggers a Linux Malware Detect (LMD) scan on a specified path, runs it in a `screen` session (non-blocking), and emails the report to root.

```bash
bash security/icmaldet.sh
# Prompts for: target scan path
```

---

### `security/whitelist.sh` — CSF IP Whitelist

Adds an IP to CSF's `csf.allow` and the cPHulk whitelist.

```bash
bash security/whitelist.sh <IP_ADDRESS>
```

---

### `security/portsetup.sh` — Quick Port Management

Opens a specific TCP port in `CSF` or `iptables` based on detected OS.

```bash
bash security/portsetup.sh <PORT>
```

---

## 🛰️ Monitoring Module (`monitoring/`)

---

### `monitoring/plesk_health.sh` — Full Plesk Stack Diagnostic

Comprehensive health diagnostic for Plesk-managed servers. Reports on all major service layers in one run.

```bash
bash monitoring/plesk_health.sh
```

**Report sections:**
- CPU load, memory pressure, uptime
- Plesk service status (`sw-cp-server`, `psa-dns`, `nginx`, `php-fpm`)
- MySQL connectivity and slow query count
- Apache/Nginx error log scan for recent errors
- Network socket state summary
- Disk usage by partition

---

### `monitoring/cpustats.sh` — CPU & I/O Monitoring

Real-time CPU breakdown with I/O wait highlighting. Critical for diagnosing disk-bound load spikes.

```bash
bash monitoring/cpustats.sh
```

**Displays:**
- Per-core CPU utilization
- I/O wait percentage (highlighted if high)
- System vs. user CPU split
- Memory and swap pressure

---

### `monitoring/sysmon.sh` — Live System Monitor

Rolling display of CPU, RAM, and load averages with continuous updates.

```bash
bash monitoring/sysmon.sh
```

---

### `monitoring/disk_analyzer.sh` — Disk Usage Report

Scans from the root filesystem down and reports the top directories by size.

```bash
bash monitoring/disk_analyzer.sh
```

**Output:** Top 20 directories and files by disk usage (using `du` and `sort`).

---

### `monitoring/adlog.sh` — Apache Domain Log Analysis

Interactive Apache log viewer with pattern matching and tail support.

```bash
bash monitoring/adlog.sh
# Prompts for: domain name, search pattern
```

---

### `monitoring/httplogs.sh` — HTTP Log Tail

Quick tail of Apache/Nginx error logs for a specific domain.

```bash
bash monitoring/httplogs.sh <DOMAIN>
```

---

### `monitoring/stress_test.sh` — Load Generator

Generates HTTP load against a target URL for service validation. Uses `curl` in a loop.

```bash
bash monitoring/stress_test.sh <URL> <REQUESTS>
```

**Use cases:** Validate rate limiting, test WAF rules, verify service recovery after restart.

---

### `monitoring/ec.pl` — Exim Log Analyzer (Legacy Perl)

High-performance Perl-based Exim stats engine. Superseded by `ops-cli email` for new deployments but retained for servers without Go.

```bash
perl monitoring/ec.pl [options]
```

| Flag | Description |
|:---|:---|
| `--shours <N>` | Limit analysis to the last N hours |
| `--days <N>` | Limit analysis to the last N days |
| `--reseller <NAME>` | Filter output by reseller name |
| `--ips` | Include IMAP/POP IP tracking |

---

## 🏗️ Automation Module (`automation/`)

---

### `automation/optimize.sh` — Apache & MySQL Performance Tuning

Calculates and optionally applies optimal Apache and MySQL settings based on available system RAM.

```bash
bash automation/optimize.sh
```

**Calculations:**
- `MaxRequestWorkers` = `floor((RAM_MB - 2048) / 60)` (reserves 2 GB for OS + other services, assumes ~60 MB per Apache worker)
- `innodb_buffer_pool_size` = `256M` for servers < 2 GB RAM, else `512M`

The script outputs the recommended values and prompts before writing to config files.

---

### `automation/maxworker.sh` — Apache Worker Calculator

Standalone version of the Apache `MaxRequestWorkers` calculator, targeted at memory-constrained VPS servers.

```bash
bash automation/maxworker.sh
```

---

### `automation/log_fixer.sh` — Disk-Full Rescue

Emergency tool for when a server has run out of disk space due to runaway log files.

```bash
bash automation/log_fixer.sh
```

**Actions:**
1. Identifies the largest log files in `/var/log/`
2. Truncates (does not delete) oversized logs using `> file` or `truncate`
3. Fixes ownership (`root:root`) and permissions (`640`) on log files
4. Restarts `rsyslog` / `syslog` if truncated

---

### `automation/permfix.sh` — Bulk Permission Correction

Corrects file and directory permissions across cPanel home directories to standard values.

```bash
bash automation/permfix.sh
```

Sets: Directories → `755`, Files → `644`

---

### `automation/mailish.sh` — Exim Queue Audit

Lightweight Exim mail queue investigator. Summarizes queue depth, top senders, and Dovecot login failures.

```bash
bash automation/mailish.sh
```

---

### `automation/zbxsetup.sh` — Zabbix Agent Deployment

Automated Zabbix Agent 2 deployment on a new server.

```bash
bash automation/zbxsetup.sh
```

**Steps performed:** Adds Zabbix repo, installs `zabbix-agent2`, configures server address, opens firewall port `10050`, enables and starts the service.

---

### `automation/porta.sh` — Port Auditor

Checks whether a specified port is open/closed and optionally opens it.

```bash
bash automation/porta.sh <PORT>
```

---

### `automation/sslrewrite.sh` — HTTPS Rewrite Rule Generator

Generates `RewriteCond` / `RewriteRule` directives for `.htaccess` to enforce HTTPS redirection.

```bash
bash automation/sslrewrite.sh <DOMAIN>
```

---

### `automation/dbim.sh` — Database Import

Non-interactive MySQL database import from a `.sql` file.

```bash
bash automation/dbim.sh <DATABASE> <SQL_FILE>
```

---

### `automation/wordpressfiles.sh` — WordPress File Utility

WordPress-specific automation for post-migration tasks: database import validation, `.htaccess` regeneration, and file permission reset for WP directories.

```bash
bash automation/wordpressfiles.sh
```

---

## 🚀 ops-cli Go Engine

For precision forensics, automated incident response, and TCP observability that requires parallel execution and mathematical analysis, use the Go engine.

```bash
# Build
go build -o ops-cli ./Go/ops-cli/

# Quick examples
./ops-cli system
./ops-cli forensics scan --path /home --quarantine /root/quarantine
./ops-cli response --dry-run=false
./ops-cli monitor thundering --threshold 200
```

→ **[Full ops-cli Command Reference with all flags and exact thresholds](./Go/ops-cli/Usage.md)**

---

**Standardized for Resilience. Optimized for the Edge.**
*Maintained by Nihar.* 🛡️✨
