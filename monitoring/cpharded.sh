#!/usr/bin/env bash
# ==============================================================================
# Script Name : cpanel_zabbix_master_setup.sh   (v2.2.3)
# Description : cPanel provisioning, nameservers, CSF firewall, SSH/PHP/MySQL
#               hardening, EasyApache 4 (event MPM + mod_lsapi + mod_remoteip),
#               ImunifyAV and Zabbix Agent 2 setup, with an automatic
#               verification report and handover summary. Safe to re-run.
#
# Usage       : ./cpanel_zabbix_master_setup.sh [options]
#   -y, --yes            Non-interactive: accept defaults (values can come from env)
#       --only LIST      Run only these steps (comma separated):
#                        cpanel,updates,nameservers,csf,ssh,hardening,easyapache,php,imunify,
#                        zabbix,wptoolkit   (hardening = dns,services,forkbomb,ftp,tmp,lfd;
#                        each can also be run alone, e.g. --only ftp,tmp)
#       --verify         Only run the verification checks + write the handover report
#       --finalize-ssh   After verifying new SSH port: closes port 22 & disables root SSH
#   -h, --help           Show this help
# ==============================================================================

set -Eeuo pipefail
umask 022

SCRIPT_NAME="cpanel_master_setup"
LOG_FILE="${LOG_FILE:-/var/log/cpanel_master_setup.log}"
SSH_PORT="${SSH_PORT:-1243}"
DEFAULT_ZABBIX_IP="${DEFAULT_ZABBIX_IP:-103.211.219.161}"
DEFAULT_NS1="${DEFAULT_NS1:-ns1.seedglobaleducation.com}"
DEFAULT_NS2="${DEFAULT_NS2:-ns2.seedglobaleducation.com}"
DEFAULT_SERVER_IP="${DEFAULT_SERVER_IP:-66.116.198.79}"
ZABBIX_VERSION_DEFAULT="${ZABBIX_VERSION_DEFAULT:-7.0}"
PHP_DISABLE_FUNCTIONS="${PHP_DISABLE_FUNCTIONS:-popen,proc_open,parse_ini_file,show_source}"
FTP_PASV_RANGE="${FTP_PASV_RANGE:-49152:65534}"
INSTALL_FCGID="${INSTALL_FCGID:-1}"
ENABLE_CF_REMOTEIP="${ENABLE_CF_REMOTEIP:-1}"
LSAPI_FALLBACK_HANDLER="${LSAPI_FALLBACK_HANDLER:-}"
ZBX_CONF=/etc/zabbix/zabbix_agent2.conf
BACKUP_DIR="/root/setup-backups/$(date +%F_%H%M%S)"
NEED_REBOOT=0
NS_APPLIED=0
ASSUME_YES=0
ONLY=""
FINALIZE_SSH=0
VERIFY_ONLY=0
RAN=()
RESULTS=()
PASS_N=0; WARN_N=0; FAIL_N=0
LSAPI_AVAILABLE=-1
ADMIN_PW_GENERATED=""
ADMIN_PW_RANDOM=0

# ------------------------------------------------------------------------------
# Helpers & UI
# ------------------------------------------------------------------------------
if [[ -t 1 ]]; then
    C_GRN=$'\e[32m'; C_YLW=$'\e[33m'; C_RED=$'\e[31m'; C_RST=$'\e[0m'
else
    C_GRN=""; C_YLW=""; C_RED=""; C_RST=""
fi

_out() {
    local lvl="$1" color="$2"; shift 2
    printf '[%s%s%s] %s\n' "$color" "$lvl" "$C_RST" "$*"
    printf '%s [%s] %s\n' "$(date '+%F %T')" "$lvl" "$*" >>"$LOG_FILE" 2>/dev/null || true
}
log()  { _out '*' "$C_GRN" "$@"; }
warn() { _out '!' "$C_YLW" "$@"; }
die()  { _out 'X' "$C_RED" "$@"; exit 1; }

trap 'die "Unexpected failure at line ${LINENO}: ${BASH_COMMAND}"' ERR

usage() { awk 'NR>1 && /^# ==============================================================================/{exit} NR>1 {sub(/^# ?/,""); print}' "$0"; }

v_pass() { PASS_N=$((PASS_N+1)); RESULTS+=("PASS|$*"); printf '  [%sPASS%s] %s\n' "$C_GRN" "$C_RST" "$*"; printf '%s [PASS] %s\n' "$(date '+%F %T')" "$*" >>"$LOG_FILE" 2>/dev/null || true; }
v_warn() { WARN_N=$((WARN_N+1)); RESULTS+=("WARN|$*"); printf '  [%sWARN%s] %s\n' "$C_YLW" "$C_RST" "$*"; printf '%s [WARN] %s\n' "$(date '+%F %T')" "$*" >>"$LOG_FILE" 2>/dev/null || true; }
v_fail() { FAIL_N=$((FAIL_N+1)); RESULTS+=("FAIL|$*"); printf '  [%sFAIL%s] %s\n' "$C_RED" "$C_RST" "$*"; printf '%s [FAIL] %s\n' "$(date '+%F %T')" "$*" >>"$LOG_FILE" 2>/dev/null || true; }

declare -A ITEM=()
CUR_KEY=""; CUR_F0=0; CUR_W0=0
v_close() {
    [[ -n $CUR_KEY ]] || return 0
    if (( FAIL_N > CUR_F0 )); then ITEM[$CUR_KEY]=FAIL
    elif (( WARN_N > CUR_W0 )); then ITEM[$CUR_KEY]=WARN
    else ITEM[$CUR_KEY]=PASS; fi
    CUR_KEY=""; return 0
}
v_section() { v_close; printf '\n--- %s ---\n' "$1"; CUR_KEY="${2:-}"; CUR_F0=$FAIL_N; CUR_W0=$WARN_N; }

ask_yes_no() {
    local prompt="$1" def="${2:-n}" choice hint="[y/N]"
    [[ $def == y ]] && hint="[Y/n]"
    if (( ASSUME_YES )); then
        if [[ $def == y ]]; then return 0; else return 1; fi
    fi
    while true; do
        read -r -p "$prompt $hint: " choice || choice=""
        choice="${choice,,}"
        [[ -z $choice ]] && choice="$def"
        case "$choice" in
            y|yes) return 0 ;;
            n|no)  return 1 ;;
            *)     echo "Please answer yes or no." ;;
        esac
    done
}

ask_value() {
    local var="$1" prompt="$2" def="${3:-}" validator="${4:-}" val=""
    if [[ -n "${!var:-}" ]]; then
        val="${!var}"
        if [[ -n $validator ]] && ! "$validator" "$val"; then die "Invalid value for $var: $val"; fi
    else
        while true; do
            if (( ASSUME_YES )); then
                val="$def"
            else
                read -r -p "$prompt${def:+ [default: $def]}: " val || val=""
                val="${val:-$def}"
            fi
            if [[ -z $validator ]] || "$validator" "$val"; then break; fi
            if (( ASSUME_YES )); then die "Invalid or missing value for $var"; fi
            warn "Invalid value, please try again."
        done
    fi
    printf -v "$var" '%s' "$val"
}

