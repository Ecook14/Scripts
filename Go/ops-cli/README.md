# 🛰️ ops-cli: High-Performance Infrastructure Automation

`ops-cli` is a professional-grade, Go-based platform engineered to replace legacy shell scripts with a unified, high-performance binary. It is designed for **Production Operations** where performance, safety, and reliability are absolute requirements.

## ⚡ Usage & Verification
For a complete breakdown of all commands, sub-commands, and flags, refer to the **[ops-cli Operational Manual (Usage.md)](./Usage.md)**.

Architecture and performance details are documented below in the **Engineering Discipline** and **Performance at Scale** sections.

---

## 🏗️ Engineering Discipline: Modules of Defense
Architecture isn't just about organization; it's about separation of concerns and resource efficiency. The codebase is structured into a multi-layered defensive stack:

### 🎮 The Command Center (`/cmd`)
Uses the **Cobra** ecosystem for structured, CLI-compliant interactions.
- `response.go`: Entry point for the Incident Response engine.
- `forensics.go`: Entry point for deep-system security audits.
- `monitor.go`: Real-time TCP observability and metrics.

### 🧠 Incident Response Engine (`/internal/incident`)
Automated remediation logic that acts on real-time system signals (CPU, Load, Miners, OOM). It moves the "Human-in-the-loop" requirement to a "Review-after-action" workflow.

### 🔍 Forensics & Malware Integrity (`/internal/forensics`)
Go beyond simple signature matching. This module uses **Mathematical Forensics** (Shannon Entropy) to detect polymorphic threats and ransomware that bypass traditional scanners.
- **Persistence Audit**: Scans `.bashrc`, `.profile`, and `cronjobs` for unauthenticated entry points.
- **Self-Healing**: Automated `chattr -i` mitigation and metadata-backed restoration.

### 🛰️ TCP Observability Sidecar (`/internal/monitor`)
High-speed parsing of `/proc/net` with zero external dependencies. Designed to detect **Thundering Herd** spikes and listen queue overflows with <1ms overhead.

---

## 🚀 Performance at Scale
Engineering is about data, not claims. `ops-cli` is built for line-rate efficiency:

- **O(K) Space Complexity**: By utilizing a **Min-Heap** for disk tracking and streaming log buffers, the RAM footprint remains constant regardless of whether you are auditing a 1GB or 100TB filesystem.
- **Shannon Entropy Analysis**: Mathematical detection of high-entropy (random) signal patterns in binaries, catching stealthy polymorphism and encrypted ransomware payloads.
- **Context-Aware Execution**: Comprehensive **Context Propagation** ensures that `SIGINT` (Ctrl+C) signals are respected instantly, preventing hung IO or "zombie" processes.

---

## 🛠️ Build & Deployment
Statically linked, zero-dependency binaries for portable cross-distro deployment.

```bash
# 1. Tidy dependencies
go mod tidy

# 2. Compile for production (Linux/AMD64)
GOOS=linux GOARCH=amd64 CGO_ENABLED=0 go build -ldflags="-s -w" -o ops-cli .
```

## 📜 Final Word
`ops-cli` reflects a commitment to building infrastructure that is not just functional, but resilient. It handles the heavy lifting of forensics and system audits so that engineers can focus on architecture, not fire-fighting.

**Built for Resilience. Optimized for the Edge.** 🛡️✨
