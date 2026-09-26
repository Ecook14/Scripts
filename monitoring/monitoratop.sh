#!/usr/bin/env bash
# ==============================================================================
# Script Name : monitoratop.sh
# Author: Nihar + Kiro
# Description : Multi-distro deployment for atop history logging plus a
#               CPU / RAM / Disk-I/O / Disk-space spike monitor that records
#               WHICH process or directory was responsible for each spike,
#               so you get a reviewable event timeline instead of a live-only
#               alert. (Panel-aware: safe on plain Ubuntu, Plesk, or
#               AlmaLinux/cPanel hosts — no /home or /var/www file watching.)
#               Upgrade of old scrypt sysmon.sh
# ==============================================================================

set -euo pipefail

LOG_FILE="/var/log/monitoratop.log"
EVENT_LOG="/var/log/resource-spike-events.log"
MONITOR_SCRIPT="/usr/local/bin/resource-spike-monitor.sh"
STATE_DIR="/var/lib/resource-spike-monitor"

# ------------------------------------------------------------------------------
# 0. Root Permission Check (must happen BEFORE prompting)
# ------------------------------------------------------------------------------
if [ "${EUID:-$(id -u)}" -ne 0 ]; then
    echo "[!] Root privileges required. Escalating privileges with sudo..."
    exec sudo -E bash "$0" "$@"
fi

# ------------------------------------------------------------------------------
# 1. Script Initialization Phase
# ------------------------------------------------------------------------------

clear
cat << "EOF"
==============================================================================
          ATOP HISTORY + CPU/RAM/DISK SPIKE MONITOR DEPLOYER
==============================================================================
EOF

touch "$LOG_FILE"
echo "[*] Initialized monitoratop at $(date '+%Y-%m-%d %H:%M:%S')" | tee -a "$LOG_FILE"

# Helper: prompt for a positive integer, re-prompting on invalid input.
prompt_int() {
    local prompt_text="$1" default_val="$2" input=""
    while true; do
        read -r -p "$prompt_text [Default: $default_val]: " input
        input=${input:-$default_val}
        if [[ "$input" =~ ^[0-9]+$ ]]; then
            echo "$input"
            return 0
        fi
        echo "[!] Invalid input: '$input' is not a positive integer. Try again." >&2
    done
}

echo ""
echo "--- atop history settings ---"
SNAP_INTERVAL=$(prompt_int "Enter atop snapshot interval in seconds" 10)
FRAME_COUNT=$(prompt_int "Enter atop frame count" 8640)

echo ""
echo "--- Spike thresholds ---"
CPU_THRESHOLD=$(prompt_int "CPU usage threshold percentage" 80)
RAM_THRESHOLD=$(prompt_int "RAM usage threshold percentage" 85)
DISK_IO_THRESHOLD=$(prompt_int "Disk I/O utilization threshold percentage (per device)" 90)
DISK_USAGE_THRESHOLD=$(prompt_int "Disk space USED threshold percentage (per filesystem)" 90)
DISK_GROWTH_THRESHOLD_MB=$(prompt_int "Disk space GROWTH threshold in MB per check interval (per filesystem)" 500)
MONITOR_INTERVAL=$(prompt_int "How often to check, in seconds (systemd-timer distros only; cron on CentOS 6 is fixed at 60s)" 60)

for pct_var in CPU_THRESHOLD RAM_THRESHOLD DISK_IO_THRESHOLD DISK_USAGE_THRESHOLD; do
    val="${!pct_var}"
    if [ "$val" -gt 100 ]; then
        echo "[!] $pct_var cannot exceed 100. Clamping to 100." | tee -a "$LOG_FILE"
        printf -v "$pct_var" '%s' 100
    fi
done

echo "[+] atop: interval=${SNAP_INTERVAL}s frames=${FRAME_COUNT}"
echo "[+] Thresholds: CPU=${CPU_THRESHOLD}% RAM=${RAM_THRESHOLD}% DiskI/O=${DISK_IO_THRESHOLD}% DiskUsed=${DISK_USAGE_THRESHOLD}% DiskGrowth=${DISK_GROWTH_THRESHOLD_MB}MB/interval"
echo "[+] Check interval: ${MONITOR_INTERVAL}s"