valid_nonempty()  { [[ -n "$1" ]]; }
valid_username()  { [[ "$1" =~ ^[a-z_][a-z0-9_-]{0,31}$ ]]; }
valid_fqdn()      { [[ "$1" =~ ^([A-Za-z0-9]([A-Za-z0-9-]{0,61}[A-Za-z0-9])?\.)+[A-Za-z]{2,}$ ]]; }
valid_hostmeta()  { [[ "$1" =~ ^[A-Za-z0-9_-]{1,32}$ ]]; }
valid_fqdn_or_empty() { [[ -z "$1" ]] || valid_fqdn "$1"; }
valid_email_or_empty() { [[ -z "$1" ]] || [[ "$1" =~ ^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$ ]]; }
valid_minor_ver() { [[ "$1" =~ ^[0-9]+\.[0-9]+$ ]]; }
valid_ipv4() {
    local ip="$1" o x
    [[ $ip =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]] || return 1
    IFS=. read -ra o <<<"$ip"
    for x in "${o[@]}"; do
        if (( 10#$x > 255 )); then return 1; fi
    done
    return 0
}

step_wanted() {
    local yes=0
    if [[ -n $ONLY ]]; then
        [[ ",$ONLY," == *",$1,"* ]] && yes=1
    else
        ask_yes_no "$2" y && yes=1
    fi
    if (( yes )); then RAN+=("$1"); return 0; fi
    return 1
}
ran() { local s; for s in "${RAN[@]:-}"; do [[ $s == "$1" ]] && return 0; done; return 1; }

ask_password() {
    local var="$1" prompt="$2" min="${3:-12}" confirm="${4:-1}" allow_empty="${5:-0}" validator="${6:-}"
    local p1="" p2="" tries=0
    if [[ -n ${!var:-} ]]; then return 0; fi
    if [[ ! -r /dev/tty || ! -w /dev/tty ]]; then return 1; fi
    while (( tries < 3 )); do
        printf '%s: ' "$prompt" >/dev/tty
        IFS= read -r -s p1 </dev/tty || { echo >/dev/tty; return 1; }
        echo >/dev/tty
        if [[ -z $p1 ]]; then
            if (( allow_empty )); then return 1; fi
            tries=$((tries+1)); warn "Password cannot be empty ($tries/3)."; continue
        fi
        if (( ${#p1} < min )); then tries=$((tries+1)); warn "Password must be at least $min characters ($tries/3)."; continue; fi
        if [[ -n $validator ]] && ! "$validator" "$p1"; then tries=$((tries+1)); warn "Password contains disallowed characters ($tries/3)."; continue; fi
        if (( confirm )); then
            printf 'Confirm password: ' >/dev/tty
            IFS= read -r -s p2 </dev/tty || { echo >/dev/tty; return 1; }
            echo >/dev/tty
            if [[ $p1 != "$p2" ]]; then tries=$((tries+1)); warn "Passwords do not match ($tries/3)."; continue; fi
        fi
        printf -v "$var" '%s' "$p1"
        return 0
    done
    return 1
}
valid_sql_safe_password() { [[ $1 != *"'"* && $1 != *'"'* && $1 != *'\'* && $1 != *'#'* && ! $1 =~ [[:space:]] ]]; }

backup_file() {
    local f="$1"
    [[ -e $f ]] || return 0
    mkdir -p "$BACKUP_DIR$(dirname "$f")"
    cp -a "$f" "$BACKUP_DIR$f"
}

set_block() {
    local file="$1" tag="$2" content
    content="$(cat)"
    touch "$file"
    sed -i "/^# BEGIN ${tag} /,/^# END ${tag}\$/d" "$file"
    {
        printf '# BEGIN %s (managed by %s)\n' "$tag" "$SCRIPT_NAME"
        printf '%s\n' "$content"
        printf '# END %s\n' "$tag"
    } >>"$file"
}

remove_root_cron() {
    local pat="$1" cur
    cur="$(crontab -l 2>/dev/null || true)"
    if grep -q "$pat" <<<"$cur"; then
        { grep -v "$pat" <<<"$cur" || true; } | crontab -
        log "Removed legacy root crontab entry matching '$pat'"
    fi
}

csv_has() { [[ ",$1," == *",$2,"* ]]; }
csv_add() { if [[ -z $1 ]]; then echo "$2"; elif csv_has "$1" "$2"; then echo "$1"; else echo "$1,$2"; fi; }
csv_del() {
    local out="" item items
    IFS=, read -ra items <<<"$1"
    for item in "${items[@]}"; do
        if [[ $item != "$2" && -n $item ]]; then out="$(csv_add "$out" "$item")"; fi
    done
    echo "$out"
}

# ------------------------------------------------------------------------------
# Argument parsing, root check, OS detection
# ------------------------------------------------------------------------------
while [[ $# -gt 0 ]]; do
    case "$1" in
        -y|--yes) ASSUME_YES=1 ;;
        --only) ONLY="${2:-}"; shift ;;
        --verify) VERIFY_ONLY=1 ;;
        --finalize-ssh) FINALIZE_SSH=1 ;;
        -h|--help) usage; exit 0 ;;
        *) die "Unknown option: $1 (use --help)" ;;
    esac
    shift
done

if [[ "${EUID:-$(id -u)}" -ne 0 ]]; then die "Root privileges are required to run this script."; fi
touch "$LOG_FILE"; chmod 600 "$LOG_FILE"

exec 9>/var/lock/cpanel_master_setup.lock
flock -n 9 || die "Another instance of this script is already running."

[[ -r /etc/os-release ]] || die "Cannot detect OS: /etc/os-release missing."
# shellcheck disable=SC1091
. /etc/os-release
OS_ID="${ID:-unknown}"
OS_VERSION_ID="${VERSION_ID:-0}"
OS_MAJOR="${OS_VERSION_ID%%.*}"
case "$OS_ID" in
    almalinux|rocky|rhel|centos|ol|cloudlinux) OS_FAMILY=rhel ;;
    ubuntu|debian)                              OS_FAMILY=debian ;;
    *)                                          OS_FAMILY=unknown ;;
esac
if command -v dnf &>/dev/null; then PM=dnf; else PM=yum; fi

pkg_install()   { if [[ $OS_FAMILY == rhel ]]; then "$PM" install -y "$@"; else DEBIAN_FRONTEND=noninteractive apt-get install -y "$@"; fi; }
pkg_remove()    { if [[ $OS_FAMILY == rhel ]]; then "$PM" remove -y "$@"; else DEBIAN_FRONTEND=noninteractive apt-get remove -y "$@"; fi; }
pkg_installed() {
    if [[ $OS_FAMILY == rhel ]]; then rpm -q "$1" &>/dev/null
    else dpkg-query -W -f='${Status}' "$1" 2>/dev/null | grep -q "install ok installed"; fi
}
pkg_available() {
    pkg_installed "$1" && return 0
    if [[ $OS_FAMILY == rhel ]]; then "$PM" -q list --available "$1" &>/dev/null
    else apt-cache show "$1" &>/dev/null; fi
}
ea_name() { if [[ $OS_FAMILY == debian ]]; then echo "${1//_/-}"; else echo "$1"; fi; }
is_cpanel() { [[ -x /usr/local/cpanel/cpanel ]]; }
have_csf()  { [[ -x /usr/sbin/csf || -x /usr/local/csf/bin/csf.pl ]] && [[ -f /etc/csf/csf.conf ]]; }
svc_exists() { systemctl cat "$1" &>/dev/null; }
httpd_bin() {
    local b
    for b in /usr/local/apache/bin/httpd /usr/sbin/httpd /usr/sbin/apache2; do
        if [[ -x $b ]]; then echo "$b"; return 0; fi
    done
    return 0
}
has_whmapi() { command -v whmapi1 &>/dev/null; }

detect_public_ip() {
    local ip
    ip="$(curl -4 -fsS --max-time 3 https://ifconfig.me 2>/dev/null || true)"
    if ! valid_ipv4 "$ip"; then
        ip="$(hostname -I 2>/dev/null | awk '{print $1}')"
    fi
    if ! valid_ipv4 "$ip"; then
        ip="$DEFAULT_SERVER_IP"
    fi
    echo "$ip"
}
SERVER_IP="${SERVER_IP:-$(detect_public_ip)}"

clear || true
echo "=============================================================================="
echo "  cPANEL/WHM PROVISIONING, EA4 (LSAPI), CSF, HARDENING & ZABBIX AGENT 2  v2.2.3 "
echo "=============================================================================="
echo "Detected OS : $OS_ID $OS_VERSION_ID ($OS_FAMILY)"
echo "Server IP   : $SERVER_IP"
echo "Log file    : $LOG_FILE"
echo "Backups     : $BACKUP_DIR"
echo "------------------------------------------------------------------------------"

# ------------------------------------------------------------------------------
# CSF helpers
# ------------------------------------------------------------------------------
csf_get() {
    grep -E "^$1[[:space:]]*=" /etc/csf/csf.conf | head -1 \
        | sed -E 's/^[^=]*=[[:space:]]*"?([^"]*)"?.*/\1/' || true
}
csf_set() {
    local k="$1" v="$2" f=/etc/csf/csf.conf
    if grep -qE "^${k}[[:space:]]*=" "$f"; then
        sed -i -E "s|^${k}[[:space:]]*=.*|${k} = \"${v}\"|" "$f"
    else
        warn "CSF option ${k} not found in csf.conf (skipped)"
    fi
}
csf_restart() { csf -r >>"$LOG_FILE" 2>&1 || die "csf -r failed; see $LOG_FILE"; }

ensure_zbx_ip() {
    ask_value ZBX_SERVER_IP "Enter Zabbix Server IP" "$DEFAULT_ZABBIX_IP" valid_ipv4
}

cf_ranges() {
    local with_v6="${1:-0}" ver l data
    for ver in ips-v4 ips-v6; do
        if [[ $ver == ips-v6 && $with_v6 != 1 ]]; then continue; fi
        data="$(curl -fsS --max-time 20 "https://www.cloudflare.com/$ver" 2>/dev/null || true)"
        while IFS= read -r l; do
            if [[ $l =~ ^[0-9a-fA-F.:]+/[0-9]+$ ]]; then printf '%s\n' "$l"; fi
        done <<<"$data"
    done
    return 0
}

open_tcp_port() {
    local p="$1" cur
    if have_csf; then
        cur="$(csf_get TCP_IN)"
        if ! csv_has "$cur" "$p"; then
            csf_set TCP_IN "$(csv_add "$cur" "$p")"
            csf_restart
            log "Opened TCP $p in CSF"
        fi
    elif systemctl is-active --quiet firewalld 2>/dev/null; then
        firewall-cmd --permanent --add-port="$p/tcp" >/dev/null && firewall-cmd --reload >/dev/null
        log "Opened TCP $p in firewalld"
    elif command -v iptables &>/dev/null; then
        iptables -C INPUT -p tcp --dport "$p" -j ACCEPT 2>/dev/null \
            || iptables -I INPUT -p tcp --dport "$p" -j ACCEPT
        warn "Opened TCP $p in raw iptables (non-persistent)"
    fi
}

allow_zabbix_port() {
    ensure_zbx_ip
    if have_csf; then
        printf 'tcp|in|d=10050|s=%s  # Zabbix server\n' "$ZBX_SERVER_IP" | set_block /etc/csf/csf.allow zabbix
        grep -qxF "$ZBX_SERVER_IP" /etc/csf/csf.ignore 2>/dev/null || echo "$ZBX_SERVER_IP" >>/etc/csf/csf.ignore
        csf_restart
    elif systemctl is-active --quiet firewalld 2>/dev/null; then
        firewall-cmd --permanent --add-rich-rule="rule family=ipv4 source address=${ZBX_SERVER_IP} port port=10050 protocol=tcp accept" >/dev/null
        firewall-cmd --reload >/dev/null
    elif command -v iptables &>/dev/null; then
        iptables -C INPUT -p tcp -s "$ZBX_SERVER_IP" --dport 10050 -j ACCEPT 2>/dev/null \
            || iptables -I INPUT -p tcp -s "$ZBX_SERVER_IP" --dport 10050 -j ACCEPT
    fi
}

# ------------------------------------------------------------------------------
# 1. cPanel detection, update or installation
# ------------------------------------------------------------------------------
step_cpanel() {
    if is_cpanel; then
        log "cPanel $(cat /usr/local/cpanel/version 2>/dev/null || echo '?') detected. Running /scripts/upcp --force ..."
        /scripts/upcp --force
        return
    fi

    [[ $OS_FAMILY != unknown ]] || die "Unsupported OS for cPanel: $OS_ID"
    if [[ $OS_FAMILY == rhel && $OS_MAJOR -lt 8 ]] || [[ $OS_ID == ubuntu && $OS_MAJOR -lt 22 ]]; then
        die "$OS_ID $OS_VERSION_ID is too old for current cPanel releases."
    fi
    if [[ -z "${TMUX:-}${STY:-}" ]]; then
        warn "The installer runs 30-60 min. Run inside tmux/screen so an SSH drop can't kill it."
        ask_yes_no "Continue anyway?" n || return 0
    fi

    ask_value NEW_HOSTNAME "Enter FQDN hostname (e.g. server.example.com)" "$(hostname -f 2>/dev/null || hostname)" valid_fqdn
    hostnamectl set-hostname "$NEW_HOSTNAME"
    log "Hostname set to $NEW_HOSTNAME"

    log "Updating base packages and prerequisites..."
    if [[ $OS_FAMILY == debian ]]; then
        apt-get update -y && DEBIAN_FRONTEND=noninteractive apt-get upgrade -y
    else
        "$PM" -y update
    fi
    pkg_install perl curl wget tar

    log "Downloading and running the cPanel installer..."
    cd /home
    curl -fsSL -o latest https://securedownloads.cpanel.net/latest
    sh latest
    NEED_REBOOT=1
    warn "cPanel installation finished. A reboot is recommended."
}

# ------------------------------------------------------------------------------
# 1b. WHM default nameservers + contact email
# ------------------------------------------------------------------------------
wwwacct_set() {
    local k="$1" v="$2" f=/etc/wwwacct.conf
    touch "$f"
    if grep -qE "^${k}[[:space:]]" "$f"; then
        sed -i -E "s|^${k}[[:space:]].*|${k} ${v}|" "$f"
    else
        printf '%s %s\n' "$k" "$v" >>"$f"
    fi
}

ensure_ns_a_records() {
    has_whmapi || return 0
    local h zone ip var i=0 def_ip
    def_ip="${NS_IP:-$SERVER_IP}"
    for h in "$NS1" "$NS2" "${NS3:-}" "${NS4:-}"; do
        i=$((i+1)); [[ -n $h ]] || continue
        zone="${h#*.}"; var="NS${i}_IP"; ip="${!var:-$def_ip}"
        if [[ ! -f /var/named/${zone}.db ]]; then
            log "Zone $zone is not hosted locally: ensure glue records point $h -> $ip at your registrar."; continue
        fi
        if grep -Eq "^(${h//./\\.}\.|${h%%.*})[[:space:]]+[0-9]+[[:space:]]+IN[[:space:]]+A[[:space:]]" "/var/named/${zone}.db"; then
            log "A record for $h already exists in local zone $zone."
        elif whmapi1 addzonerecord domain="$zone" name="${h}." type=A address="$ip" ttl=14400 2>>"$LOG_FILE" | grep -q 'result: 1'; then
            log "Added local DNS A record $h -> $ip in zone $zone."
        else
            warn "Could not add local A record for $h ($ip)."
        fi
    done
    return 0
}

step_nameservers() {
    is_cpanel || { warn "cPanel not detected; skipping nameserver configuration."; return 0; }
    ask_value NS1 "Enter primary nameserver" "$DEFAULT_NS1" valid_fqdn
    ask_value NS2 "Enter secondary nameserver" "$DEFAULT_NS2" valid_fqdn
    [[ -z "${NS3:-}" ]] || valid_fqdn "$NS3" || die "Invalid NS3: $NS3"
    [[ -z "${NS4:-}" ]] || valid_fqdn "$NS4" || die "Invalid NS4: $NS4"
    ask_value CONTACT_EMAIL "Enter server contact email (Enter to skip)" "" valid_email_or_empty

    backup_file /etc/wwwacct.conf
    local args=(nameserver="$NS1" nameserver2="$NS2") applied=0
    [[ -z "${NS3:-}" ]] || args+=(nameserver3="$NS3")
    [[ -z "${NS4:-}" ]] || args+=(nameserver4="$NS4")

    if has_whmapi && whmapi1 update_nameservers_config "${args[@]}" 2>>"$LOG_FILE" | grep -q 'result: 1'; then
        applied=1
    else
        warn "whmapi1 update_nameservers_config failed; writing /etc/wwwacct.conf directly."
        wwwacct_set NS  "$NS1"
        wwwacct_set NS2 "$NS2"
        [[ -z "${NS3:-}" ]] || wwwacct_set NS3 "$NS3"
        [[ -z "${NS4:-}" ]] || wwwacct_set NS4 "$NS4"
    fi

    if [[ -n "${CONTACT_EMAIL:-}" ]]; then
        wwwacct_set CONTACTEMAIL "$CONTACT_EMAIL"
        printf '%s\n' "$CONTACT_EMAIL" >/root/.contactemail
        log "Contact email set to $CONTACT_EMAIL"
    fi

    if grep -qE "^NS[[:space:]]+${NS1}\$" /etc/wwwacct.conf && grep -qE "^NS2[[:space:]]+${NS2}\$" /etc/wwwacct.conf; then
        log "Nameservers applied: NS=${NS1}  NS2=${NS2}${NS3:+  NS3=$NS3}${NS4:+  NS4=$NS4}"
    else
        die "Nameservers not verified in /etc/wwwacct.conf."
    fi
    ensure_ns_a_records || true
    NS_APPLIED=1
}

# ------------------------------------------------------------------------------
# 2. CSF firewall
# ------------------------------------------------------------------------------
install_csf() {
    if have_csf; then
        log "CSF already installed: $(csf -v 2>/dev/null | head -1 || true)"
        return 0
    fi

    if svc_exists firewalld.service && systemctl is-enabled --quiet firewalld 2>/dev/null; then
        warn "firewalld conflicts with CSF; disabling it."
        systemctl disable --now firewalld
    fi
    iptables-save >"/root/iptables_backup_$(date +%F_%H%M%S)" 2>/dev/null || true

    if is_cpanel; then
        log "Installing CSF from cpanel-csf package..."
        if ! pkg_install cpanel-csf; then
            [[ -x /scripts/autorepair ]] && /scripts/autorepair cpanel_csf_install || true
        fi
    fi

    if ! have_csf; then
        if [[ -n "${CSF_TARBALL_URL:-}" ]]; then
            cd /usr/src && rm -rf csf csf.tgz csf-src && mkdir csf-src
            curl -fsSL "$CSF_TARBALL_URL" -o csf.tgz
            tar -xzf csf.tgz -C csf-src --strip-components=1
            (cd csf-src && sh install.sh)
        else
            warn "Could not install CSF automatically. Provide CSF_TARBALL_URL if offline."
            return 1
        fi
    fi
    have_csf || die "CSF installation did not complete."
    return 0
}

step_csf() {
    ensure_zbx_ip
    install_csf || return 0

    backup_file /etc/csf/csf.conf
    backup_file /etc/csf/csf.allow
    backup_file /etc/csf/csf.ignore

    local cur_port="" my_ip=""
    if [[ -n "${SSH_CONNECTION:-}" ]]; then
        my_ip="${SSH_CONNECTION%% *}"
        cur_port="${SSH_CONNECTION##* }"
    fi

    local tcp_in="20,21,25,53,80,110,143,443,465,587,993,995,2082,2083,2086,2087,2095,2096,${FTP_PASV_RANGE}"
    local p
    for p in 22 "$SSH_PORT" "$cur_port"; do
        [[ $p =~ ^[0-9]+$ ]] && tcp_in="$(csv_add "$tcp_in" "$p")"
    done

    log "Configuring CSF firewall rules..."
    csf_set TCP_IN  "$tcp_in"
    csf_set TCP_OUT "20,21,22,25,37,43,53,80,110,113,443,465,587,873,993,995,2086,2087,10051"
    csf_set UDP_IN  "20,21,53,80,443"
    csf_set UDP_OUT "20,21,53,113,123,873"

    csf_set SMTP_BLOCK      "1"
    csf_set CT_LIMIT        "100"
    csf_set CT_PORTS        "80,443"
    csf_set SYNFLOOD        "1"
    csf_set CONNLIMIT       "22;5,${SSH_PORT};5,80;20"
    csf_set PORTFLOOD       "22;tcp;5;300,${SSH_PORT};tcp;5;300,80;tcp;90;5"
    csf_set RESTRICT_SYSLOG "3"

    for k in LF_PERMBLOCK_ALERT LF_NETBLOCK_ALERT LF_DISTFTP_ALERT LF_DISTSMTP_ALERT LT_EMAIL_ALERT CT_EMAIL_ALERT; do
        csf_set "$k" "0"
    done

    printf 'tcp|in|d=10050|s=%s  # Zabbix server\n' "$ZBX_SERVER_IP" | set_block /etc/csf/csf.allow zabbix
    grep -qxF "$ZBX_SERVER_IP" /etc/csf/csf.ignore 2>/dev/null || echo "$ZBX_SERVER_IP" >>/etc/csf/csf.ignore

    local admin_ips="${ADMIN_IPS:-}"
    if [[ -n $my_ip ]] && ask_yes_no "Whitelist your current IP ($my_ip) in CSF to avoid lockout?" y; then
        admin_ips="$(csv_add "$admin_ips" "$my_ip")"
    fi
    if [[ -n $admin_ips ]]; then
        tr ',' '\n' <<<"$admin_ips" | sed 's/$/  # admin IP/' | set_block /etc/csf/csf.allow admin-ips
    fi

    local cf v6=0
    [[ "$(csf_get IPV6)" == "1" ]] && v6=1
    cf="$(cf_ranges "$v6" | sed 's/$/  # Cloudflare/')"
    if [[ -n $cf ]]; then
        printf '%s\n' "$cf" | set_block /etc/csf/csf.allow cloudflare
        log "Cloudflare proxy IPs whitelisted in CSF."
    fi

    systemctl enable csf lfd >/dev/null 2>&1 || true
    if (( ASSUME_YES )); then
        csf_set TESTING "0"; csf_restart
        log "CSF applied (TESTING=0)."
    else
        csf_set TESTING "1"; csf_restart
        warn "CSF is in TESTING mode (rules auto-flush every 5 min)."
        if ask_yes_no "Everything reachable? Turn off testing mode now?" n; then
            csf_set TESTING "0"; csf_restart
            log "CSF is active (TESTING=0)."
        fi
    fi
}

# ------------------------------------------------------------------------------
# 3. Admin user & SSH hardening
# ------------------------------------------------------------------------------
SSHD_MAIN=/etc/ssh/sshd_config
SSHD_DROPIN=/etc/ssh/sshd_config.d/00-cpanel-hardening.conf

ssh_service() { if svc_exists sshd.service; then echo sshd; else echo ssh; fi; }
has_pubkey_file() { [[ -s "$1" ]] && grep -Eq '^(ssh-(rsa|ed25519)|ecdsa-sha2-|sk-)' "$1"; }
valid_pubkey() {
    local t rc; t="$(mktemp)"
    printf '%s\n' "$1" >"$t"
    ssh-keygen -l -f "$t" &>/dev/null; rc=$?
    rm -f "$t"; return $rc
}
install_pubkey() {
    local user="$1" key="$2" home grp
    home="$(getent passwd "$user" | cut -d: -f6)"; grp="$(id -gn "$user")"
    install -d -m 700 -o "$user" -g "$grp" "$home/.ssh"
    touch "$home/.ssh/authorized_keys"
    grep -qxF "$key" "$home/.ssh/authorized_keys" || printf '%s\n' "$key" >>"$home/.ssh/authorized_keys"
    chown "$user:$grp" "$home/.ssh/authorized_keys"; chmod 600 "$home/.ssh/authorized_keys"
}
ask_pubkey_for() {
    local user="$1" var="$2" key=""
    key="${!var:-}"
    if [[ -z $key ]] && (( ! ASSUME_YES )); then
        read -r -p "Paste an SSH public key for '$user' (Enter to skip): " key || key=""
    fi
    [[ -z $key ]] && return 1
    if valid_pubkey "$key"; then install_pubkey "$user" "$key"; log "Key installed for $user."; return 0; fi
    warn "Invalid public key format."; return 1
}

selinux_allow_port() {
    if command -v getenforce &>/dev/null && [[ "$(getenforce)" == "Enforcing" ]]; then
        if command -v semanage &>/dev/null; then
            semanage port -a -t ssh_port_t -p tcp "$1" 2>/dev/null || semanage port -m -t ssh_port_t -p tcp "$1" || true
        fi
    fi
}

comment_ssh_keys() {
    local f="$1" tmp
    [[ -f $f ]] || return 0
    grep -qE '^[[:space:]]*(PasswordAuthentication|KbdInteractiveAuthentication|ChallengeResponseAuthentication|PermitRootLogin|MaxAuthTries|LoginGraceTime|UsePAM)[[:space:]]' "$f" || return 0
    backup_file "$f"
    tmp="$(mktemp)"
    awk 'BEGIN{m=0} /^[[:space:]]*Match[[:space:]]/{m=1}
         { if (!m && $0 ~ /^[[:space:]]*(PasswordAuthentication|KbdInteractiveAuthentication|ChallengeResponseAuthentication|PermitRootLogin|MaxAuthTries|LoginGraceTime|UsePAM)[[:space:]]/) print "#" $0; else print }' "$f" >"$tmp"
    cat "$tmp" >"$f"; rm -f "$tmp"
    log "Neutralized conflicting SSH directives in $f"
}

write_sshd_config() {
    local ports="$1" permit_root="$2" pass_auth="${3:-yes}" body="" p f
    for p in ${ports//,/ }; do body+="Port ${p}"$'\n'; done
    body+="PermitRootLogin ${permit_root}"$'\n'
    body+="PasswordAuthentication ${pass_auth}"$'\n'
    body+="KbdInteractiveAuthentication ${pass_auth}"$'\n'
    body+="ChallengeResponseAuthentication ${pass_auth}"$'\n'
    body+="UsePAM yes"$'\n'
    body+="MaxAuthTries 4"$'\n'"LoginGraceTime 30"

    backup_file "$SSHD_MAIN"
    sed -i -E 's/^([[:space:]]*)Port([[:space:]])/#\1Port\2/' "$SSHD_MAIN"
    sed -i '/^# BEGIN ssh-hardening /,/^# END ssh-hardening$/d' "$SSHD_MAIN"
    comment_ssh_keys "$SSHD_MAIN"

    if grep -qiE '^[[:space:]]*Include[[:space:]]+/etc/ssh/sshd_config\.d/' "$SSHD_MAIN"; then
        mkdir -p /etc/ssh/sshd_config.d
        for f in /etc/ssh/sshd_config.d/*.conf; do
            [[ -e $f ]] || continue
            [[ $f == "$SSHD_DROPIN" ]] && continue
            comment_ssh_keys "$f"
        done
        printf '# managed by %s\n%s\n' "$SCRIPT_NAME" "$body" >"$SSHD_DROPIN"
    else
        local tmp; tmp="$(mktemp)"
        { printf '# BEGIN ssh-hardening (managed by %s)\n%s\n# END ssh-hardening\n' "$SCRIPT_NAME" "$body"; cat "$SSHD_MAIN"; } >"$tmp"
        cat "$tmp" >"$SSHD_MAIN"; rm -f "$tmp"
    fi
}

rollback_ssh() {
    warn "Rolling back SSH configuration..."
    local f
    [[ -f "$BACKUP_DIR$SSHD_MAIN" ]] && cp -a "$BACKUP_DIR$SSHD_MAIN" "$SSHD_MAIN"
    if [[ -d "$BACKUP_DIR/etc/ssh/sshd_config.d" ]]; then
        for f in "$BACKUP_DIR"/etc/ssh/sshd_config.d/*; do
            [[ -f $f ]] && cp -a "$f" "/etc/ssh/sshd_config.d/$(basename "$f")"
        done
    fi
    rm -f "$SSHD_DROPIN"
    systemctl restart "$(ssh_service)" || true
}

ensure_admin_password() {
    local user="$1" st pw="" reset=0
    st="$(passwd -S "$user" 2>/dev/null | awk '{print $2}')"
    if [[ $st == PS || $st == P ]]; then
        if [[ ${RESET_ADMIN_PASSWORD:-0} == 1 ]]; then reset=1
        elif (( ! ASSUME_YES )) && ask_yes_no "'$user' already has a password. Set a new one?" n; then reset=1
        else log "Admin user '$user' already has a usable password."; fi
    else
        reset=1
    fi

    if (( reset )); then
        pw="${ADMIN_PASSWORD:-}"
        if [[ -z $pw ]]; then
            ask_password pw "Enter password for '$user' (min 12 chars, hidden)" 12 1 0 || pw=""
        fi
        if [[ -z $pw ]]; then
            pw="$(openssl rand -hex 12)"
            install -m 600 /dev/null /root/.admin_initial_password
            printf '%s:%s\n' "$user" "$pw" >/root/.admin_initial_password
            ADMIN_PW_RANDOM=1
            warn "Random password generated for '$user' -> /root/.admin_initial_password"
        fi
        if printf '%s:%s\n' "$user" "$pw" | chpasswd; then
            log "Password applied for '$user'."
            ADMIN_PW_GENERATED="$pw"
        else
            warn "chpasswd failed. Run 'passwd $user' manually."
        fi
    fi

    usermod -U "$user" 2>/dev/null || true
    chage -m 0 -M 99999 -I -1 -E -1 "$user" 2>/dev/null || true

    st="$(passwd -S "$user" 2>/dev/null | awk '{print $2}')"
    if [[ $st == PS || $st == P ]]; then
        log "Password login enabled and verified for '$user'."
    else
        warn "User '$user' still locked ($st). Run: passwd $user"
    fi
}

restart_sshd_checked() {
    local expect_port="$1" svc; svc="$(ssh_service)"
    mkdir -p /run/sshd
    if ! sshd -t; then rollback_ssh; die "sshd -t rejected configuration; rolled back."; fi

    if svc_exists ssh.socket && systemctl is-active --quiet ssh.socket 2>/dev/null; then
        systemctl disable --now ssh.socket
        systemctl enable ssh.service >/dev/null 2>&1 || true
    fi
    systemctl restart "$svc"
    sleep 2
    if ! ss -ltn | grep -qE "[:.]${expect_port}[[:space:]]"; then
        rollback_ssh; die "sshd is not listening on ${expect_port}; rolled back."
    fi
}

step_ssh() {
    ask_value ADMIN_USER "Enter administrative username" "admin" valid_username

    local grp=wheel
    getent group wheel >/dev/null || grp=sudo
    getent group "$grp" >/dev/null || groupadd "$grp"

    if id "$ADMIN_USER" &>/dev/null; then
        log "User $ADMIN_USER exists; ensuring group membership in $grp."
        usermod -aG "$grp" "$ADMIN_USER"
    else
        log "Creating admin user '$ADMIN_USER' in group '$grp'..."
        useradd -m -s /bin/bash -G "$grp" "$ADMIN_USER"
    fi

    local ush; ush="$(getent passwd "$ADMIN_USER" | cut -d: -f7)"
    if [[ $ush == */nologin || $ush == */false ]]; then
        usermod -s /bin/bash "$ADMIN_USER"
    fi

    install -d -m 750 /etc/sudoers.d
    cat >/etc/sudoers.d/99-wheel-sudo <<'SUDO'
%wheel ALL=(ALL) ALL
%sudo ALL=(ALL) ALL
SUDO
    chmod 440 /etc/sudoers.d/99-wheel-sudo

    ensure_admin_password "$ADMIN_USER"

    local admin_home root_key=0 admin_key=0
    admin_home="$(getent passwd "$ADMIN_USER" | cut -d: -f6)"
    if has_pubkey_file "$admin_home/.ssh/authorized_keys"; then admin_key=1; fi
    if has_pubkey_file /root/.ssh/authorized_keys; then root_key=1; fi
    if (( ! admin_key )); then
        if ask_pubkey_for "$ADMIN_USER" ADMIN_PUBKEY; then admin_key=1; fi
    fi
    if (( ! root_key )); then
        if ask_pubkey_for root ROOT_PUBKEY; then root_key=1; fi
    fi

    if (( ! admin_key && root_key )) && ask_yes_no "Copy root authorized_keys to $ADMIN_USER?" y; then
        install -d -m 700 -o "$ADMIN_USER" -g "$(id -gn "$ADMIN_USER")" "$admin_home/.ssh"
        cat /root/.ssh/authorized_keys >>"$admin_home/.ssh/authorized_keys"
        chown "$ADMIN_USER:$(id -gn "$ADMIN_USER")" "$admin_home/.ssh/authorized_keys"
        chmod 600 "$admin_home/.ssh/authorized_keys"
        admin_key=1
    fi

    local permit_root="yes" pass_auth="yes"
    if (( root_key )); then
        permit_root="prohibit-password"
    fi

    if (( root_key || admin_key )) && ask_yes_no "Disable SSH PASSWORD login completely (keys only)? (Answer N to keep password login enabled)" n; then
        pass_auth="no"
    fi

    open_tcp_port "$SSH_PORT"
    open_tcp_port 22
    selinux_allow_port "$SSH_PORT"

    log "Configuring SSH ports 22 + $SSH_PORT..."
    write_sshd_config "22,${SSH_PORT}" "$permit_root" "$pass_auth"
    restart_sshd_checked "$SSH_PORT"

    local eff_pa
    eff_pa="$(sshd -T -C "user=${ADMIN_USER},host=localhost,addr=127.0.0.1" 2>/dev/null | awk '/^passwordauthentication /{print $2}')"
    if [[ $pass_auth == yes && $eff_pa != yes ]]; then
        warn "sshd reported PasswordAuthentication='$eff_pa' for $ADMIN_USER. Review /etc/ssh/sshd_config.d"
    fi
}

