# ops-cli: Modern System Administration Toolbelt

A unified, high-performance Go CLI replacement for legacy shell scripts. Designed for "Senior Admin" workflows with zero external dependencies, robust error handling, and resource efficiency.

## 🚀 Features

### 1. System Health (`system`)
- **Zero-Dependency**: Parses `/proc/loadavg` and `/proc/meminfo` directly on Linux without `sysstat` or `top`.
- **Metrics**: Real-time CPU, Load Average, and Memory usage (Used/Total).

### 2. Disk Usage (`disk`)
- **Memory Optimized**: Uses a fixed-size Min-Heap to track the top 5 largest files without loading entire file lists into memory.
- **Context Aware**: Respects timeouts and cancellation signals (Ctrl+C).

### 3. Log Analysis (`logs`)
- **Defensive Execution**: Wraps `grep` and `tail` in `exec.Command` with absolute paths (`/usr/bin/grep`) to prevent shell injection.
- **Unified Interface**: Analyze Apache, Exim, MySQL, and System logs from a single command.

### 4. Security (`security`)
- **Hardening Checks**: Native Go config parsing for SSH (`PermitRootLogin`) and FTP (`Anonymous`) settings.
- **Abuse Reporting**: Creates evidence packages (ZIP) using Go's standard library `archive/zip`—no `zip` binary required.

### 5. Optimization (`optimize`)
- **Smart Tuning**: Calculates optimal `MaxRequestWorkers` (Apache) and `innodb_buffer_pool_size` (MySQL) based on actual detected system RAM.

## 🛠️ Build Instructions

Ensure you have Go installed (1.22+ recommended).

```bash
# 1. Download dependencies (cobra)
go mod tidy

# 2. Build the binary (Static linking recommended for production)
CGO_ENABLED=0 go build -ldflags="-s -w" -o ops-cli .
```

## 📖 Usage

```bash
# Check System Health
./ops-cli system

# Analyze Disk Usage (Scan specific path)
./ops-cli disk /var/www

# Interactive Log Viewer
./ops-cli logs

# Security Hardening Scan
./ops-cli security harden

# Generate Abuse Report for a Domain
./ops-cli security abuse example.com

# Get Optimization Recommendations
./ops-cli optimize
```

## 🧠 Design Principles

This tool adheres to the following "Senior Admin" rules:
1.  **Zero-Dependency Minimalism**: No `pip install`, no `npm install`. Just a single static binary.
2.  **Explicit Error Handling**: Every error is checked and wrapped. No silent failures.
3.  **Graceful Shutdown**: Handles `SIGINT`/`SIGTERM` via `context.Context` propagation.
4.  **Structured Logging**: Operational logs go to `Stderr` via `slog` (JSON-ready), data goes to `Stdout`.