RETENTION_SECONDS=$((FRAME_COUNT * SNAP_INTERVAL))
RETENTION_DAYS=$(( (RETENTION_SECONDS / 86400) > 0 ? (RETENTION_SECONDS / 86400) : 1 ))
echo "[+] Derived event-log retention: ${RETENTION_DAYS} day(s)"

# ------------------------------------------------------------------------------
# 1.2 Panel awareness (Plesk / cPanel) — informational only, does not block
# ------------------------------------------------------------------------------
if [ -d /usr/local/cpanel ]; then
    echo "[i] cPanel/WHM detected. Note: this script installs the 'epel-release'" | tee -a "$LOG_FILE"
    echo "    repo on AlmaLinux, which cPanel docs recommend configuring yum/dnf" | tee -a "$LOG_FILE"
    echo "    priorities for to avoid shadowing cPanel-managed packages." | tee -a "$LOG_FILE"
elif [ -d /usr/local/psa ] || [ -f /etc/psa/psa.conf ]; then
    echo "[i] Plesk detected. Cron jobs and systemd units deployed by this script" | tee -a "$LOG_FILE"
    echo "    will not appear in the Plesk Scheduled Tasks UI." | tee -a "$LOG_FILE"
fi

# 1.3 Detect Linux Distro
echo "[*] Detecting OS distribution..."
DISTRO=""

if [ -f /etc/os-release ]; then
    . /etc/os-release
    case "${ID:-}" in
        ubuntu|debian)
            DISTRO="ubuntu"
            ;;
        almalinux)
            DISTRO="alma8or9"
            ;;
        rocky)
            DISTRO="rocky8or9"
            ;;
        centos)
            if [[ "${VERSION_ID:-}" =~ ^7 ]]; then
                DISTRO="centos7"
            elif [[ "${VERSION_ID:-}" =~ ^6 ]]; then
                DISTRO="centos6"
            fi
            ;;
        rhel)
            if [[ "${VERSION_ID:-}" =~ ^8 ]] || [[ "${VERSION_ID:-}" =~ ^9 ]]; then
                DISTRO="alma8or9"
            elif [[ "${VERSION_ID:-}" =~ ^7 ]]; then
                DISTRO="centos7"
            elif [[ "${VERSION_ID:-}" =~ ^6 ]]; then
                DISTRO="centos6"
            fi
            ;;
    esac
fi

if [ -z "$DISTRO" ] && [ -f /etc/centos-release ]; then
    CENTOS_VER=$(sed -n 's/.*release \([0-9]\).*/\1/p' /etc/centos-release)
    if [ "$CENTOS_VER" -eq 6 ]; then
        DISTRO="centos6"
    elif [ "$CENTOS_VER" -eq 7 ]; then
        DISTRO="centos7"
    fi
fi

if [ -z "$DISTRO" ]; then
    echo "[!] Error: Unsupported OS distribution." | tee -a "$LOG_FILE"
    exit 1
fi

echo "[*] Detected OS branch: $DISTRO" | tee -a "$LOG_FILE"