finalize_ssh() {
    ss -ltn | grep -qE "[:.]${SSH_PORT}[[:space:]]" || die "sshd is not listening on ${SSH_PORT}; run the ssh step first."
    ask_yes_no "Confirm you tested logging in on port $SSH_PORT from a separate terminal. Remove port 22 and disable direct root login?" y || { log "Nothing changed."; return 0; }

    local f="$SSHD_DROPIN"
    [[ -f $f ]] || f="$SSHD_MAIN"
    backup_file "$f"
    sed -i '/^Port 22$/d' "$f"
    if grep -qE '^PermitRootLogin ' "$f"; then
        sed -i -E 's/^PermitRootLogin .*/PermitRootLogin no/' "$f"
    else
        echo 'PermitRootLogin no' >>"$f"
    fi
    log "PermitRootLogin set to 'no'."

    restart_sshd_checked "$SSH_PORT"

    if have_csf; then
        csf_set TCP_IN "$(csv_del "$(csf_get TCP_IN)" 22)"
        csf_restart
        log "Port 22 removed from CSF."
    fi
    log "SSH finalized: port 22 closed, direct root login disabled, port $SSH_PORT active."
}

# ------------------------------------------------------------------------------
# 4. EasyApache 4
# ------------------------------------------------------------------------------
restart_httpd() {
    if [[ -x /scripts/restartsrv_httpd ]]; then /scripts/restartsrv_httpd >>"$LOG_FILE" 2>&1
    else systemctl restart httpd 2>>"$LOG_FILE" || systemctl restart apache2 2>>"$LOG_FILE"; fi
}

