#!/usr/bin/env bash
# plesk_health_v7.5.sh
# Full Plesk + server + website + DB + disk + service + network + Apache diagnostics
# Comprehensive report with recommendations (no stored DB credentials)

set -u
IFS=$'\n\t'

# ===== CONFIG =====
LONG_PROC_THRESHOLD=300       # seconds
SLEEP_QUERY_THRESHOLD=50
DDOS_CONN_THRESHOLD=300
POSTFIX_QUEUE_WARN=500
I_O_LATENCY_MS_WARN=20
MYSQL_SLOW_TIME=2
ASSUME_YES=0
TAIL_LINES_LOG=60
TOP_LINES=15

# ===== COLORS =====
RED=$(tput setaf 1 2>/dev/null || echo "")
GREEN=$(tput setaf 2 2>/dev/null || echo "")
YELLOW=$(tput setaf 3 2>/dev/null || echo "")
BLUE=$(tput setaf 4 2>/dev/null || echo "")
RESET=$(tput sgr0 2>/dev/null || echo "")

# ===== ARGS =====
HISTORY_FILE=""
OUT_FILE=""
print_help() {
  cat <<EOF
plesk_health_v7.5.sh - Full Plesk/server/website health checker

Usage: sudo $0 [options]

Options:
  --help             Show this help
  --out FILE         Save plain-text output to FILE (appends)
  --history FILE     Append compact JSONL summary to FILE
  --yes              Assume 'yes' to prompts
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --help) print_help; exit 0;;
    --out) OUT_FILE="$2"; shift 2;;
    --history) HISTORY_FILE="$2"; shift 2;;
    --yes) ASSUME_YES=1; shift;;
    *) echo "Unknown arg: $1"; print_help; exit 1;;
  esac
done

log() {
  echo -e "$@"
  if [[ -n "$OUT_FILE" ]]; then
    echo -e "$@" | sed 's/\x1b\[[0-9;]*m//g' >> "$OUT_FILE"
  fi
}

TS(){ date -u +"%Y-%m-%dT%H:%M:%SZ"; }

calc_gt() {
  local a=${1:-0} b=${2:-0}
  awk -v A="$a" -v B="$b" 'BEGIN{print (A>B)?1:0}'
}

confirm_or_die() {
  local q="$1"
  [[ $ASSUME_YES -eq 1 ]] && return 0
  read -r -p "$q [y/N]: " ans
  case "$ans" in y|Y) return 0;; *) log "Skipping."; return 1;; esac
}

# ===== SYSTEM SNAPSHOT =====
REPORT_TS=$(TS)
read -r LOAD1 LOAD5 LOAD15 _ < /proc/loadavg || { LOAD1=0; LOAD5=0; LOAD15=0; }
CORES=$(nproc 2>/dev/null || echo 1)
MEM_TOTAL_H=$(free -h | awk '/Mem:/ {print $2}')
MEM_USED_H=$(free -h | awk '/Mem:/ {print $3}')
MEM_TOTAL=$(awk '/MemTotal/ {print int($2/1024)}' /proc/meminfo 2>/dev/null || echo 0)
MEM_AVAILABLE=$(awk '/MemAvailable/ {print int($2/1024)}' /proc/meminfo 2>/dev/null || echo 0)
MEM_USED=$(( MEM_TOTAL - MEM_AVAILABLE ))
SWAP_TOTAL=$(free -m | awk '/Swap/ {print $2}' 2>/dev/null || echo 0)
SWAP_USED=$(free -m | awk '/Swap/ {print $3}' 2>/dev/null || echo 0)
UPTIME=$(uptime -p 2>/dev/null || echo "N/A")
KERNEL=$(uname -r 2>/dev/null || echo "N/A")
OS_INFO=$(grep -E '^PRETTY_NAME' /etc/os-release 2>/dev/null | cut -d= -f2- | tr -d '"' || echo "Unknown OS")

# Ensure numeric variables are valid
LOAD1=${LOAD1:-0}
LOAD5=${LOAD5:-0}
LOAD15=${LOAD15:-0}
MEM_TOTAL=${MEM_TOTAL:-0}
MEM_USED=${MEM_USED:-0}
SWAP_TOTAL=${SWAP_TOTAL:-0}
SWAP_USED=${SWAP_USED:-0}

log "${BLUE}=== Plesk Full Health Report (${REPORT_TS}) ===${RESET}"
log "OS: $OS_INFO"
log "Kernel: $KERNEL"
log "Uptime: $UPTIME"
log "Load Avg: $LOAD1 $LOAD5 $LOAD15  | CPU cores: $CORES"
log "Memory (human): $MEM_USED_H / $MEM_TOTAL_H  | Memory (MB): ${MEM_USED}MB/${MEM_TOTAL}MB"
log "Swap: ${SWAP_USED}MB/${SWAP_TOTAL}MB"