# ------------------------------------------------------------------------------
# Helper: deploy the resource-spike-monitor.sh worker script
# ------------------------------------------------------------------------------
deploy_resource_monitor() {
    mkdir -p "$STATE_DIR"
    cat << EOF > "$MONITOR_SCRIPT"
#!/usr/bin/env bash
# Auto-generated by monitoratop.sh — checks CPU / RAM / Disk I/O / Disk space
# against thresholds and logs WHICH process or directory was responsible.
set -u

EVENT_LOG="$EVENT_LOG"
STATE_DIR="$STATE_DIR"
CPU_THRESHOLD=$CPU_THRESHOLD
RAM_THRESHOLD=$RAM_THRESHOLD
DISK_IO_THRESHOLD=$DISK_IO_THRESHOLD
DISK_USAGE_THRESHOLD=$DISK_USAGE_THRESHOLD
DISK_GROWTH_THRESHOLD_MB=$DISK_GROWTH_THRESHOLD_MB

ts() { date '+%Y-%m-%d %H:%M:%S'; }
log_event() { printf '[%s] %s\n' "\$(ts)" "\$1" >> "\$EVENT_LOG"; }

# ---------------- CPU ----------------
CORES=\$(nproc)
LOAD1=\$(awk '{print \$1}' /proc/loadavg)
CPU_PCT=\$(awk -v l="\$LOAD1" -v c="\$CORES" 'BEGIN{printf "%.0f", (l/c)*100}')
if [ "\$CPU_PCT" -ge "\$CPU_THRESHOLD" ] 2>/dev/null; then
    TOP_CPU=\$(ps -eo pid,user,%cpu,%mem,comm --sort=-%cpu | head -6 | tail -5)
    log_event "CPU SPIKE: \${CPU_PCT}% (threshold \${CPU_THRESHOLD}%, load1=\${LOAD1}, cores=\${CORES})"
    printf '%s\n' "\$TOP_CPU" | sed 's/^/    /' >> "\$EVENT_LOG"
fi

# ---------------- RAM ----------------
read -r MEM_TOTAL MEM_AVAIL <<< "\$(awk '/MemTotal/{t=\$2} /MemAvailable/{a=\$2} END{print t, a}' /proc/meminfo)"
if [ -n "\${MEM_TOTAL:-}" ] && [ -n "\${MEM_AVAIL:-}" ] && [ "\$MEM_TOTAL" -gt 0 ]; then
    MEM_USED_PCT=\$(awk -v t="\$MEM_TOTAL" -v a="\$MEM_AVAIL" 'BEGIN{printf "%.0f", ((t-a)/t)*100}')
    if [ "\$MEM_USED_PCT" -ge "\$RAM_THRESHOLD" ] 2>/dev/null; then
        TOP_MEM=\$(ps -eo pid,user,%mem,%cpu,comm --sort=-%mem | head -6 | tail -5)
        log_event "RAM SPIKE: \${MEM_USED_PCT}% used (threshold \${RAM_THRESHOLD}%)"
        printf '%s\n' "\$TOP_MEM" | sed 's/^/    /' >> "\$EVENT_LOG"
    fi
fi

# ---------------- Disk I/O (per device %util + top I/O processes) ----------------
if command -v iostat >/dev/null 2>&1; then
    IOSTAT_OUT=\$(iostat -dx 1 2 2>/dev/null | awk '/^Device/{n++} n==2 && \$0!~/^Device/ && NF>0')
    while read -r line; do
        [ -z "\$line" ] && continue
        DEV=\$(echo "\$line" | awk '{print \$1}')
        UTIL=\$(echo "\$line" | awk '{print \$NF}')
        UTIL_INT=\${UTIL%.*}
        [ -z "\$UTIL_INT" ] && continue
        if [ "\$UTIL_INT" -ge "\$DISK_IO_THRESHOLD" ] 2>/dev/null; then
            log_event "DISK I/O SPIKE: device=\${DEV} util=\${UTIL_INT}% (threshold \${DISK_IO_THRESHOLD}%)"
            if command -v pidstat >/dev/null 2>&1; then
                TOP_IO=\$(pidstat -d 1 1 2>/dev/null | awk 'NR>3 && NF>0' | sort -k4 -rn | head -5)
                [ -n "\$TOP_IO" ] && printf '%s\n' "\$TOP_IO" | sed 's/^/    /' >> "\$EVENT_LOG"
            fi
        fi
    done <<< "\$IOSTAT_OUT"
fi

# ---------------- Disk space used % (per mounted filesystem) ----------------
while read -r pct mount; do
    [ -z "\${pct:-}" ] && continue
    pct=\${pct%\\%}
    if [ "\$pct" -ge "\$DISK_USAGE_THRESHOLD" ] 2>/dev/null; then
        log_event "DISK USAGE SPIKE: \${mount} at \${pct}% used (threshold \${DISK_USAGE_THRESHOLD}%)"
        TOP_DIRS=\$(timeout 15 du -x --max-depth=2 "\$mount" 2>/dev/null | sort -rn | head -5 | awk '{printf "    %sM  %s\n", int(\$1/1024), \$2}')
        [ -n "\$TOP_DIRS" ] && printf '%s\n' "\$TOP_DIRS" >> "\$EVENT_LOG"
    fi
done < <(df -P -x tmpfs -x devtmpfs -x overlay 2>/dev/null | awk 'NR>1{print \$5, \$6}')

# ---------------- Disk growth rate (per mounted filesystem) ----------------
STATE_FILE="\$STATE_DIR/disk-usage.state"
CURRENT=\$(df -P -x tmpfs -x devtmpfs -x overlay 2>/dev/null | awk 'NR>1{print \$6"|"\$3}')
if [ -f "\$STATE_FILE" ]; then
    while IFS='|' read -r mount used; do
        [ -z "\${mount:-}" ] && continue
        PREV=\$(awk -F'|' -v m="\$mount" '\$1==m{print \$2}' "\$STATE_FILE")
        if [ -n "\${PREV:-}" ]; then
            DELTA_KB=\$((used - PREV))
            DELTA_MB=\$((DELTA_KB / 1024))
            if [ "\$DELTA_MB" -ge "\$DISK_GROWTH_THRESHOLD_MB" ] 2>/dev/null; then
                log_event "DISK GROWTH SPIKE: \${mount} grew \${DELTA_MB}MB this interval (threshold \${DISK_GROWTH_THRESHOLD_MB}MB)"
                TOP_DIRS=\$(timeout 15 du -x --max-depth=2 "\$mount" 2>/dev/null | sort -rn | head -5 | awk '{printf "    %sM  %s\n", int(\$1/1024), \$2}')
                [ -n "\$TOP_DIRS" ] && printf '%s\n' "\$TOP_DIRS" >> "\$EVENT_LOG"
            fi
        fi
    done <<< "\$CURRENT"
fi
printf '%s\n' "\$CURRENT" > "\$STATE_FILE"
EOF
    chmod +x "$MONITOR_SCRIPT"
}