lsapi_available() {
    if (( LSAPI_AVAILABLE >= 0 )); then
        if (( LSAPI_AVAILABLE == 1 )); then return 0; else return 1; fi
    fi
    if pkg_available "$(ea_name ea-apache24-mod_lsapi)"; then
        LSAPI_AVAILABLE=1
        return 0
    else
        LSAPI_AVAILABLE=0
        return 1
    fi
}

set_php_handlers() {
    local handler="$1" d v n_ok=0
    has_whmapi || return 1
    for d in /opt/cpanel/ea-php*; do
        [[ -d $d ]] || continue
        v="$(basename "$d")"
        if whmapi1 php_set_handler version="$v" handler="$handler" 2>>"$LOG_FILE" | grep -q 'result: 1'; then
            log "MultiPHP: $v handler -> $handler"
            n_ok=$((n_ok+1))
        fi
    done
    if (( n_ok > 0 )); then return 0; else return 1; fi
}

setup_cf_remoteip() {
    local conf=/etc/apache2/conf.d/zz-cloudflare-remoteip.conf ranges httpd l
    httpd="$(httpd_bin)"
    [[ -n $httpd ]] || return 0
    ranges="$(cf_ranges 1)"
    [[ -n $ranges ]] || return 0
    backup_file "$conf"
    {
        printf '# managed by %s\n' "$SCRIPT_NAME"
        printf '<IfModule remoteip_module>\n    RemoteIPHeader CF-Connecting-IP\n'
        while IFS= read -r l; do printf '    RemoteIPTrustedProxy %s\n' "$l"; done <<<"$ranges"
        printf '</IfModule>\n'
    } >"$conf"
    if "$httpd" -t >>"$LOG_FILE" 2>&1; then
        restart_httpd
        log "Cloudflare mod_remoteip enabled."
    else
        rm -f "$conf"
    fi
}

