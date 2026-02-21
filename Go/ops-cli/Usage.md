# 🛰️ ops-cli: Professional Command Reference

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
Automated anomaly detection and self-healing.

**Usage:** `ops-cli response [flags]`

| Flag | Type | Default | Description |
| :--- | :--- | :--- | :--- |
| `--dry-run` | bool | `true` | If true, logs anomalies without taking action. Set to `false` to execute remediations. |

**Example:**
```bash
# Detect and fix MySQL/Apache downtime automatically
ops-cli response --dry-run=false
```

---

## 🛡️ [2] Forensics Engine (`forensics`)
Architectural auditing and malware mitigation.

**Usage:** `ops-cli forensics [sub-command] [flags]`

### 🔍 `scan` (Malware Signature Scan)
| Flag | Shorthand | Default | Description |
| :--- | :--- | :--- | :--- |
| `--path` | `-p` | `.` | Target directory to scan for signatures and high entropy. |
| `--quarantine`| N/A | `""` | Directory to move malicious files to. |

### 🕰️ `timeline` (Modification audit)
| Flag | Shorthand | Default | Description |
| :--- | :--- | :--- | :--- |
| `--path` | `-p` | `.` | Target directory to analyze. |
| `--since` | `-t` | `24h` | Time window (e.g. `1h`, `30m`, `48h`). |

### ♻️ `restore` (Quarantine Management)
| Flag | Type | Default | Description |
| :--- | :--- | :--- | :--- |
| `--file` | string | `""` | Specific `.quarantine` file to restore. |
| `--all` | bool | `false` | Restore all files in the quarantine directory. |
| `--quarantine`| string | `""` | Path to the quarantine directory. |

---

## 🛰️ [3] Monitor Engine (`monitor`)
TCP stack observability and metrics.

**Usage:** `ops-cli monitor [sub-command] [flags]`

### 🚥 `thundering` (Herd Detection)
| Flag | Type | Default | Description |
| :--- | :--- | :--- | :--- |
| `--threshold` | int | `100` | SYN_RECV count to trigger a thundering herd warning. |

### 📊 `serve` (Prometheus Exporter)
| Flag | Type | Default | Description |
| :--- | :--- | :--- | :--- |
| `--addr` | string | `:9090` | Address/Port to serve Prometheus metrics on. |

---

## 💾 [4] Disk Engine (`disk`)
O(K) constant-memory filesystem analysis.

**Usage:** `ops-cli disk [paths...] [flags]`

| Flag | Shorthand | Default | Description |
| :--- | :--- | :--- | :--- |
| `--top` | `-n` | `5` | Number of top-consumers (files/dirs) to report. |
| `--min-size` | N/A | `1` | Minimum size threshold in MB for reporting. |

---

## 🔍 [5] Log Engine (`logs`)
High-speed streaming search across cross-stack logs.

**Usage:** `ops-cli logs [module] [flags]`
Modules: `apache`, `exim`, `mysql`, `system`.

| Flag | Shorthand | Default | Description |
| :--- | :--- | :--- | :--- |
| `--query` | `-q` | `""` | **(Required)** The string or pattern to search for. |
| `--limit` | `-l` | `50` | Maximum number of matches to return. |

---

## 🌐 [6] Network Engine (`network`)
Unified firewall management.

**Usage:** `ops-cli network [sub-command] [flags]`

| Flag | Type | Default | Description |
| :--- | :--- | :--- | :--- |
| `--ip` | string | `""` | **(Required)** Target IP address for check/unblock operations. |

---

## ⚡ Quick Reference: Practical Patterns

### Incident Response Automation
```bash
# Run a silent audit and output JSON to a file
ops-cli response --json > health_report.json
```

### Forensic Deep-Dive
```bash
# Scan for malware in /tmp and isolate anything found
ops-cli forensics scan --path /tmp --quarantine /root/forensics_quarantine
```

### Resource Management
```bash
# Find the top 10 files larger than 50MB in /var
ops-cli disk /var --top 10 --min-size 50
```

### High-Speed Log Search
```bash
# Search Exim logs for a specific sender in the last 50 matches
ops-cli logs exim --query "user@domain.com" --limit 50
```

---
**Maintained by Nihar** | Engineering Excellence for Infrastructure. 🛡️✨