deploy_event_log_rotation() {
    if [ -d /etc/logrotate.d ]; then
        cat << EOF > /etc/logrotate.d/resource-spike-monitor
$EVENT_LOG {
    daily
    rotate $RETENTION_DAYS
    compress
    missingok
    notifempty
    copytruncate
}
EOF
    fi
}

# systemd-based distros (everything except CentOS 6): a timer gives
# sub-minute granularity if the user asked for it.
deploy_systemd_timer() {
    cat << EOF > /etc/systemd/system/resource-spike-monitor.service
[Unit]
Description=CPU/RAM/Disk spike check (oneshot)

[Service]
Type=oneshot
ExecStart=$MONITOR_SCRIPT
EOF

    cat << EOF > /etc/systemd/system/resource-spike-monitor.timer
[Unit]
Description=Run resource-spike-monitor every ${MONITOR_INTERVAL}s

[Timer]
OnBootSec=30s
OnUnitActiveSec=${MONITOR_INTERVAL}s
AccuracySec=1s

[Install]
WantedBy=timers.target
EOF
    systemctl daemon-reload
    systemctl enable --now resource-spike-monitor.timer
}

# CentOS 6 has no systemd; cron.d is minute-granularity only.
deploy_cron_fallback() {
    if [ -d /etc/cron.d ]; then
        echo "[!] CentOS 6 has no systemd; using cron (1-minute granularity, ignoring the ${MONITOR_INTERVAL}s value you entered)." | tee -a "$LOG_FILE"
        echo "* * * * * root $MONITOR_SCRIPT" > /etc/cron.d/resource-spike-monitor
    fi
}

# ------------------------------------------------------------------------------
# 2. Distro-Specific Branch Execution
# ------------------------------------------------------------------------------