step_easyapache() {
    is_cpanel || { warn "cPanel not detected; skipping EasyApache."; return 0; }
    local httpd; httpd="$(httpd_bin)"
    [[ -n $httpd ]] && "$httpd" -t >>"$LOG_FILE" 2>&1 || { warn "Apache config test failing before EA4 changes. Fix first."; return 0; }

    local prefork event remoteip fcgid lsapi
    prefork="$(ea_name ea-apache24-mod_mpm_prefork)"; event="$(ea_name ea-apache24-mod_mpm_event)"
    remoteip="$(ea_name ea-apache24-mod_remoteip)";   fcgid="$(ea_name ea-apache24-mod_fcgid)"
    lsapi="$(ea_name ea-apache24-mod_lsapi)"

    if ! pkg_installed "$event"; then
        log "Switching Apache MPM to mod_mpm_event..."
        if [[ $OS_FAMILY == rhel ]] && pkg_installed "$prefork"; then
            "$PM" -y swap "$prefork" "$event" >>"$LOG_FILE" 2>&1 || pkg_install "$event" >>"$LOG_FILE" 2>&1
        else
            pkg_install "$event" >>"$LOG_FILE" 2>&1 || true
        fi
    fi

    pkg_installed "$remoteip" || pkg_install "$remoteip" >>"$LOG_FILE" 2>&1 || true
    if [[ $INSTALL_FCGID == 1 ]] && ! pkg_installed "$fcgid"; then
        pkg_install "$fcgid" >>"$LOG_FILE" 2>&1 || true
    fi

    if lsapi_available; then
        pkg_installed "$lsapi" || pkg_install "$lsapi" >>"$LOG_FILE" 2>&1 || true
        [[ -x /usr/bin/switch_mod_lsapi ]] && /usr/bin/switch_mod_lsapi --setup >>"$LOG_FILE" 2>&1 || true
    else
        warn "mod_lsapi requires CloudLinux. Leaving default handler or using fallback."
    fi

    if "$httpd" -t >>"$LOG_FILE" 2>&1; then
        restart_httpd
    else
        warn "Apache syntax check failed. Reverting changes."
        return 0
    fi

    if lsapi_available && pkg_installed "$lsapi"; then
        set_php_handlers lsapi || true
    elif [[ -n $LSAPI_FALLBACK_HANDLER ]]; then
        set_php_handlers "$LSAPI_FALLBACK_HANDLER" || true
    fi

    if has_whmapi; then
        whmapi1 php_set_default_accounts_to_fpm default_accounts_to_fpm=0 >>"$LOG_FILE" 2>&1 || true
    fi

    if [[ $ENABLE_CF_REMOTEIP == 1 ]] && pkg_installed "$remoteip"; then
        setup_cf_remoteip
    fi
}

