# 🛡️ Unified Ops Core: Built for the Edge

![Go](https://img.shields.io/badge/go-%2300ADD8.svg?style=for-the-badge&logo=go&logoColor=white)
![Linux](https://img.shields.io/badge/Linux-FCC624?style=for-the-badge&logo=linux&logoColor=black)
![Security](https://img.shields.io/badge/Security-4B0082?style=for-the-badge&logo=crowdstrike&logoColor=white)

A library of production-hardened tools for Linux server operations. It combines battle-tested Bash scripts for quick triage with a Go-powered engine (`ops-cli`) for precision forensics and incident response.

> [!IMPORTANT]
> These are tools for humans, not autonomous bots. They require precise operator input — IPs, paths, domains — to function. No action is taken without your intent.

---

## Repository Map

```
Scripts/
├── automation/          # 19 scripts — server maintenance and optimization
├── monitoring/          # 11 scripts + monitoring/health/ — observability
├── security/            # 10 scripts — hardening and incident response
├── Go/ops-cli/          # Go engine (source; no binary tracked)
├── docs/                # design notes + legacy/ (PowerShell + shell)
├── monetization.sh
├── README.md
└── Usage.md
```

---

## 🏗️ Onion Layer Defense

```
    Alert[Monitoring Alert] --> Triage[Triage: maintenance_menu.sh / swiss.sh]
    Triage -->|Security Events| L1[security/]
    Triage -->|Resource Pressure| L2[monitoring/]
    Triage -->|System Repair| L3[automation/]
    L1/L2/L3 --> Engine[ops-cli: Forensics & Incident Response]
    Engine --> Report[Operational Summary]
```

---

## 🛰️ Layer 2: The Heartbeat (`monitoring/`)

| Script | Purpose |
|---|---|
| `plesk_health.sh` | Full-spectrum Plesk + server health report |
| `cpustats.sh` | Per-core CPU with I/O-wait highlighting |
| `sysmon.sh` | High-load monitoring with Atop and Inotify |
| `monitoratop.sh` | Atop history logging + CPU/RAM/disk spike attribution |
| `disk_analyzer.sh` | Disk usage ranked by directory size |
| `adlog.sh` | Log viewer for system, web, and mail |
| `httplogs.sh` | Apache access/error log tailer |
| `stress_test.sh` | `ab`/`curl` load generation |
| `cpharded.sh` | v2.2.3 cPanel/EA4/Zabbix master setup (see Layer 1) |
| `attacker.pl` | Per-port connection counts; flags known CDN/monitor ranges |
| `ec.pl` | Legacy Perl Exim log analyzer (superseded by `ops-cli email`) |
| `health/monthly_report.sh` | Monthly health/security/integrity report |

---

## 🛡️ Layer 1: The Perimeter (`security/`)

| Script | Purpose |
|---|---|
| `hardening.sh` | cPanel/WHM baseline: chkrootkit, ClamAV, CSF, disables services, `ServerTokens ProductOnly`, disables dangerous PHP functions, hardens `pure-ftpd`, moves SSH to port 1243, hardens `/tmp`. Also runs `rm -rf /usr/local/src/*` and restarts sshd/named/crond — review before use. |
| `cphard.sh` | v2.1.0 cPanel provisioning master: nameservers, CSF, SSH/PHP/MySQL hardening, EasyApache 4, ImunifyAV, Zabbix Agent 2. Idempotent. |
| `cpanel_audit.sh` | Forensic scan for cPanel/WHM compromise (CVE-2026-41940) |
| `ioc_check.sh` | Scans cPanel/WHM session files for compromise indicators |
| `Scanner.sh` | Broad sweep: suspicious SSH logins, root accounts, rootkit traces |
| `spamcheck.sh` | Exim queue investigation and spam reporting |
| `abuse_report.sh` | Domain abuse evidence collection |
| `icmaldet.sh` | Imunify360 / maldet scan wrapper |
| `whitelist.sh` | CSF firewall IP whitelist management |
| `portsetup.sh` | TCP port open via CSF/iptables (CentOS + Ubuntu) |

---

## 🏥 Layer 3: The Medic (`automation/`)

| Script | Purpose |
|---|---|
| `maintenance_menu.sh` | Primary incident triage hub (25 prompts) |
| `swiss.sh` | 13-option menu: ports, IP delist, processes, logs, permissions |
| `optimize.sh` | Apache `MaxRequestWorkers` + MySQL buffer pool from RAM |
| `maxworker.sh` | Standalone Apache worker calculator |
| `log_fixer.sh` | Disk-full rescue: recreate and fix log file permissions |
| `permfix.sh` | Bulk cPanel home-directory permission correction |
| `mailish.sh` | Exim queue manager and login auditor |
| `zbxsetup.sh` | Zabbix Agent 2 install and registration |
| `porta.sh` | Port audit and open/close |
| `sslrewrite.sh` | HTTPS redirect rules in `.htaccess` |
| `dbim.sh` | MySQL database import |
| `wordpressfiles.sh` | WordPress database/config management |
| `wp-pass.sh` | Bulk WordPress password reset by domain (root) |
| `wp-triggers.sh` | WordPress install discovery + WP-CLI triggers (root) |
| `findfwd.sh` | Forwarded-email enumeration |
| `whitelist.sh` | ModSecurity rule-ID whitelisting (**not** firewall — distinct from `security/whitelist.sh`) |
| `enable_email.sh` / `disable_email.sh` | Toggle outbound mail per cPanel account |
| `process_analyser.sh` | Identify the script/plugin/PHP file behind hot processes |

---

## 🚀 Layer 4: The Engine (`Go/ops-cli/`)

A Go CLI (cobra) reading OS state from `/proc`. **Build from source — no binary is tracked in git.**

```bash
cd Go/ops-cli
go build -o ops-cli .
```

### Verified command surface

| Command | Flags | Behavior |
|---|---|---|
| `system` | `--json` | OS/arch, CPU count, `/proc/loadavg`, `/proc/meminfo`. Returns an error on non-Linux (memory needs `/proc`). |
| `optimize` | `--json` | Recommends Apache `MaxRequestWorkers` ((RAM−2048)/60, min 10) and MySQL `innodb_buffer_pool_size` (256M under 2GB, else **512M**). Advisory only — applies nothing. |
| `monitor connections` | `--json` | Parses `/proc/net/tcp` for total + per-state counts (IPv4 only; IPv6 not handled). |
| `monitor backlog` | `--json` | Lists ports with non-zero Rx/Tx queues. |
| `monitor thundering` | `--threshold int` (default 100) | Flags SYN_RECV counts above threshold. |
| `monitor serve` | `--addr` (default `:9090`) | Serves `ops_cli_*` metrics on `/metrics`. |
| `forensics scan` | `-p/--path`, `--quarantine` | Parallel signature scan (8 workers) + Shannon entropy (>5.5 over first 4KB). Clears `+i` on hits; optionally quarantines. **Exits 1 on findings.** |
| `forensics timeline` | `-p/--path`, `-t/--since` (default `24h`) | Lists files modified within the window. |
| `forensics persistence` | `-p/--path` | Audits `/etc/profile`, `/etc/bash.bashrc`, `~/.bashrc`, `.profile`, `.bash_profile`, `.bash_logout`, plus crontabs. **Exits 1 on findings.** |
| `forensics restore` | `--file`, `--all`, `--quarantine` | Restores quarantined files from JSON sidecars. |
| `response` | `--dry-run` (**default true**) | 6 checks: load >5.0, httpd:80, mysql:3306, miner processes, OOM log events, killer daemons. **Exits 1 when incidents are found**, dry-run or not. |
| `security harden` | — | Audits `PermitRootLogin no` and pure-ftpd `NoAnonymous yes`. Read-only. |
| `security abuse [DOMAIN]` | — | Zips `/var/log/messages`, `exim_mainlog`, and the domain's Apache domlog. |
| `logs apache\|exim\|mysql\|system` | `-q/--query`, `-l/--limit` (default 50) | Searches known log paths; case-insensitive substring. |
| `disk [paths...]` | `-n/--top` (default 5), `--min-size` MB | Top-N largest files and directories. |
| `network check\|unblock` | `--ip` | Checks/unblocks across CSF, Firewalld, iptables. `unblock` mutates firewall state. |
| `email` | `--json` | Parses `/var/log/exim_mainlog` for total volume + top 10 senders. |

### Known limitations (verified against the source)

- **`optimize` caps MySQL at 512M** regardless of RAM. The code comment itself notes modern practice is 50–70% of RAM. On a large host this under-provisions badly.
- **`forensics scan` flags its own source files.** The signature list matches bare strings like `stratum+tcp` and `eval(base64_decode`, so scanning `internal/` reports `miner_check.go` and `scanner.go` as malware. Expect false positives; the exit code 1 is not a reliable signal on its own.
- **IPv6 is unhandled** in `/proc/net/tcp` parsing (`/proc/net/tcp6` is never read).
- **Non-Linux memory stats are unimplemented** and return an error.
- **`response --dry-run=false` restarts services and `kill -9`s processes.** The dry-run default is a flag default, not a guarantee.
- **Logs output is JSON-formatted to stderr**, while `render()` writes plain text to stdout — mixed streams complicate piping.
- **No tests and no CI.** `go test ./...` has no test files to run; nothing in the repo builds on push.

---

## Design Philosophy

- **Zero-dependency shell core**: standard GNU utilities only (`awk`, `sed`, `grep`, `lsof`, `nc`).
- **Modular and self-contained**: each script drops onto any Linux server and runs.
- **Go engine for precision**: reads `/proc` directly; the only external dependency is `cobra`.
- **Human-led remediation**: destructive operations are dry-run or review-first by default.
- **Pipeline-native exit codes**: `forensics scan`, `forensics persistence`, and `response` exit 1 on detections.

---

**Standardized for Resilience. Optimized for the Edge.**
*Maintained by Nihar.* 🛡️✨