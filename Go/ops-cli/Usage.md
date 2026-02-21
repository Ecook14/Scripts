# �️ ops-cli: Professional Command Reference

`ops-cli` is a high-alpha infrastructure automation tool. This guide provides a granular breakdown of every command, flag, and option available in the Go engine.

---

## 🌐 Global Options
These flags are available on **all** commands and sub-commands.

| Flag | Shorthand | Type | Default | Description |
| :--- | :--- | :--- | :--- | :--- |
| `--json` | N/A | bool | `false` | Output results in structured JSON format for automation/SIEM integration. |
| `--help` | `-h` | N/A | N/A | Display help information for the current command. |

---

## 🧠 [1] Incident Engine (`response`)
Assisted anomaly detection and remediation.

**Usage:** `ops-cli response [flags]`

| Flag | Type | Default | Description |
| :--- | :--- | :--- | :--- |
| `--dry-run` | bool | `true` | If true, logs anomalies without taking action. Set to `false` to execute remediation utilities. |

**Example:**
```bash
# Detect and remediate system anomalies (MySQL/Apache downtime, OOM)
ops-cli response --dry-run=false
```

---

## 🛡️ [2] Forensics Engine (`forensics`)
Architectural auditing and malware mitigation.

**Usage:** `ops-cli forensics [sub-command] [flags]`

**Global Forensics Flags:**
| Flag | Shorthand | Default | Description |
| :--- | :--- | :--- | :--- |
| `--path` | `-p` | `.` | Target directory to analyze. |

### 🔍 `scan` (Malware Signature Scan)
| Flag | Type | Default | Description |
| :--- | :--- | :--- | :--- |
| `--quarantine`| string | `""` | Move malicious files to this directory. |

**Example:**
```bash
# Scan for malware in /var/www and isolate results
ops-cli forensics scan --path /var/www --quarantine /root/forensics_quarantine
```

### 🕰️ `timeline` (Modification audit)
| Flag | Shorthand | Default | Description |
| :--- | :--- | :--- | :--- |
| `--since` | `-t` | `24h` | Time window (e.g. `1h`, `30m`, `48h`). |

### 🚪 `persistence` (Shell/Cron audit)
Audits files like `/etc/profile`, `~/.bashrc`, and system/user cronjobs for anomalies. No specific flags.

### ♻️ `restore` (Quarantine Management)
| Flag | Type | Default | Description |
| :--- | :--- | :--- | :--- |
| `--file` | string | `""` | Specific `.quarantine` file to restore. |
| `--all` | bool | `false` | Restore all files in the quarantine directory. |
| `--quarantine`| string | `""` | Path to the quarantine directory where files are stored. |

---

## 🛰️ [3] Monitor Engine (`monitor`)
TCP stack observability and metrics.

**Usage:** `ops-cli monitor [sub-command] [flags]`

### 🚥 `connections` (Socket Statistics)
Reports total connections and counts by state (ESTABLISHED, SYN_RECV, etc.).

### 🚥 `backlog` (Listen Queue Health)
Identifies ports with non-zero Rx/Tx queues indicating service saturation.

### � `thundering` (Herd Detection)
| Flag | Type | Default | Description |
| :--- | :--- | :--- | :--- |
| `--threshold` | int | `100` | SYN_RECV count to trigger a thundering herd warning. |

### 📊 `serve` (Prometheus Exporter)
| Flag | Type | Default | Description |
| :--- | :--- | :--- | :--- |
| `--addr` | string | `:9090` | Address/Port to serve Prometheus metrics on. |

---

## 💾 [4] Disk Engine (`disk`)
O(K) constant-memory filesystem analysis using a Min-Heap.

**Usage:** `ops-cli disk [paths...] [flags]`

| Flag | Shorthand | Default | Description |
| :--- | :--- | :--- | :--- |
| `--top` | `-n` | `5` | Number of top-consumers (files/dirs) to report. |
| `--min-size` | N/A | `1` | Minimum size threshold in MB for reporting. |

**Example:**
```bash
# Find the top 10 large files (>100MB) in /home
ops-cli disk /home --top 10 --min-size 100
```

---

## 🔍 [5] Log Engine (`logs`)
High-speed streaming search across cross-stack logs.

**Usage:** `ops-cli logs [module] [flags]`
Modules: `apache`, `exim`, `mysql`, `system`.

| Flag | Shorthand | Default | Description |
| :--- | :--- | :--- | :--- |
| `--query` | `-q` | `""` | **(Required)** The string or pattern to search for. |
| `--limit` | `-l` | `50` | Maximum number of matches to return. |

**Example:**
```bash
# High-speed search in Apache logs for segmentation faults
ops-cli logs apache --query "segmentation fault" --limit 10
```

---

## 🌐 [6] Network Engine (`network`)
Unified firewall management across CSF, Firewalld, and IPTables.

**Usage:** `ops-cli network [check|unblock] --ip [IP]`

| Flag | Type | Default | Description |
| :--- | :--- | :--- | :--- |
| `--ip` | string | `""` | **(Required)** Target IP address for check/unblock operations. |

**Example:**
```bash
# Check if an IP is blocked across all supported firewalls
ops-cli network check --ip 1.2.3.4
```

---

## 📧 [7] Email Engine (`email`)
High-speed Exim mail log analyzer and traffic summary tool.

**Usage:** `ops-cli email`

**Example:**
```bash
# Generate a traffic summary and identify top 10 senders from Exim logs
ops-cli email
```

---

## ⚖️ [8] Optimization Engine (`optimize`)
Calculates optimal Apache and MySQL settings based on detected system memory. No specific flags.

---

## 🔐 [9] Security Engine (`security`)
Server hardening and abuse investigation.

### 🛡️ `harden` (Hardening Scan)
Checks system configurations (SSH, FTP) against security baselines.

### 📦 `abuse` (Evidence Collector)
Packages relevant logs for a domain into a zip file for abuse reporting.
**Usage:** `ops-cli security abuse [DOMAIN]`

---

## 🖥️ [10] System Engine (`system`)
Real-time diagnostics for CPU, memory, and load averages. No specific flags.

---

## ⚡ Quick Reference: Practical Patterns

### Incident Response Automation
```bash
# Run a silent audit and output JSON for integration
ops-cli response --json > health_report.json
```

### Forensic Deep-Dive
```bash
# Scan for malware in /var/www and isolate results
ops-cli forensics scan --path /var/www --quarantine /root/forensics_quarantine
```

### Resource Management
```bash
# Find the top 10 large files in /home
ops-cli disk /home --top 10 --min-size 100
```

### High-Speed Log Search
```bash
# Search Apache logs for a specific error
ops-cli logs apache --query "segmentation fault" --limit 10
```

---
**Standardized for High-Performance Infrastructure.** Built by Nihar.
> [!NOTE]
> All `ops-cli` operations are operator-centric. The engine provides the speed and precision, but you provide the parameters and final validation.
