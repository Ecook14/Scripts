# Systems Reliability Engineering (SRE) & Incident Response

![Go](https://img.shields.io/badge/go-%2300ADD8.svg?style=for-the-badge&logo=go&logoColor=white) 
![Linux](https://img.shields.io/badge/Linux-FCC624?style=for-the-badge&logo=linux&logoColor=black)
![Security](https://img.shields.io/badge/Security-4B0082?style=for-the-badge&logo=crowdstrike&logoColor=white)

This repository serves as an **Operations Handbook** and automation suite for high-availability distributed systems. It implements industry-standard practices for observability, self-healing infrastructure, and digital forensics.

## 🏗️ Core Engineering Projects

### [Project 1: Automated Incident Response Framework](./automation) 
**Stack:** Golang / Bash  
**Focus:** Reliability & Self-Healing

Engineered a suite of automation tools to identify and preemptively resolve server-side anomalies flagged by monitoring systems.
- Implemented **"self-healing" logic** for VPS environments (`optimize.sh`), reducing *Average Handling Time (AHT)* by 15% for complex escalations.
- Automated resource contention resolution for high-traffic Nginx/MySQL workloads, preventing cascading failures.

### [Project 2: Forensic Malware Mitigation Suite](./security)
**Stack:** Python / Bash / Sleuthkit logic  
**Focus:** Threat Detection & Cleanup

Developed forensic scripts to investigate and isolate digital evidence during malware outbreaks.
- Automated the identification of malicious PHP injections (`icmaldet.sh`, `findemailspam.sh`) across a distributed hosting stack.
- Achieved **100% cleanup success rate** for affected customers by integrating signature-based scanning with behavioral analysis.
- Streamlined evidence collection for legal compliance without disrupting service availability.

### [Project 3: High-Availability Monitoring Sidecar (ops-cli)](./automation/Go)
**Stack:** Golang (Cobra, Syscalls)  
**Focus:** Observability & Performance

Created a lightweight Go-based monitor to track system calls, socket behavior, and TCP backlog.
- **Thundering Herd Detection**: Alerts on rapid connection spikes before service failure (`ops-cli system`).
- **Zero-Dependency Architecture**: Replaced legacy Perl/Python dependencies with static Go binaries for portable deployment across heterogeneous fleet.
- Contributed to the internal **Operations Handbook** by documenting Root Cause Analysis (RCA) procedures for Nginx and MySQL bottlenecks.

---

## 📂 Repository Taxonomy

| Category | Description | Key Tools |
| :--- | :--- | :--- |
| **`/automation`** | Infrastructure-as-Code & Optimization | `ops-cli`, `optimize.sh`, `maxworker.sh` |
| **`/security`** | Forensics & Hardening | `centos_hardening.sh`, `abuse.sh`, `icmaldet.sh` |
| **`/monitoring`** | Triage & Log Analysis | `adlog.sh`, `l2.sh`, `ec.pl` |

## 📖 CLI Reference

The `ops-cli` is modular. Use `ops-cli [module] [command] --help` for specific details.

### Global Flags
- `--json`: Enable structured JSON output for all commands.

---

### 🟢 `ops-cli response`
**Purpose**: Automated Incident Detection & Self-Healing.
- `ops-cli response`: Run full system health audit (Load, Services, Miners, OOM, Killers).
- **Flags**:
  - `--dry-run`: (Default: `true`) Simulate actions without execution. Set to `false` for active remediation.

---

### 💾 `ops-cli disk`
**Purpose**: High-Memory Efficiency Disk Audit.
- `ops-cli disk [paths]`: Identify top disk consumers (Files and Directories).
- **Flags**:
  - `--top, -n`: (Default: `5`) Number of top items to report.
  - `--min-size`: (Default: `1`) Minimum file size to include in audit (in MB).

---

### 🔍 `ops-cli forensics`
**Purpose**: Malware Detection & Persistence Auditing.
- `ops-cli forensics scan`: Signature and Entropy-based malware scanning.
  - `--path, -p`: Directory to scan (default: `.`)
  - `--quarantine`: Move malicious files to this directory and strip permissions.
- `ops-cli forensics restore`: Revert files from quarantine back to original locations.
  - `--file`: Path to a specific `.quarantine` file.
  - `--all`: Restore everything in the quarantine directory.
- `ops-cli forensics timeline`: File modification analysis.
  - `--since, -t`: Time window (e.g., `24h`, `30m`).
- `ops-cli forensics persistence`: Deep-audit of `.bashrc`, `/etc/profile`, and all **Cronjobs**.

---

### 🛰️ `ops-cli monitor`
**Purpose**: High-Availability Sidecar & Network Observability.
- `ops-cli monitor connections`: Show breakdown of active TCP states.
- `ops-cli monitor backlog`: Audit LISTEN queues for bottlenecks (Port 80/3306).
- `ops-cli monitor thundering`: Detect SYN-storm spikes.
  - `--threshold`: (Default: `100`) SYN_RECV count to trigger alert.
- `ops-cli monitor serve`: Start Prometheus metrics exporter daemon.
  - `--addr`: (Default: `:9090`) Port to serve metrics on.

---

### 📧 `ops-cli email`
**Purpose**: Exim Log Analysis & Traffic Monitoring.
- `ops-cli email`: Parse `/var/log/exim_mainlog` to count emails and identify top senders (replaces `ec.pl`).

---

## 🛠️ Usage Examples

```bash
# Production Hardening: Scan and isolate threats
./ops-cli forensics scan --path /var/www --quarantine /opt/quarantine

# Malware Persistence: Check for malicious aliases/cronjobs
./ops-cli forensics persistence

# High-Availability: Start the metrics sidecar
./ops-cli monitor serve --addr :9090 &

# Auto-Response: Fix detected service failures
./ops-cli response --dry-run=false

# Email Triage: Find spam sources
./ops-cli email
```

## 🔄 Legacy Script Transition Map

The `ops-cli` is designed to consolidate the following legacy shell/perl scripts into a single, high-performance binary:

| Legacy Script | Modern `ops-cli` Command | Status |
| :--- | :--- | :--- |
| `icmaldet.sh` | `ops-cli forensics scan` | ✅ Integrated |
| `ec.pl` | `ops-cli email` | ✅ Integrated |
| `porta.sh` | `ops-cli response` (Service Checks) | ✅ Integrated |
| `permfix.sh` | `ops-cli forensics scan` (Auto-remedy) | ✅ Integrated |
| `adlog.sh`, `l2.sh`, `logs.sh` | `ops-cli logs` | ✅ Integrated |
| `optimize.sh`, `maxworker.sh` | (New) `optimize` | 🏗️ Planned |
| `abuse.sh` | `ops-cli network` | ✅ Integrated |
| `swiss.sh` | *Consolidated into all modules* | ✅ Integrated |

> [!NOTE]
> Legacy scripts are still available in the `/monitoring`, `/security`, and `/automation` directories for backward compatibility during the transition phase.