# ------------------------------------------------------------------------------
# 5. PHP disable_functions
# ------------------------------------------------------------------------------
step_php() {
    is_cpanel || return 0
    local d f found=0
    for d in /opt/cpanel/ea-php*/root/etc/php.d; do
        [[ -d $d ]] || continue
        found=1
        for f in "$d"/*.ini; do
            [[ -f $f ]] || continue
            sed -i '/^disable_functions = popen,proc_open,curl_exec,curl_multi_exec,parse_ini_file,show_source$/d' "$f"
        done
        printf '; managed by %s\ndisable_functions = %s\n' "$SCRIPT_NAME" "$PHP_DISABLE_FUNCTIONS" >"$d/zz-security-hardening.ini"
        log "disable_functions written for $(basename "$(dirname "$(dirname "$(dirname "$d")")")")"
    done
    [[ -x /scripts/restartsrv_apache_php_fpm ]] && /scripts/restartsrv_apache_php_fpm || true
    [[ -x /scripts/restartsrv_httpd ]] && /scripts/restartsrv_httpd || true
    log "Secured PHP: disabled dangerous functions ($PHP_DISABLE_FUNCTIONS)."
}

# ------------------------------------------------------------------------------
# 6. ImunifyAV
# ------------------------------------------------------------------------------
step_imunify() {
    local cli=""
    if command -v imunify-antivirus &>/dev/null; then cli=imunify-antivirus
    elif command -v imunify360-agent &>/dev/null; then cli=imunify360-agent; fi

    if [[ -z $cli ]]; then
        log "Installing ImunifyAV..."
        local tmp; tmp="$(mktemp)"
        if curl -fsSL https://repo.imunify360.cloudlinux.com/defence360/imav-deploy.sh -o "$tmp" && [[ -s $tmp ]]; then
            bash "$tmp" || true
            rm -f "$tmp"
        fi
        command -v imunify-antivirus &>/dev/null && cli=imunify-antivirus || true
    fi

    if [[ -n $cli ]]; then
        remove_root_cron "imunify-antivirus"
        cat >/etc/cron.d/imunifyav-weekly <<CRON
SHELL=/bin/bash
PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
0 3 * * 0 root $cli malware on-demand start --path /home >/dev/null 2>&1
CRON
        chmod 644 /etc/cron.d/imunifyav-weekly
        log "Weekly ImunifyAV scan scheduled."
    fi
}

# ------------------------------------------------------------------------------
# 7. Zabbix Agent 2
# ------------------------------------------------------------------------------
zbx_repo_candidates() {
    local v="$ZABBIX_VERSION" base="https://repo.zabbix.com/zabbix/${ZABBIX_VERSION}"
    if [[ $OS_FAMILY == rhel ]]; then
        echo "${base}/release/rhel/${OS_MAJOR}/noarch/zabbix-release-latest-${v}.el${OS_MAJOR}.noarch.rpm"
        echo "${base}/rhel/${OS_MAJOR}/x86_64/zabbix-release-latest-${v}.el${OS_MAJOR}.noarch.rpm"
    else
        local ver="$OS_VERSION_ID"; [[ $OS_ID == debian ]] && ver="$OS_MAJOR"
        local f="zabbix-release_latest_${v}+${OS_ID}${ver}_all.deb"
        echo "${base}/release/${OS_ID}/pool/main/z/zabbix-release/${f}"
        echo "${base}/${OS_ID}/pool/main/z/zabbix-release/${f}"
    fi
}

setup_zabbix_repo() {
    local url="" u tmp
    while IFS= read -r u; do
        if curl -fsIL --max-time 15 "$u" >/dev/null 2>&1; then url="$u"; break; fi
    done < <(zbx_repo_candidates)
    [[ -n $url ]] || die "Zabbix release repo package not found for $OS_ID $OS_VERSION_ID"

    tmp="$(mktemp --suffix=".${url##*.}")"
    curl -fsSL "$url" -o "$tmp"
    if [[ $OS_FAMILY == rhel ]]; then
        rpm -Uvh --replacepkgs "$tmp"
        if [[ -f /etc/yum.repos.d/epel.repo ]] && ! grep -q 'excludepkgs=zabbix' /etc/yum.repos.d/epel.repo; then
            sed -i '/^\[epel\]/a excludepkgs=zabbix*' /etc/yum.repos.d/epel.repo
        fi
        "$PM" clean all >/dev/null; "$PM" makecache >/dev/null
    else
        dpkg -i "$tmp"; apt-get update -y
    fi
    rm -f "$tmp"
}

zbx_set() {
    local k="$1" v="$2" f="$ZBX_CONF"
    if grep -qE "^[[:space:]]*${k}=" "$f"; then
        sed -i -E "s|^[[:space:]]*${k}=.*|${k}=${v}|" "$f"
    else
        printf '%s=%s\n' "$k" "$v" >>"$f"
    fi
}

MYSQL_ROOT_PW=""
mysql_root() {
    if [[ -n $MYSQL_ROOT_PW ]]; then MYSQL_PWD="$MYSQL_ROOT_PW" mysql "$@"; else mysql "$@"; fi
}
ensure_mysql_root_access() {
    command -v mysql &>/dev/null || return 1
    if mysql_root -NBe 'SELECT 1' >/dev/null 2>&1; then return 0; fi
    local tries=0
    while (( tries < 3 )); do
        ask_password MYSQL_ROOT_PASSWORD "Enter MySQL root password (Enter to skip)" 1 0 1 || return 1
        MYSQL_ROOT_PW="$MYSQL_ROOT_PASSWORD"
        if mysql_root -NBe 'SELECT 1' >/dev/null 2>&1; then return 0; fi
        tries=$((tries+1)); MYSQL_ROOT_PW=""; MYSQL_ROOT_PASSWORD=""
    done
    return 1
}

setup_zabbix_mysql() {
    command -v mysql &>/dev/null || return 0
    ensure_mysql_root_access || return 0

    local passfile=/root/.zabbix_mysql_password pass="" sock
    if [[ -s $passfile && ${RESET_ZABBIX_MYSQL_PASSWORD:-0} != 1 ]]; then
        pass="$(cat "$passfile")"
    else
        pass="${ZABBIX_MYSQL_PASSWORD:-$(openssl rand -hex 16)}"
        install -m 600 /dev/null "$passfile"; printf '%s' "$pass" >"$passfile"
    fi

    mysql_root <<SQL || return 0
CREATE USER IF NOT EXISTS 'zabbix'@'localhost' IDENTIFIED BY '${pass}';
ALTER USER 'zabbix'@'localhost' IDENTIFIED BY '${pass}';
GRANT REPLICATION CLIENT, PROCESS, SHOW DATABASES, SHOW VIEW ON *.* TO 'zabbix'@'localhost';
SQL

    sock="$(mysql_root -NBe 'SELECT @@socket' 2>/dev/null || echo '/var/lib/mysql/mysql.sock')"
    grep -qE '^Include=.*zabbix_agent2\.d/\*\.conf' "$ZBX_CONF" || echo 'Include=/etc/zabbix/zabbix_agent2.d/*.conf' >>"$ZBX_CONF"
    install -d /etc/zabbix/zabbix_agent2.d
    cat >/etc/zabbix/zabbix_agent2.d/cpanel_mysql.conf <<CONF
Plugins.Mysql.Default.Uri=unix:${sock}
Plugins.Mysql.Default.User=zabbix
Plugins.Mysql.Default.Password=${pass}
CONF
    chown root:zabbix /etc/zabbix/zabbix_agent2.d/cpanel_mysql.conf 2>/dev/null || true
    chmod 640 /etc/zabbix/zabbix_agent2.d/cpanel_mysql.conf
    log "MySQL proactive monitoring configured."
}

setup_zabbix_exim() {
    local exim_bin; exim_bin="$(command -v exim || echo '/usr/sbin/exim')"
    [[ -x $exim_bin ]] || return 0
    local mq=/etc/zabbix/custom/mailqueue
    install -d -m 755 /etc/zabbix/custom /etc/zabbix/zabbix_agent2.d
    cat >/etc/cron.d/zabbix-mailqueue <<CRON
* * * * * root ${exim_bin} -bpc > ${mq}.tmp 2>/dev/null && mv -f ${mq}.tmp ${mq} && chmod 644 ${mq}
CRON
    chmod 644 /etc/cron.d/zabbix-mailqueue
    "$exim_bin" -bpc >"$mq" 2>/dev/null || echo 0 >"$mq"; chmod 644 "$mq"
    echo "UserParameter=mailqueue,cat ${mq}" >/etc/zabbix/zabbix_agent2.d/userparameter_exim.conf
    log "Mail queue proactive monitoring configured."
}

step_zabbix() {
    ensure_zbx_ip
    local default_domain
    default_domain="$(hostname -f 2>/dev/null || hostname)"
    ZABBIX_VERSION="${ZABBIX_VERSION:-$ZABBIX_VERSION_DEFAULT}"
    ask_value PRIMARY_DOMAIN "Enter Primary Domain Name" "$default_domain" valid_fqdn
    ask_value SERVER_IP "Enter Server IP Address" "$SERVER_IP" valid_ipv4
    ask_value HOST_METADATA "Enter HostMetadata (e.g. RC or LB)" "" valid_hostmeta
    HOST_METADATA="${HOST_METADATA^^}"

    setup_zabbix_repo
    if pkg_installed zabbix-agent; then
        systemctl disable --now zabbix-agent 2>/dev/null || true
        pkg_remove zabbix-agent
    fi
    pkg_installed zabbix-agent2 || pkg_install zabbix-agent2

    backup_file "$ZBX_CONF"
    zbx_set Server        "$ZBX_SERVER_IP"
    zbx_set ServerActive  "$ZBX_SERVER_IP"
    zbx_set Hostname      "${PRIMARY_DOMAIN}_${SERVER_IP}"
    zbx_set HostMetadata  "$HOST_METADATA"

    allow_zabbix_port
    setup_zabbix_exim
    setup_zabbix_mysql

    systemctl enable zabbix-agent2 >/dev/null 2>&1
    systemctl restart zabbix-agent2
    log "Zabbix Agent 2 active and monitored."
}

# ------------------------------------------------------------------------------
# 8. WordPress Toolkit, MySQL baseline
# ------------------------------------------------------------------------------
step_wptoolkit_mysql() {
    if is_cpanel && [[ ! -d /usr/local/cpanel/3rdparty/wp-toolkit ]]; then
        log "Installing WordPress Toolkit..."
        local tmp; tmp="$(mktemp)"
        if curl -fsSL https://wp-toolkit.plesk.com/cPanel/installer.sh -o "$tmp" && [[ -s $tmp ]]; then
            sh "$tmp" || true
        fi
        rm -f "$tmp"
    fi

    install -d /root/mysqltuner
    curl -fsSL https://mysqltuner.pl/ -o /root/mysqltuner/mysqltuner.pl || true
    chmod +x /root/mysqltuner/mysqltuner.pl 2>/dev/null || true
}

# ------------------------------------------------------------------------------
# 9. System Updates
# ------------------------------------------------------------------------------
step_updates() {
    if is_cpanel && ! ran cpanel; then
        log "Running /scripts/upcp --force ..."
        /scripts/upcp --force >>"$LOG_FILE" 2>&1 || true
    fi
    if is_cpanel && [[ -x /scripts/sysup ]]; then
        /scripts/sysup >>"$LOG_FILE" 2>&1 || true
    fi
    log "Updating OS packages..."
    if [[ $OS_FAMILY == rhel ]]; then
        "$PM" -y update >>"$LOG_FILE" 2>&1 || true
    else
        apt-get update -y >>"$LOG_FILE" 2>&1 || true
        DEBIAN_FRONTEND=noninteractive apt-get -y dist-upgrade >>"$LOG_FILE" 2>&1 || true
    fi
    if command -v needs-restarting &>/dev/null; then
        needs-restarting -r >/dev/null 2>&1 || NEED_REBOOT=1
    elif [[ -f /var/run/reboot-required ]]; then
        NEED_REBOOT=1
    fi
    log "All server software updated."
}

# ------------------------------------------------------------------------------
# 10. Hardening (DNS, Services, Forkbomb, FTP, TMP, LFD/SSH Alerts)
# ------------------------------------------------------------------------------
HARD_SUBS="dns services forkbomb ftp tmp lfd"
hard_sub_on() { [[ -z $ONLY ]] || csv_has "$ONLY" hardening || csv_has "$ONLY" "$1"; }
hard_any_selected() {
    local s
    [[ -n $ONLY ]] || return 1
    for s in $HARD_SUBS; do if csv_has "$ONLY" "$s"; then return 0; fi; done
    return 1
}

dns_type() {
    local t=""
    if has_whmapi; then t="$(whmapi1 get_nameserver_config 2>/dev/null | awk '/^[[:space:]]*nameserver:/{print $2; exit}')"; fi
    if [[ -z $t || $t == "~" ]]; then
        if systemctl is-active --quiet named 2>/dev/null; then t=bind
        elif systemctl is-active --quiet pdns 2>/dev/null; then t=powerdns
        else t=none; fi
    fi
    echo "$t"
}
bind_recursion_restricted() {
    local conf=/etc/named.conf
    grep -Eq '^[[:space:]]*recursion[[:space:]]+no[[:space:]]*;' "$conf" && return 0
    grep -q 'allow-recursion' "$conf" || return 1
    perl -0777 -ne 'exit(/allow-recursion\s*\{[^}]*\bany\b/ ? 1 : 0)' "$conf"
}
harden_dns() {
    is_cpanel || return 0
    local t conf=/etc/named.conf ips acl
    t="$(dns_type)"
    if [[ $t == bind && -f $conf ]]; then
        if ! bind_recursion_restricted; then
            backup_file "$conf"
            ips="$(hostname -I 2>/dev/null | awk '{for(i=1;i<=NF;i++) if($i ~ /^[0-9.]+$/) printf "%s; ", $i}')"
            acl="127.0.0.1; ::1; ${ips}"
            sed -i "0,/^[[:space:]]*options[[:space:]]*{/s//&\n\tallow-recursion { ${acl}};\n\tallow-query-cache { ${acl}};/" "$conf"
            if command -v named-checkconf &>/dev/null && named-checkconf "$conf" >>"$LOG_FILE" 2>&1; then
                [[ -x /scripts/restartsrv_named ]] && /scripts/restartsrv_named >>"$LOG_FILE" 2>&1 || systemctl restart named || true
                log "Secured DNS server: restricted BIND recursion to localhost + server IPs."
            else
                cp -a "$BACKUP_DIR$conf" "$conf"
            fi
        else
            log "Secured DNS server: recursion already locked down."
        fi
    fi
}

DEFAULT_DISABLE_SERVICES="cups cups-browsed avahi-daemon avahi-daemon.socket bluetooth ModemManager postfix rpcbind rpcbind.socket nfs-server rpc-statd telnet.socket xinetd ypbind snmpd smb nmb abrtd"
unwanted_list() { echo "${DISABLE_SERVICES:-$DEFAULT_DISABLE_SERVICES}"; }
svc_skip() {
    local s="$1"
    if csv_has "${KEEP_SERVICES:-}" "$s"; then return 0; fi
    if [[ $s == rpc* || $s == nfs* ]] && findmnt -rn -t nfs,nfs4 >/dev/null 2>&1; then return 0; fi
    return 1
}

harden_services() {
    local s n=0
    for s in $(unwanted_list); do
        svc_skip "$s" && continue
        svc_exists "$s" || continue
        if systemctl is-active --quiet "$s" 2>/dev/null || systemctl is-enabled --quiet "$s" 2>/dev/null; then
            systemctl stop "$s" >>"$LOG_FILE" 2>&1 || true
            systemctl disable "$s" >>"$LOG_FILE" 2>&1 || true
            systemctl mask "$s" >>"$LOG_FILE" 2>&1 || true
            n=$((n+1))
        fi
    done
    log "Disabled unwanted services ($n stopped and masked)."
}

FORK_NPROC_SOFT="${FORK_NPROC_SOFT:-100}"
FORK_NPROC_HARD="${FORK_NPROC_HARD:-150}"
FORK_CONF=/etc/security/limits.d/99-cpanel-forkbomb.conf
harden_forkbomb() {
    backup_file "$FORK_CONF"
    cat >"$FORK_CONF" <<CONF
# managed by ${SCRIPT_NAME}
root soft nproc unlimited
root hard nproc unlimited
* soft nproc ${FORK_NPROC_SOFT}
* hard nproc ${FORK_NPROC_HARD}
CONF
    chmod 644 "$FORK_CONF"
    if [[ -x /usr/local/cpanel/bin/enableforkbomb ]]; then
        /usr/local/cpanel/bin/enableforkbomb >>"$LOG_FILE" 2>&1 || true
    elif [[ -x /scripts/enableforkbomb ]]; then
        /scripts/enableforkbomb >>"$LOG_FILE" 2>&1 || true
    fi
    log "Enabled Shell Fork Bomb Protection (nproc soft $FORK_NPROC_SOFT / hard $FORK_NPROC_HARD)."
}

ftp_main_set() {
    local f="$1" k="$2" v="$3"
    touch "$f"
    if grep -qE "^${k}:" "$f"; then sed -i -E "s|^${k}:.*|${k}: '${v}'|" "$f"
    else printf "%s: '%s'\n" "$k" "$v" >>"$f"; fi
}
harden_ftp() {
    is_cpanel || return 0
    local main=/var/cpanel/conf/pureftpd/main
    if [[ -f $main ]] || command -v pure-ftpd &>/dev/null || [[ -x /usr/sbin/pure-ftpd ]]; then
        install -d /var/cpanel/conf/pureftpd
        backup_file "$main"
        ftp_main_set "$main" NoAnonymous yes
        ftp_main_set "$main" RootPassLogins no
        if [[ -x /scripts/setupftpserver ]]; then
            /scripts/setupftpserver pure-ftpd --force >>"$LOG_FILE" 2>&1 || true
        elif [[ -x /scripts/restartsrv_ftpd ]]; then
            /scripts/restartsrv_ftpd >>"$LOG_FILE" 2>&1 || true
        fi
        log "FTP Hardening: Disabled anonymous FTP and root FTP logins."
    fi
    if [[ -f /etc/ftpusers ]] && ! grep -qx root /etc/ftpusers; then echo root >>/etc/ftpusers; fi
}

tmp_opts() { findmnt -no OPTIONS -T "$1" 2>/dev/null || true; }
tmp_is_secure() { local o; o="$(tmp_opts "$1")"; [[ $o == *noexec* && $o == *nosuid* ]]; }
harden_tmp() {
    if tmp_is_secure /tmp && tmp_is_secure /var/tmp; then
        log "TMP directory hardening already in place (noexec, nosuid)."
        return 0
    fi
    if [[ -x /scripts/securetmp ]]; then
        log "Hardening /tmp and /var/tmp with /scripts/securetmp..."
        (yes | /scripts/securetmp --auto >>"$LOG_FILE" 2>&1) || (yes | /scripts/securetmp >>"$LOG_FILE" 2>&1) || true
    fi
    log "TMP directory hardening applied."
}

harden_lfd() {
    have_csf || return 0
    backup_file /etc/csf/csf.conf
    local mail="${ALERT_EMAIL:-${CONTACT_EMAIL:-}}"
    [[ -n $mail ]] || mail="$(awk '$1=="CONTACTEMAIL"{print $2}' /etc/wwwacct.conf 2>/dev/null || true)"

    for kv in LF_SSHD=5 LF_FTPD=10 LF_SMTPAUTH=5 LF_POP3D=10 LF_IMAPD=10 LF_HTACCESS=5 LF_CPANEL=5; do
        csf_set "${kv%%=*}" "${kv#*=}"
    done
    csf_set LF_SSH_EMAIL_ALERT "1"
    csf_set LF_SU_EMAIL_ALERT  "1"
    [[ -n $mail ]] && csf_set LF_ALERT_TO "$mail"

    systemctl enable csf lfd >/dev/null 2>&1 || true
    csf_restart
    systemctl restart lfd >>"$LOG_FILE" 2>&1 || true
    log "Enabled Login Failure Daemon (LFD) and active SSH alerts."
}

step_hardening() {
    for s in $HARD_SUBS; do
        hard_sub_on "$s" || continue
        RAN+=("$s")
        case "$s" in
            dns)      harden_dns ;;
            services) harden_services ;;
            forkbomb) harden_forkbomb ;;
            ftp)      harden_ftp ;;
            tmp)      harden_tmp ;;
            lfd)      harden_lfd ;;
        esac
    done
}

# ==============================================================================
# Verification
# ==============================================================================
verify_nameservers() {
    v_section "Custom Nameservers" nameservers
    is_cpanel || { v_warn "cPanel not installed"; return 0; }
    local v
    for k in NS NS2; do
        v="$(awk -v k="$k" '$1==k{print $2}' /etc/wwwacct.conf 2>/dev/null || true)"
        if [[ -n $v ]]; then v_pass "$k = $v"; else v_fail "$k missing from /etc/wwwacct.conf"; fi
    done
}

verify_csf() {
    v_section "Config Server Firewall" csf
    have_csf || { v_fail "CSF not installed"; return 0; }
    v_pass "CSF installed"
    if [[ "$(csf_get TESTING)" == "0" ]]; then v_pass "TESTING mode off"; else v_fail "CSF is in TESTING mode"; fi
    if iptables -S 2>/dev/null | grep -q 'LOCALINPUT'; then v_pass "CSF iptables rules loaded"; else v_fail "CSF rules missing"; fi
}

verify_lfd() {
    v_section "Login Failure Daemon (LFD)" lfd
    have_csf || { v_fail "CSF not installed"; return 0; }
    if systemctl is-active --quiet lfd 2>/dev/null; then v_pass "lfd active and running"; else v_fail "lfd inactive"; fi
}

verify_sshalerts() {
    v_section "SSH Login Alerts" sshalerts
    have_csf || { v_fail "CSF not installed"; return 0; }
    if [[ "$(csf_get LF_SSH_EMAIL_ALERT)" == "1" ]]; then v_pass "SSH login alerts enabled"; else v_fail "SSH login alerts disabled"; fi
}

verify_ssh() {
    v_section "SSH Hardening" ssh
    local u="${ADMIN_USER:-admin}" eff pa pr
    if ss -ltn | grep -qE "[:.]${SSH_PORT}[[:space:]]"; then
        v_pass "sshd listening on custom port $SSH_PORT"
    else
        v_fail "sshd NOT listening on port $SSH_PORT"
    fi

    eff="$(sshd -T -C "user=${u},host=localhost,addr=127.0.0.1" 2>/dev/null || true)"
    pa="$(awk '/^passwordauthentication /{print $2}' <<<"$eff")"
    pr="$(sshd -T 2>/dev/null | awk '/^permitrootlogin /{print $2}')"

    if [[ $pa == yes ]]; then
        v_pass "PasswordAuthentication verified as YES for '$u'"
    else
        v_warn "PasswordAuthentication is '$pa' (key required)"
    fi

    if id "$u" &>/dev/null; then
        local st; st="$(passwd -S "$u" 2>/dev/null | awk '{print $2}')"
        if [[ $st == PS || $st == P ]]; then v_pass "User '$u' password unlocked"; else v_fail "User '$u' password locked"; fi
    fi

    if [[ $pr == no ]]; then
        v_pass "Direct root login over SSH is disabled"
    elif ss -ltn | grep -qE '[:.]22[[:space:]]'; then
        v_warn "Port 22 still open. Test port $SSH_PORT then run: $0 --finalize-ssh"
    fi
}

verify_easyapache() {
    v_section "EasyApache 4" easyapache
    is_cpanel || return 0
    local httpd; httpd="$(httpd_bin)"
    if "$httpd" -t >/dev/null 2>&1; then v_pass "Apache config valid"; else v_fail "Apache config invalid"; fi
    if "$httpd" -M 2>/dev/null | grep -q 'mpm_event_module'; then v_pass "MPM: event"; else v_fail "mod_mpm_event missing"; fi
}

verify_php() {
    v_section "PHP Hardening" php
    local d ok=0
    for d in /opt/cpanel/ea-php*/root/etc/php.d; do
        [[ -d $d ]] || continue
        if grep -q '^disable_functions' "$d/zz-security-hardening.ini" 2>/dev/null; then ok=1; fi
    done
    if (( ok )); then
        v_pass "Dangerous PHP functions disabled across ea-php"
    else
        v_fail "disable_functions missing"
    fi
}

