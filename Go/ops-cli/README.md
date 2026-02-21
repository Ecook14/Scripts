# 🛰️ ops-cli: High-Performance Infrastructure Engineering

`ops-cli` is a professional-grade Go platform engineered to provide line-rate observability and assisted remediation for distributed systems. It replaces legacy dependencies with a unified, statically-linked binary designed for extreme resource efficiency.

---

## 🏗️ Technical Architecture: The 6 Engines

I built `ops-cli` around six decoupled engines, each optimized for specific infrastructure reality.

### 🛡️ [1] Forensics Engine (`/internal/forensics`)
Go beyond simple string matching. This module implements **Mathematical Auditing**:
- **Shannon Entropy Analysis**: Detects high-entropy signals (Threshold: >5.5) in file headers to identify encrypted ransomware or obfuscated malware (e.g., Rondo polymorphism).
- **Persistence Audit**: Scans system and user-level initialization files (`.bashrc`, `.profile`) and `cronjobs` for command hijacking (aliases), hidden execution paths, and unauthenticated remote script invocations (`curl | bash`).
- **Quarantine Logic**: Automated file isolation with **Attribute Unlocking** (`chattr -i`) for persistent threats that attempt to lock their own presence.

### 🧠 Incident Remediation Engine (`/internal/incident`)
A library of remediation utilities that act on real-time system signals:
- **Modular Checks**: Dedicated logic for `LoadCheck`, `ServiceCheck` (TCP availability), `MinerCheck` (CPU architecture signatures), and `OOMCheck` (Kernel log parsing).
- **Remediation Commands**: Statically defined executions for `ServiceRestart` (via `systemctl`) and `ProcessKill` (via `SIGKILL`).
- **Assisted Workflow**: Moves analysis heavy-lifting to the engine while keeping the expert operator in control via `--dry-run` logic.

### 🛰️ Monitoring Engine (`/internal/monitor`)
Zero-dependency observability sidecar for the TCP stack:
- **ProcNet Parser**: High-speed parsing of `/proc/net/tcp` with little-endian hex decoding.
- **Herd Detection**: Heuristic analysis for **Thundering Herd** patterns by monitoring `SYN_RECV` states against operator-defined thresholds.
- **Metric Export**: Built-in Prometheus-compatible sidecar exposing granular socket states and backlog counters.

### 🗄️ Disk Engine (`/internal/disk`)
Memory-optimized filesystem analysis:
- **O(K) Space Complexity**: Implements a **Min-Heap** data structure to ensure a constant RAM footprint whether auditing a 1GB or 100TB partition.

### 📡 Log Engine (`/internal/logs`)
The high-speed streaming search engine:
- **Line-Rate Streaming**: Uses `bufio.Scanner` to search multi-gigabyte logs without memory pressure.
- **Unified Mapping**: Pre-integrated with standard log paths for Apache, Exim, MySQL, and System logs across Linux distributions.

### 🧱 Network Engine (`/internal/network`)
The cross-firewall bridge:
- **Unified Abstraction**: Single interface for interacting with `CSF`, `Firewalld`, and `IPTables`.
- **IP Mitigation**: Standardized `CheckIP` and `UnblockIP` logic for rapid incident mitigation.

---

## 🚀 Performance at Scale
- **Static Linkage**: Zero-dependency binary (`CGO_ENABLED=0`) for portable, immediate deployment.
- **Context-Aware**: Full `context.Context` propagation ensures that I/O operations and scans respect timeouts and `SIGINT` (Ctrl+C) instantly.
- **Zero-B.S. Model**: Stripped of interactive friction, designed for direct execution via automation handlers.

[View the Exhaustive Operational Manual (Usage.md)](./Usage.md)

---
**Standardized for Resilience.** Built by Nihar. 🛡️✨