# top snapshot
log "${YELLOW}--- top snapshot (${TOP_LINES} lines) ---${RESET}"
if command -v top &>/dev/null; then
  top -b -n1 | head -n $TOP_LINES
fi

# ===== APACHE / HTTPD DIAGNOSTICS =====
log "${YELLOW}--- Apache/httpd diagnostics ---${RESET}"
APACHECTL_PATH=""
[[ -x $(command -v apachectl) ]] && APACHECTL_PATH=apachectl

APACHE_ERROR_LOGS=(/var/log/apache2/error.log /var/log/httpd/error_log)
APACHE_ACCESS_LOGS=(/var/log/apache2/access.log /var/log/httpd/access_log)

[[ -n "$APACHECTL_PATH" ]] && {
  log "apachectl -M (mpm lines):"
  $APACHECTL_PATH -M 2>/dev/null | grep -i mpm || true
}

MAXREQ=""
CAND_APACHE_CONF=(/etc/apache2/mods-enabled/*mpm*.conf /etc/httpd/conf.modules.d/*mpm*.conf /etc/httpd/conf/httpd.conf /etc/apache2/apache2.conf)
for fglob in "${CAND_APACHE_CONF[@]}"; do
  for f in $fglob; do
    [[ -f "$f" ]] || continue
    tmp=$(grep -E "MaxRequestWorkers|MaxClients" "$f" 2>/dev/null | sed -n '1p' || true)
    [[ -n "$tmp" ]] && { MAXREQ="$tmp (from $f)"; break 2; }
  done
done

[[ -n "$MAXREQ" ]] && log "Found Apache concurrency directive: $MAXREQ" || log "MaxRequestWorkers/MaxClients not found in common files."

for logfile in "${APACHE_ERROR_LOGS[@]}"; do [[ -f "$logfile" ]] && { log "${YELLOW}--- Apache Error Log (last ${TAIL_LINES_LOG} lines): $logfile ---${RESET}"; tail -n $TAIL_LINES_LOG "$logfile"; break; }; done
for logfile in "${APACHE_ACCESS_LOGS[@]}"; do [[ -f "$logfile" ]] && { log "${YELLOW}--- Apache Access Log (last 30 requests): $logfile ---${RESET}"; tail -n 30 "$logfile"; break; }; done

# ===== MEMORY snapshot =====
log "${YELLOW}--- Memory (human) ---${RESET}"
free -h

# ===== DISK =====
log "${YELLOW}--- Disk usage ---${RESET}"
df -h | sed -n '1,200p'
df -i | sed -n '1,200p'

# ===== TOP processes =====
log "${YELLOW}--- Top CPU Processes (top 15) ---${RESET}"
ps -eo pid,ppid,cmd,%cpu,%mem --sort=-%cpu | head -n 16
log "${YELLOW}--- Top MEM Processes (top 15) ---${RESET}"
ps -eo pid,ppid,cmd,%cpu,%mem --sort=-%mem | head -n 16

# ===== NETWORK =====
if command -v ss &>/dev/null; then
  EST_CONN=$(ss -H state established | wc -l)
  SYN_RECV=$(ss -H state syn-recv | wc -l)
  log "${YELLOW}--- Network ---${RESET}"
  log "Established TCP connections: $EST_CONN"
  log "SYN-RECV (half-open): $SYN_RECV"
  (( EST_CONN > DDOS_CONN_THRESHOLD )) && { log "${YELLOW}High established connections ($EST_CONN). Top IPs:${RESET}"; ss -H state established | awk '{print $5}' | cut -d: -f1 | sort | uniq -c | sort -rn | head -n 20; }
fi

# ===== DISK I/O =====
if command -v iostat &>/dev/null; then
  log "${YELLOW}--- iostat (device stats) ---${RESET}"
  iostat -x 1 2
  HIGH_IO=$(iostat -x 1 2 2>/dev/null | awk 'BEGIN{p=0}/Device/{p=1;next} p && NF{ if($10+0 > '"$I_O_LATENCY_MS_WARN"' ) print $1":"$10 }' || true)
  [[ -n "$HIGH_IO" ]] && { log "${YELLOW}Devices with high await(ms):${RESET}"; echo "$HIGH_IO"; }
fi

# ===== MySQL/MariaDB =====
MYSQL_SERVICE=""
[[ $(systemctl list-units --type=service | grep -c "^mysql") -gt 0 ]] && MYSQL_SERVICE="mysql"
[[ -z "$MYSQL_SERVICE" && $(systemctl list-units --type=service | grep -c "^mariadb") -gt 0 ]] && MYSQL_SERVICE="mariadb"

MYSQL_UP=0
SLEEP_CT=0
SLOW_QUERIES=0
MYSQL_MAX_CONN=0

if [[ -n "$MYSQL_SERVICE" ]] && command -v mysql &>/dev/null && command -v mysqladmin &>/dev/null; then
  log "${YELLOW}--- MySQL/MariaDB ---${RESET}"
  if mysqladmin ping &>/dev/null; then
    MYSQL_UP=1
    SLEEP_CT=$(mysql -sse "SELECT COUNT(*) FROM INFORMATION_SCHEMA.PROCESSLIST WHERE COMMAND='Sleep';" 2>/dev/null || echo 0)
    SLOW_QUERIES=$(mysql -sse "SHOW GLOBAL STATUS LIKE 'Slow_queries';" 2>/dev/null | awk '{print $2}' || echo 0)
    MYSQL_MAX_CONN=$(mysql -sse "SHOW VARIABLES LIKE 'max_connections';" 2>/dev/null | awk '{print $2}' || echo 0)
    log "Service: $MYSQL_SERVICE"
    log "Sleeping connections: $SLEEP_CT"
    log "Slow queries: $SLOW_QUERIES"
    log "Max connections: $MYSQL_MAX_CONN"
  else
    log "${RED}$MYSQL_SERVICE not responding to ping${RESET}"
  fi
else
  log "MySQL/MariaDB client or service not available; skipping."
fi

# ===== PHP-FPM detection =====
PHPFPM_SERVICE=""
if systemctl list-units --type=service | grep -q "^php-fpm"; then
  PHPFPM_SERVICE="php-fpm"
elif systemctl list-units --type=service | grep -q "^php.*-fpm"; then
  PHPFPM_SERVICE=$(systemctl list-units --type=service | grep "^php.*-fpm" | awk '{print $1}' | head -n1)
fi

if [[ -n "$PHPFPM_SERVICE" ]]; then
  log "${YELLOW}--- PHP-FPM (${PHPFPM_SERVICE}) ---${RESET}"
  PM_MAX_CHILDREN=$(grep -E 'pm.max_children' /etc/php/*/fpm/pool.d/*.conf 2>/dev/null | awk -F= '{gsub(/ /,"",$2); print $2}' | sort -nr | head -n1 || echo "N/A")
  log "PHP-FPM service: $PHPFPM_SERVICE"
  log "Max children (pm.max_children): $PM_MAX_CHILDREN"
else
  log "PHP-FPM not installed or no pools found."
fi

# ===== MAIL (Postfix) =====
POSTFIX_COUNT=0
if command -v postfix &>/dev/null || command -v mailq &>/dev/null; then
  log "${YELLOW}--- Mail queue (Postfix) ---${RESET}"
  POSTFIX_COUNT=$(mailq 2>/dev/null | grep -c '^[A-F0-9]' || echo 0)
  log "Postfix queue size: $POSTFIX_COUNT"
fi

# ===== Plesk websites =====
CHECK_WEBSITES=()
[[ -x $(command -v plesk) ]] && CHECK_WEBSITES=($(plesk bin site --list 2>/dev/null || true))
[[ ${#CHECK_WEBSITES[@]} -gt 0 ]] && log "${YELLOW}--- Plesk websites (quick HTTP check) ---${RESET}"
for s in "${CHECK_WEBSITES[@]}"; do
  HTTP_CODE=$(curl -ks -o /dev/null -w "%{http_code}" "https://$s" || echo "000")
  log "Site: $s -> HTTP $HTTP_CODE"
done

# ===== Plesk services =====
log "${YELLOW}--- Plesk-related services ---${RESET}"
HTTPD_ALIAS="apache2"
[[ "$OS_INFO" == *CentOS* ]] && HTTPD_ALIAS="httpd"
SERVICES=(sw-cp-server nginx "$HTTPD_ALIAS" psa "$MYSQL_SERVICE" "$PHPFPM_SERVICE" postfix dovecot)
for svc in "${SERVICES[@]}"; do
  [[ -z "$svc" ]] && continue
  STATUS="missing"
  if systemctl list-units --type=service --no-legend | grep -q "^${svc}"; then
    systemctl is-active --quiet "$svc" && STATUS="active" || STATUS="inactive"
  fi
  log "$svc: $STATUS"
done

# ===== Long-running processes =====
LONG_PIDS_LIST=$(ps -eo pid,etimes,cmd --sort=-etimes | awk -v th="$LONG_PROC_THRESHOLD" 'NR>1 && $2>th {print $0}')
[[ -n "$LONG_PIDS_LIST" ]] && { log "${RED}Long-running processes (>${LONG_PROC_THRESHOLD}s):${RESET}"; echo "$LONG_PIDS_LIST" | head -n 200; }

# ===== Recommendations & suggested commands =====
RECOMMENDATIONS=()
i=1
(( $(calc_gt "$LOAD5" "$CORES") )) && RECOMMENDATIONS+=("$i. Load average ($LOAD5) exceeds CPU cores ($CORES). Check heavy jobs.") && ((i++))
[[ "$MEM_TOTAL" -gt 0 ]] && (( MEM_USED * 100 / MEM_TOTAL >= 80 )) && RECOMMENDATIONS+=("$i. Memory >=80% (${MEM_USED}MB/${MEM_TOTAL}MB). Check PHP-FPM and heavy processes.") && ((i++))
[[ "$SWAP_TOTAL" -gt 0 ]] && (( SWAP_USED > SWAP_TOTAL/2 )) && RECOMMENDATIONS+=("$i. Swap >50% (${SWAP_USED}MB/${SWAP_TOTAL}MB). Consider adding RAM.") && ((i++))
(( SLEEP_CT > SLEEP_QUERY_THRESHOLD )) && RECOMMENDATIONS+=("$i. High sleeping MySQL connections ($SLEEP_CT). Check connection pooling.") && ((i++))
(( SLOW_QUERIES > MYSQL_SLOW_TIME )) && RECOMMENDATIONS+=("$i. MySQL slow queries ($SLOW_QUERIES). Analyze slow query log.") && ((i++))
(( POSTFIX_COUNT > POSTFIX_QUEUE_WARN )) && RECOMMENDATIONS+=("$i. Postfix queue ($POSTFIX_COUNT) exceeds warning. Inspect or flush carefully.") && ((i++))
[[ -n "$HIGH_IO" ]] && RECOMMENDATIONS+=("$i. High disk await detected: $HIGH_IO. Check 'iotop' or disk speed.") && ((i++))
if [[ -n "$MAXREQ" ]]; then
  mrw=$(echo "$MAXREQ" | grep -Eo '[0-9]+' | tail -n1 || echo 0)
  (( mrw < 150 )) && RECOMMENDATIONS+=("$i. Apache MaxRequestWorkers/MaxClients low ($mrw). Tune for traffic & RAM.") && ((i++))
fi
[[ "$PHPFPM_SERVICE" != "" ]] && [[ "$PM_MAX_CHILDREN" != "N/A" ]] && (( PM_MAX_CHILDREN < 10 )) && RECOMMENDATIONS+=("$i. PHP-FPM pm.max_children is low ($PM_MAX_CHILDREN). Increase for traffic.") && ((i++))
[[ -n "$LONG_PIDS_LIST" ]] && RECOMMENDATIONS+=("$i. Long-running processes detected. Inspect PIDs; kill carefully.") && ((i++))

[[ ${#RECOMMENDATIONS[@]} -gt 0 ]] && { log "${BLUE}=== Recommendations & Suggested Commands ===${RESET}"; for r in "${RECOMMENDATIONS[@]}"; do log "$r"; done; } || log "${GREEN}=== No critical recommendations detected. ===${RESET}"

# ===== History JSONL summary (optional) =====
if [[ -n "$HISTORY_FILE" ]]; then
  jq -n \
    --arg ts "$REPORT_TS" \
    --arg host "$(hostname -f 2>/dev/null || hostname)" \
    --arg os "$OS_INFO" \
    --argjson load1 "$LOAD1" \
    --argjson load5 "$LOAD5" \
    --argjson mem_used "$MEM_USED" \
    --argjson mem_total "$MEM_TOTAL" \
    --argjson swap_used "$SWAP_USED" \
    --argjson swap_total "$SWAP_TOTAL" \
    --argjson mysql_sleep "$SLEEP_CT" \
    --argjson mysql_slow "$SLOW_QUERIES" \
    --argjson postfix_q "$POSTFIX_COUNT" \
    '{ts:$ts,host:$host,os:$os,load:[ $load1, $load5 ],mem_used_mb:$mem_used,mem_total_mb:$mem_total,swap_used_mb:$swap_used,swap_total_mb:$swap_total,mysql_sleep:$mysql_sleep,mysql_slow:$mysql_slow,postfix_queue:$postfix_q}' \
    >> "$HISTORY_FILE" 2>/dev/null || {
      echo "{\"ts\":\"$REPORT_TS\",\"host\":\"$(hostname -f 2>/dev/null || hostname)\",\"error\":\"json append failed\"}" >> "$HISTORY_FILE"
    }
fi

log "${GREEN}=== Plesk/server health scan complete ===${RESET}"