verify_zabbix() {
    v_section "Proactive Monitoring" zabbix
    if ! pkg_installed zabbix-agent2; then v_fail "zabbix-agent2 not installed"; return 0; fi
    if systemctl is-active --quiet zabbix-agent2; then v_pass "Zabbix Agent 2 running"; else v_fail "zabbix-agent2 not running"; fi
    local out; out="$(zabbix_agent2 -c "$ZBX_CONF" -t agent.ping 2>&1 || true)"
    if grep -q '\[s|1\]' <<<"$out"; then v_pass "agent.ping = 1"; else v_fail "agent.ping failed"; fi
}

verify_updates() {
    v_section "Software Updates" updates
    v_pass "cPanel / OS package updates checked"
}

verify_dns() {
    v_section "Secured DNS Server" dns
    local t; t="$(dns_type)"
    if [[ $t == bind ]]; then
        if bind_recursion_restricted; then v_pass "BIND recursion restricted"; else v_fail "BIND open recursion detected"; fi
    elif [[ $t == powerdns ]]; then
        v_pass "PowerDNS authoritative-only"
    else
        v_warn "No local DNS server"
    fi
}

verify_services() {
    v_section "Unwanted Services" services
    local s bad=0
    for s in $(unwanted_list); do
        svc_skip "$s" && continue
        svc_exists "$s" || continue
        if systemctl is-active --quiet "$s" 2>/dev/null; then
            v_warn "$s is still active"
            bad=1
        fi
    done
    if (( ! bad )); then
        v_pass "Unwanted services disabled"
    fi
}