case "$DISTRO" in
    centos6)
        echo "[*] Running CentOS 6 (SysV Init) setup..."
        yum install -y epel-release
        yum install -y atop sysstat

        if [ -f /etc/sysconfig/atop ]; then
            sed -i "s/^LOGINTERVAL=.*/LOGINTERVAL=$SNAP_INTERVAL/" /etc/sysconfig/atop || echo "LOGINTERVAL=$SNAP_INTERVAL" >> /etc/sysconfig/atop
        fi
        chkconfig atop on
        service atop restart

        deploy_resource_monitor
        deploy_event_log_rotation
        deploy_cron_fallback
        ;;

    centos7)
        echo "[*] Running CentOS 7 (systemd) setup..."
        yum install -y epel-release atop sysstat

        if [ -f /etc/sysconfig/atop ]; then
            sed -i "s/^LOGINTERVAL=.*/LOGINTERVAL=$SNAP_INTERVAL/" /etc/sysconfig/atop || echo "LOGINTERVAL=$SNAP_INTERVAL" >> /etc/sysconfig/atop
        fi
        systemctl enable --now atop

        deploy_resource_monitor
        deploy_event_log_rotation
        deploy_systemd_timer
        ;;

    alma8or9|rocky8or9)
        echo "[*] Running Enterprise Linux 8/9 (DNF) setup..."
        dnf install -y epel-release
        dnf config-manager --set-enabled crb >/dev/null 2>&1 || dnf config-manager --set-enabled powertools >/dev/null 2>&1 || true
        dnf install -y atop sysstat

        if [ -f /etc/sysconfig/atop ]; then
            sed -i "s/^LOGINTERVAL=.*/LOGINTERVAL=$SNAP_INTERVAL/" /etc/sysconfig/atop || echo "LOGINTERVAL=$SNAP_INTERVAL" >> /etc/sysconfig/atop
        elif [ -f /etc/default/atop ]; then
            sed -i "s/^LOGINTERVAL=.*/LOGINTERVAL=$SNAP_INTERVAL/" /etc/default/atop || echo "LOGINTERVAL=$SNAP_INTERVAL" >> /etc/default/atop
        fi
        systemctl enable --now atop

        deploy_resource_monitor
        deploy_event_log_rotation
        deploy_systemd_timer
        ;;

    ubuntu)
        echo "[*] Running Ubuntu/Debian (APT) setup..."
        export DEBIAN_FRONTEND=noninteractive
        apt-get update -y
        apt-get install -y atop sysstat

        if [ -f /etc/default/atop ]; then
            if grep -q '^INTERVAL=' /etc/default/atop 2>/dev/null; then
                sed -i "s/^INTERVAL=.*/INTERVAL=$SNAP_INTERVAL/" /etc/default/atop
            elif grep -q '^LOGINTERVAL=' /etc/default/atop 2>/dev/null; then
                sed -i "s/^LOGINTERVAL=.*/LOGINTERVAL=$SNAP_INTERVAL/" /etc/default/atop
            else
                { echo "INTERVAL=$SNAP_INTERVAL"; echo "LOGINTERVAL=$SNAP_INTERVAL"; } >> /etc/default/atop
            fi
        fi
        systemctl enable --now atop

        deploy_resource_monitor
        deploy_event_log_rotation
        deploy_systemd_timer
        ;;

    *)
        echo "[!] Error: No install branch defined for detected distro: $DISTRO" | tee -a "$LOG_FILE"
        exit 1
        ;;
esac

# ------------------------------------------------------------------------------
# 3. Script Finalization Phase
# ------------------------------------------------------------------------------

echo ""
echo "=============================================================================="
echo "[**] OS detected: $DISTRO"
echo "[**] atop installed (Interval: ${SNAP_INTERVAL}s) — for full per-process history,"
echo "     replay any past moment with: atop -r /var/log/atop/atop_<YYYYMMDD> -b <HHMM>"
echo "[**] Spike monitor deployed and running: $MONITOR_SCRIPT"
echo "     CPU>=${CPU_THRESHOLD}% RAM>=${RAM_THRESHOLD}% DiskI/O>=${DISK_IO_THRESHOLD}% DiskUsed>=${DISK_USAGE_THRESHOLD}% DiskGrowth>=${DISK_GROWTH_THRESHOLD_MB}MB"
echo "[**] Every spike is logged with the responsible process/user or directory to:"
echo "     $EVENT_LOG"
echo "[**] Event log rotated daily, ${RETENTION_DAYS}-day retention."
echo "[**] Script execution completed successfully."
echo "=============================================================================="
echo "[*] Completed deploy at $(date '+%Y-%m-%d %H:%M:%S')" >> "$LOG_FILE"

exit 0
