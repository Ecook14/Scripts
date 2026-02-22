# 🛰️ ops-cli: High-Performance Infrastructure Engineering

`ops-cli` is a statically-linked Go binary that replaces a suite of shell script dependencies with a unified, zero-dependency platform for server diagnostics, forensics, and automated incident response.

> **Target OS:** Linux. Commands that read `/proc` — `system`, `disk`, `monitor`, `forensics`, `response` — require a Linux host to run.
> **Format:** Every command supports `--json` for structured output suitable for piping into log aggregators or CI/CD pipelines.

```bash
# Build
go build -o ops-cli .

# Run (defaults to a help message)
./ops-cli --help
```

---

## Architecture: 6 Internal Engines

The tool is built as a [Cobra](https://github.com/spf13/cobra) CLI layered over six independent internal packages.

```
ops-cli/
├── cmd/           # Cobra command layer (user-facing)
│   ├── system.go
│   ├── disk.go
│   ├── logs.go
│   ├── network.go
│   ├── security.go
│   ├── forensics.go
│   ├── monitor.go
│   ├── optimize.go
│   ├── email.go
│   └── response.go
└── internal/      # Pure-Go engine layer (no external deps)
    ├── disk/
    ├── forensics/
    ├── incident/
    ├── logs/
    ├── monitor/
    └── network/
```

---

## Command Reference

### `system` — Live Health Snapshot

Reads `/proc/meminfo` and `/proc/loadavg` directly. No syscall wrappers, no CGO.

```bash
./ops-cli system
./ops-cli system --json
```

**Output:** OS, architecture, CPU count, load average (Linux), memory used/total in GB.

> Memory is derived from `MemAvailable` (preferred) then `MemFree` as a fallback from `/proc/meminfo`.

---

### `disk [paths...]` — Disk Usage Analysis

Walks one or more directory paths and reports the largest files and directories.

| Flag | Default | Description |
|---|---|---|
| `--top`, `-n` | `5` | Number of top items to display |
| `--min-size` | `1` | Minimum file size to include (MB) |

```bash
./ops-cli disk /var/log /home --top 10 --min-size 50
./ops-cli disk --json
```

---

### `logs` — Unified Log Search

Streams log files line-by-line using `bufio.Scanner` for low memory pressure on multi-GB logs.

| Subcommand | Log File |
|---|---|
| `logs apache` | `/usr/local/apache/logs/error_log` |
| `logs exim` | `/var/log/exim_mainlog` |
| `logs mysql` | `/var/log/mysqld.log` |
| `logs system` | `/var/log/messages` (or `/var/log/syslog`) |

| Flag | Default | Description |
|---|---|---|
| `--query`, `-q` | *(required)* | Search string |
| `--limit`, `-l` | `50` | Maximum number of results |

```bash
./ops-cli logs apache --query "PHP Fatal" --limit 20
./ops-cli logs exim --query "rejected" --json
```

---

### `network` — Firewall Management

Detects and manages blocked IPs across `CSF`, `Firewalld`, and `IPTables`.

| Flag | Description |
|---|---|
| `--ip` | Target IP address (required) |

```bash
./ops-cli network check --ip 1.2.3.4
./ops-cli network unblock --ip 1.2.3.4
```

`unblock` first calls `check` to identify the active firewall, then removes the rule from the correct backend.

---

### `security` — Auditing & Evidence Packaging

#### `security harden`
Checks two critical config settings without modifying the system:

| Check | File | Expected Pattern |
|---|---|---|
| SSH Root Login | `/etc/ssh/sshd_config` | `PermitRootLogin no` |
| FTP Anonymous | `/etc/pure-ftpd/pure-ftpd.conf` | `NoAnonymous yes` |

```bash
./ops-cli security harden
# [PASS] SSH Root Login: /etc/ssh/sshd_config
# [FAIL] FTP Anonymous: /etc/pure-ftpd/pure-ftpd.conf
```

#### `security abuse [DOMAIN]`
Packages log evidence for a domain into a timestamped `.zip` file using Go's native `archive/zip`. No `zip` binary dependency.

Collects:
- `/var/log/messages`
- `/var/log/exim_mainlog`
- `/var/log/apache2/domlogs/<DOMAIN>`

```bash
./ops-cli security abuse example.com
# Creates: example.com_abuse_1708001234.zip
```

---

### `forensics` — Malware Mitigation Suite

#### `forensics scan`
Runs a **parallel 8-worker** signature scan across a directory tree.

| Flag | Default | Description |
|---|---|---|
| `--path`, `-p` | `.` | Root directory to scan |
| `--quarantine` | *(none)* | If set, moves detections to this directory |

**Two-Stage Detection:**

1. **Signature Matching** — 12 built-in patterns checked line-by-line against every file:

   | Signature Name | Pattern |
   |---|---|
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

2. **Shannon Entropy Analysis** — Applied to the first **4 KB** of any file that passes signature checks. Files with entropy **> 5.5** are flagged as `High Entropy (X.XX)`, indicating encrypted/obfuscated payloads.

   > Scale: `0.0` = no randomness, `8.0` = fully random. Normal PHP/text code scores `< 5.0`. Encrypted data or compressed blobs score `> 7.0`.

3. **Immutability Check** — For each detection, checks `lsattr` for `+i` (immutable) flag. Runs `chattr -i` to unlock the file before quarantine.

```bash
./ops-cli forensics scan --path /home/user/public_html --quarantine /root/quarantine
./ops-cli forensics scan --json
```

Exits with code `1` if any detections are found (CI/CD compatible).

#### `forensics timeline`

Reports all files modified within a time window in a directory.

| Flag | Default | Description |
|---|---|---|
| `--path`, `-p` | `.` | Root directory |
| `--since`, `-t` | `24h` | Duration window (Go format: `24h`, `2h`, `30m`) |

```bash
./ops-cli forensics timeline --path /home --since 6h
```

#### `forensics persistence`

Audits shell init files and crontabs for persistence anomalies. Checks the current user's home directory.

**Files Scanned:** `/etc/profile`, `/etc/bash.bashrc`, `~/.bashrc`, `~/.profile`, `~/.bash_profile`, `~/.bash_logout`

**Cron Directories Scanned:** `/etc/crontab`, `/etc/cron.d/`, `/etc/cron.daily/`, `/etc/cron.hourly/`, `/var/spool/cron/crontabs/`

**Anomaly Types Detected:**

| Anomaly | Pattern |
|---|---|
| Command Hijack (Alias) | `alias ls=`, `alias sudo=`, etc. (10 common commands) |
| Remote Script Execution | `curl ... \| bash`, `wget ... \| sh` |
| Hidden path/memory execution | `/. `, `/.hidden`, `/dev/shm` paths |
| Background Persistence | Lines ending in `&` |
| Cron: Remote Script/Download | `curl`/`wget` + `http` + `\| bash` in cron |
| Cron: Suspicious exec path | `/tmp`, `/dev/shm` in cron commands |
| Cron: Encoded/Inline payload | `base64`, `python -c`, `perl -e`, `php -r` in cron |

```bash
./ops-cli forensics persistence
./ops-cli forensics persistence --json
```

Exits with code `1` if anomalies are found.

#### `forensics restore`

Restores quarantined files using JSON sidecar metadata (preserves original path and permissions).

```bash
# Restore a single file
./ops-cli forensics restore --file /root/quarantine/1708001234_shell.php.quarantine

# Restore all files in a quarantine directory
./ops-cli forensics restore --all --quarantine /root/quarantine
```

---

### `monitor` — TCP Stack Observability

Parses `/proc/net/tcp` directly (little-endian hex decoding) with no external dependencies.

#### `monitor connections`
Shows total connection count and a breakdown by TCP state.

```bash
./ops-cli monitor connections
./ops-cli monitor connections --json
```

#### `monitor backlog`
Lists ports with non-zero Rx/Tx queues (indicating listen queue pressure).

```bash
./ops-cli monitor backlog
```

#### `monitor thundering`
Detects thundering herd by counting `SYN_RECV` state connections.

| Flag | Default | Description |
|---|---|---|
| `--threshold` | `100` | Alert if `SYN_RECV` count exceeds this |

```bash
./ops-cli monitor thundering --threshold 200
```

#### `monitor serve`
Starts a zero-dependency Prometheus-compatible metrics exporter that continuously polls TCP state.

| Flag | Default | Description |
|---|---|---|
| `--addr` | `:9090` | Listen address for the metrics endpoint |

**Exported Metrics:**
- `tcp_connections_total` — total socket count
- `tcp_state_<state>` — per-state counts (e.g., `tcp_state_established`)

```bash
./ops-cli monitor serve --addr :9091
```

---

### `optimize` — Performance Tuning

Calculates optimal settings based on actual available RAM (read from `/proc/meminfo`).

```bash
./ops-cli optimize
```

**Formulas used:**

| Setting | Formula |
|---|---|
| Apache `MaxRequestWorkers` | `floor((RAM_MB - 2048) / 60)` |
| MySQL `innodb_buffer_pool_size` | `256M` if RAM < 2048 MB, else `512M` |

> Defaults to 4096 MB RAM if `/proc/meminfo` is unavailable (non-Linux).

---

### `email` — Exim Log Analyzer

A Go-native replacement for `ec.pl`. Parses `/var/log/exim_mainlog` to produce a traffic summary.

```bash
./ops-cli email
```

Detects message arrival events via the `<=` marker in Exim log lines and outputs:
- Total emails processed
- Top 10 senders by volume

---

### `response` — Automated Incident Response

Runs a set of health checks and optionally executes remediations. **Defaults to `--dry-run=true`** for safety.

| Flag | Default | Description |
|---|---|---|
| `--dry-run` | `true` | Simulate remediations without executing |

**Checks Executed:**

| Check | Logic | Remediation |
|---|---|---|
| `LoadCheck` | 1-min load avg from `/proc/loadavg` > **5.0** | None |
| `ServiceCheck: httpd` | TCP connect to `localhost:80` (2s timeout) | `systemctl restart httpd` |
| `ServiceCheck: mysql` | TCP connect to `localhost:3306` (2s timeout) | `systemctl restart mysql` |
| `MinerCheck` | Scans all `/proc/<PID>/cmdline` for 9 crypto signatures | `SIGKILL` the PID |
| `OOMCheck` | Scans syslog/kern.log for `Out of memory` or `invoked oom-killer` | None |
| `KillerProcessCheck` | Scans `/proc/<PID>/comm` for `oomd`, `earlyoom`, `monit`, `watchdog` | None (informational) |

```bash
# Safe audit (dry-run, default)
./ops-cli response

# Live execution of remediations
./ops-cli response --dry-run=false

# JSON output for monitoring system integration
./ops-cli response --json
```

Exits with code `1` if any incidents are detected.

---

## Global Flags

| Flag | Description |
|---|---|
| `--json` | Output results as structured JSON (all commands) |
| `--help` | Display help for any command |

---

## Design Principles

- **Zero External Dependencies**: Only the standard library + `github.com/spf13/cobra`. No `ps`, `netstat`, `awk`, `grep`, or other shell utilities are exec'd.
- **Context Propagation**: `SIGINT` (Ctrl+C) and `SIGTERM` are captured at startup and propagated via `context.Context` to all I/O operations and scan loops.
- **Structured Logging**: All operational output goes to `stderr` via `log/slog` (JSON format). Command results go to `stdout`, making pipe-friendly automation clean.
- **CI/CD Exit Codes**: `forensics scan`, `forensics persistence`, and `response` exit `1` on detections, making them pipeline-native.

---

**Built by Nihar.** 🛡️✨