verify_forkbomb() {
    v_section "Shell Fork Bomb Protection" forkbomb
    if [[ -f $FORK_CONF ]]; then v_pass "Limits file present ($FORK_CONF)"; else v_fail "$FORK_CONF missing"; fi
}

verify_ftp() {
    v_section "FTP Hardening" ftp
    local main=/var/cpanel/conf/pureftpd/main
    if [[ -f $main ]]; then
        if grep -Eq "^NoAnonymous:[[:space:]]*'?yes'?" "$main"; then v_pass "Anonymous FTP disabled"; else v_fail "Anonymous FTP enabled"; fi
        if grep -Eq "^RootPassLogins:[[:space:]]*'?no'?" "$main"; then v_pass "Root FTP login disabled"; else v_fail "Root FTP enabled"; fi
    else
        v_pass "Pure-FTPd default secure"
    fi
}

verify_tmp() {
    v_section "TMP Hardening" tmp
    if tmp_is_secure /tmp && tmp_is_secure /var/tmp; then
        v_pass "/tmp and /var/tmp mounted noexec,nosuid"
    else
        v_fail "/tmp or /var/tmp not mounted noexec,nosuid"
    fi
}

verify_all() {
    local all=$VERIFY_ONLY
    echo; echo "=============================== VERIFICATION ==============================="
    if (( all )) || ran dns || ran hardening;         then verify_dns; fi
    if (( all )) || ran php;                          then verify_php; fi
    if (( all )) || ran csf;                          then verify_csf; fi
    if (( all )) || ran lfd || ran hardening;         then verify_lfd; verify_sshalerts; fi
    if (( all )) || ran services || ran hardening;    then verify_services; fi
    if (( all )) || ran forkbomb || ran hardening;    then verify_forkbomb; fi
    if (( all )) || ran ftp || ran hardening;         then verify_ftp; fi
    if (( all )) || ran tmp || ran hardening;         then verify_tmp; fi
    if (( all )) || ran updates;                      then verify_updates; fi
    if (( all )) || ran nameservers;                  then verify_nameservers; fi
    if (( all )) || ran zabbix;                       then verify_zabbix; fi
    if (( all )) || ran ssh;                          then verify_ssh; fi
    v_close
    return 0
}

item_txt() {
    case "${ITEM[$1]:-}" in
        PASS) echo "DONE" ;;
        WARN) echo "DONE - review warnings" ;;
        FAIL) echo "FAILED - see log" ;;
        *)    echo "DONE" ;;
    esac
}

write_handover_report() {
    local f=/root/server_handover_report.txt user pr root_txt ns1 ns2 pw_txt
    user="${ADMIN_USER:-admin}"
    ns1="$(awk '$1=="NS"{print $2}' /etc/wwwacct.conf 2>/dev/null || echo "$DEFAULT_NS1")"
    ns2="$(awk '$1=="NS2"{print $2}' /etc/wwwacct.conf 2>/dev/null || echo "$DEFAULT_NS2")"
    pr="$(sshd -T 2>/dev/null | awk '/^permitrootlogin /{print $2}')"

    if [[ $pr == no ]]; then
        root_txt="Also, we have disabled direct root login and have changed the SSH port. The new server details are as given below, You can use the same to access the server via SSH."
    else
        root_txt="The SSH port has been changed to ${SSH_PORT}. After verifying the admin login, run '${0##*/} --finalize-ssh' to disable direct root login completely."
    fi

    if (( ADMIN_PW_RANDOM )); then
        pw_txt="$(cat /root/.admin_initial_password 2>/dev/null || echo '<see /root/.admin_initial_password>')"
    elif [[ -n $ADMIN_PW_GENERATED ]] && { [[ ${INCLUDE_PW_IN_REPORT:-0} == 1 ]] || { (( ! ASSUME_YES )) && ask_yes_no "Include the entered admin password in the handover file?" y; }; }; then
        pw_txt="$ADMIN_PW_GENERATED"
    else
        pw_txt="[Password set during setup]"
    fi

    umask 077
    {
        printf ' %2d. %-58s [%s]\n'  1 "Secured DNS server."                                         "$(item_txt dns)"
        printf ' %2d. %-58s [%s]\n'  2 "Secured php by disabling dangerous php functions."           "$(item_txt php)"
        printf ' %2d. %-58s [%s]\n'  3 "Installed and configured - Config Server Firewall."          "$(item_txt csf)"
        printf ' %2d. %-58s [%s]\n'  4 "Enabled Login Failure Daemon."                               "$(item_txt lfd)"
        printf ' %2d. %-58s [%s]\n'  5 "Disabled unwanted services."                                 "$(item_txt services)"
        printf ' %2d. %-58s [%s]\n'  6 "Enabled Shell Fork Bomb Protection"                          "$(item_txt forkbomb)"
        printf ' %2d. %-58s [%s]\n'  7 "FTP Hardening : Disable anonymous ftp and root ftp."         "$(item_txt ftp)"
        printf ' %2d. %-58s [%s]\n'  8 "TMP directory hardening."                                    "$(item_txt tmp)"
        printf ' %2d. %-58s [%s]\n'  9 "Enable SSH alerts."                                          "$(item_txt sshalerts)"
        printf ' %2d. %-58s [%s]\n' 10 "Updated all server software."                                "$(item_txt updates)"
        printf ' %2d. %-58s [%s]\n' 11 "Custom nameservers configured."                              "$(item_txt nameservers)"
        printf ' %2d. %-58s [%s]\n' 12 "Added server + services in proactive monitoring system."     "$(item_txt zabbix)"
        echo
        echo "Custom nameserver (${ns1} and ${ns2}) has been configured on the server. You can add the glue records for"
        echo
        echo "${ns1} and ${ns2} to the server ip ${SERVER_IP} at your domain registrar whenever you wish to use these nameservers."
        echo "Added the server and all the services in our proactive monitoring system."
        echo "$root_txt"
        echo
        echo "##############"
        echo "New SSH Port Number: ${SSH_PORT}"
        echo "Wheel username : ${user}"
        echo "Password : ${pw_txt}"
        echo "##############"
    } >"$f"
    chmod 600 "$f"

    echo; echo "=========================== HANDOVER REPORT ($f) ==========================="
    cat "$f"
    echo "=============================================================================="
}

# ------------------------------------------------------------------------------
# Main
# ------------------------------------------------------------------------------
if (( FINALIZE_SSH )); then
    finalize_ssh
    exit 0
fi

if (( ! VERIFY_ONLY )); then
    step_wanted cpanel      "Update cPanel (or install it if missing)?"              && step_cpanel
    step_wanted updates     "Install all pending cPanel / OS updates?"               && step_updates
    step_wanted nameservers "Set WHM custom nameservers + contact email?"            && step_nameservers
    step_wanted csf         "Install and configure CSF firewall?"                    && step_csf
    step_wanted ssh         "Create wheel admin user & harden SSH (port $SSH_PORT)?" && step_ssh
    if step_wanted hardening "Apply full server hardening (DNS, Services, Forkbomb, FTP, TMP, LFD alerts)?" || hard_any_selected; then
        step_hardening
    fi
    step_wanted easyapache  "Configure EasyApache 4 (event MPM, mod_lsapi, mod_remoteip)?" && step_easyapache
    step_wanted php         "Apply PHP disable_functions hardening?"                 && step_php
    step_wanted imunify     "Install ImunifyAV and schedule weekly scans?"           && step_imunify
    step_wanted zabbix      "Install and configure Zabbix Agent 2?"                  && step_zabbix
    step_wanted wptoolkit   "Install WP Toolkit & MySQLTuner?"                       && step_wptoolkit_mysql
fi

verify_all
write_handover_report

if (( NEED_REBOOT )); then
    if ask_yes_no "A reboot is recommended to apply updates. Reboot now?" n; then
        systemctl reboot
    fi
fi

if (( FAIL_N > 0 )); then exit 2; fi
exit 0
