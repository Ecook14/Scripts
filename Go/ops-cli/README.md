# ops-cli: High-Performance Infrastructure Automation

`ops-cli` is a professional-grade, Go-based platform designed to consolidate legacy shell scripts into a unified, high-performance binary. It is engineered for **Senior SREs** with a focus on active defense, self-healing, and observability.

## 🏗️ Technical Architecture

The codebase is organized into modular packages to ensure separation of concerns and high testability:

### 🎮 CLI Core (`/cmd`)
Uses **Cobra** for command-line parsing.
- `root.go`: Global configuration and `--json` support.
- `response.go`: Entry for the Incident Response engine.
- `forensics.go`: Security and persistence auditing entry.
- `monitor.go`: TCP observability and metrics exporter.
- `network.go`: Firewall management bridge.
- `logs.go`: Unified log search entry.

### 🧠 Incident Engine (`/internal/incident`)
Handles system health and automated remediation.
- **Checks**: Load average, Service ports, Cryptominer processes, Kernel OOM logs.
- **Remediation**: `ServiceRestart`, `ProcessKill`.
- **Policy**: Supports dry-run and automated action flows.

### 🔍 Forensics Suite (`/internal/forensics`)
Advanced security analysis toolset.
- **Scanner**: Parallel signature matching + **Shannon Entropy** analysis for polymorphism.
- **Persistence**: Deep audit of `.bashrc`, `.profile`, and system-wide **Cronjobs**.
- **Self-Healing**: Automated `chattr -i` unlocking, **Quarantine** isolation, and **Full Restoration** via metadata-backed revert logic.

### 🛰️ Monitoring Sidecar (`/internal/monitor`)
High-availability observability.
- **TCP Stack**: Zero-dependency parsing of `/proc/net/tcp`.
- **Anomalies**: Detects **Thundering Herd** spikes and Listen Queue overflows.
- **Exporter**: Built-in Prometheus-compatible metrics server.

### 💾 Disk Audit (`/internal/disk`)
- **Memory Optimized**: Uses a fixed-size **Min-Heap** to track the top K largest files/dirs without loading entire file lists into memory.
- **Granular Controls**: Supports `--top` (report density) and `--min-size` (noise reduction) filters.
- **Context Aware**: Respects timeouts and cancellation signals (Ctrl+C).

### 🌐 Network & Logs (`/internal/network`, `/internal/logs`)
Legacy script replacements with native Go speed.
- **Network**: Delisting from CSF, Firewalld, and Iptables.
- **Logs**: High-speed, case-insensitive searching across multiple log categories.

## 🛠️ Build & Deployment

`ops-cli` is designed to be deployed as a single, statically linked binary.

```bash
# 1. Tidy dependencies
go mod tidy

# 2. Compile for production (Linux target)
GOOS=linux GOARCH=amd64 CGO_ENABLED=0 go build -ldflags="-s -w" -o ops-cli .
```

## 💎 Key Professional Features

- **Observability**: Expose health metrics via `ops-cli monitor serve`.
- **Interoperability**: Global `--json` flag for integration with standard SIEM/Automation.
- **Safety**: Robust context-cancellation support for long-running scans or audits.
- **Minimalism**: Compiled binary has zero external runtime dependencies.

## 🛡️ Security Logic
The tool executes all system commands (like `csf`, `systemctl`) using absolute paths and strict `exec.CommandContext` wrappers to prevent shell inheritance and injection attacks.

## 🚀 Why this is the "Optimum Approach"

This toolkit utilizes Computer Science fundamentals to ensure production-grade reliability:

- **O(K) Space Complexity (Disk/Logs)**: By using a **Min-Heap** for disk tracking and streaming log buffers, the RAM usage remains constant regardless of whether you scan a 1GB or 100TB filesystem.
- **Mathematical Forensics**: Implements **Shannon Entropy** to detect polymorphic malware and ransomware. This mathematical approach identifies "randomness" signals that standard signature-based scanners miss.
- **Signal-Aware Execution**: Comprehensive **Context Propagation** ensures that `SIGINT` (Ctrl+C) signals are respected instantly across all goroutines, preventing hung IO or "zombie" processes.
- **Zero-Dependency Core**: built entirely on the Go Standard Library to eliminate supply-chain risks, minimize binary size, and guarantee binary portability across any Linux distro.
