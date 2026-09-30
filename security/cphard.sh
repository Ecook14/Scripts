#!/usr/bin/env bash
# ==============================================================================
# Script Name : cpanel_zabbix_master_setup.sh   (v2.1.0)
# Description : cPanel provisioning, nameservers, CSF firewall, SSH/PHP/MySQL
#               hardening, EasyApache 4 (event MPM + mod_lsapi + mod_remoteip),
#               ImunifyAV and Zabbix Agent 2 setup, with an automatic
#               verification report at the end.  Safe to re-run (idempotent).
#
# Usage       : ./cpanel_zabbix_master_setup.sh [options]
#   -y, --yes            Non-interactive: accept defaults (values can come from env)
#       --only LIST      Run only these steps (comma separated):
#                        cpanel,nameservers,csf,ssh,easyapache,php,imunify,zabbix,wptoolkit
#       --verify         Only run the verification checks (changes nothing)
#       --finalize-ssh   After you verified the new SSH port: remove port 22
#   -h, --help           Show this help
#
# Env overrides: NS1, NS2 (+ optional NS3, NS4), CONTACT_EMAIL, SSH_PORT, ZBX_SERVER_IP,
#   ZABBIX_VERSION, PRIMARY_DOMAIN, SERVER_IP, HOST_METADATA, ADMIN_USER, ADMIN_PUBKEY,
#   ROOT_PUBKEY, NEW_HOSTNAME, PHP_DISABLE_FUNCTIONS, FTP_PASV_RANGE,
#   ADMIN_IPS (comma list for CSF allow), CSF_TARBALL_URL,
#   FORCE_MYSQL_TUNING=1 (overwrite existing values in /etc/my.cnf),
#   INSTALL_FCGID=0|1 (default 1, mod_fcgid kept installed as a spare handler),
#   LSAPI_FALLBACK_HANDLER (e.g. fcgi; used ONLY when mod_lsapi is unavailable),
#   ENABLE_CF_REMOTEIP=0|1 (default 1: Cloudflare mod_remoteip config)
#
# Changes vs v2.0.1
#   * New step "easyapache": mod_prefork -> mod_mpm_event, installs mod_lsapi,
#     mod_remoteip (+ mod_fcgid), sets the MultiPHP handler to lsapi for every
#     ea-php version, turns PHP-FPM OFF (not needed with lsapi).
#     If mod_lsapi is not available (needs CloudLinux OS + license) the script says so
#     clearly and does NOT switch handlers unless LSAPI_FALLBACK_HANDLER is set.
#   * ModSecurity OWASP CRS is intentionally NOT installed.
#   * Cloudflare real-IP (mod_remoteip) is configured automatically.
#   * Nameserver + contact email applied; DNS A records of the nameservers checked.
#   * Zabbix is verified end to end (service, port, agent.ping, mysql.ping,
#     mailqueue, firewall, server reachability, log errors) with one auto-restart.
#   * Final PASS/WARN/FAIL verification report replaces the static checklist.
# ==============================================================================

set -Eeuo pipefail
umask 022

SCRIPT_NAME="cpanel_master_setup"
LOG_FILE="${LOG_FILE:-/var/log/cpanel_master_setup.log}"
SSH_PORT="${SSH_PORT:-1243}"
DEFAULT_ZABBIX_IP="${DEFAULT_ZABBIX_IP:-103.211.219.161}"
DEFAULT_NS1="${DEFAULT_NS1:-ns1.seedglobaleducation.com}"
DEFAULT_NS2="${DEFAULT_NS2:-ns2.seedglobaleducation.com}"
ZABBIX_VERSION_DEFAULT="${ZABBIX_VERSION_DEFAULT:-7.0}"   # must be <= your Zabbix server version
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

usage() { awk 'NR>1 && /^# Changes vs/ {exit} NR>1 {sub(/^# ?/,""); print}' "$0"; }

# --- verification result recorder ----------------------------------------------
v_pass() { PASS_N=$((PASS_N+1)); RESULTS+=("PASS|$*"); printf '  [%sPASS%s] %s\n' "$C_GRN" "$C_RST" "$*"; printf '%s [PASS] %s\n' "$(date '+%F %T')" "$*" >>"$LOG_FILE" 2>/dev/null || true; }
v_warn() { WARN_N=$((WARN_N+1)); RESULTS+=("WARN|$*"); printf '  [%sWARN%s] %s\n' "$C_YLW" "$C_RST" "$*"; printf '%s [WARN] %s\n' "$(date '+%F %T')" "$*" >>"$LOG_FILE" 2>/dev/null || true; }
v_fail() { FAIL_N=$((FAIL_N+1)); RESULTS+=("FAIL|$*"); printf '  [%sFAIL%s] %s\n' "$C_RED" "$C_RST" "$*"; printf '%s [FAIL] %s\n' "$(date '+%F %T')" "$*" >>"$LOG_FILE" 2>/dev/null || true; }
v_section() { printf '\n--- %s ---\n' "$*"; }

ask_yes_no() {
    local prompt="$1" def="${2:-n}" choice hint="[y/N]"
    [[ $def == y ]] && hint="[Y/n]"
    if (( ASSUME_YES )); then [[ $def == y ]]; return; fi
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

# ask_value VAR "prompt" "default" [validator]  -- env var wins, then prompt/default
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

step_wanted() {  # step_wanted name "prompt"  (records the step in RAN when selected)
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

backup_file() {
    local f="$1"
    [[ -e $f ]] || return 0
    mkdir -p "$BACKUP_DIR$(dirname "$f")"
    cp -a "$f" "$BACKUP_DIR$f"
}

# set_block FILE TAG  <stdin>: replace/append a marked, idempotent block
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

remove_root_cron() {  # remove lines matching pattern from root's crontab (v1 leftovers)
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
pkg_available() {  # installed OR installable from an enabled repo
    pkg_installed "$1" && return 0
    if [[ $OS_FAMILY == rhel ]]; then "$PM" -q list --available "$1" &>/dev/null
    else apt-cache show "$1" &>/dev/null; fi
}
ea_name() { if [[ $OS_FAMILY == debian ]]; then echo "${1//_/-}"; else echo "$1"; fi; }  # EA4 deb names use dashes
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

clear || true
echo "=============================================================================="
echo "  cPANEL/WHM PROVISIONING, EA4 (LSAPI), CSF, HARDENING & ZABBIX AGENT 2  v2.1.0 "
echo "=============================================================================="
echo "Detected OS : $OS_ID $OS_VERSION_ID ($OS_FAMILY)"
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
csf_restart() { csf -r >>"$LOG_FILE" 2>&1 || die "csf -r failed; see $LOG_FILE (use 'csf -f' if locked out at the console)"; }

ensure_zbx_ip() {
    ask_value ZBX_SERVER_IP "Enter Zabbix Server IP" "$DEFAULT_ZABBIX_IP" valid_ipv4
}

# Cloudflare published ranges, one per line. Arg1=1 includes IPv6.
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

open_tcp_port() {  # open a TCP port on whichever firewall is active
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
        warn "Opened TCP $p in raw iptables (not persistent across reboot)"
    fi
}

allow_zabbix_port() {  # 10050 restricted to the Zabbix server
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
    warn "cPanel installation finished. A reboot is recommended (offered at the end)."
}

# ------------------------------------------------------------------------------
# 1b. WHM default nameservers + contact email
# ------------------------------------------------------------------------------
wwwacct_set() {  # fallback: edit /etc/wwwacct.conf directly ("KEY value" format)
    local k="$1" v="$2" f=/etc/wwwacct.conf
    touch "$f"
    if grep -qE "^${k}[[:space:]]" "$f"; then
        sed -i -E "s|^${k}[[:space:]].*|${k} ${v}|" "$f"
    else
        printf '%s %s\n' "$k" "$v" >>"$f"
    fi
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
        log "Nameservers applied: NS=${NS1}  NS2=${NS2}${NS3:+  NS3=$NS3}${NS4:+  NS4=$NS4}  (via $( ((applied)) && echo whmapi1 || echo wwwacct.conf ))"
    else
        die "Nameservers not found in /etc/wwwacct.conf after applying; check $LOG_FILE"
    fi
    NS_APPLIED=1
}

# ------------------------------------------------------------------------------
# 2. CSF firewall (cPanel-maintained fork; original ConfigServer is discontinued)
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
        log "Installing CSF from the cPanel-maintained package (cpanel-csf)..."
        if ! pkg_install cpanel-csf; then
            warn "cpanel-csf package failed; trying /scripts/autorepair cpanel_csf_install"
            [[ -x /scripts/autorepair ]] && /scripts/autorepair cpanel_csf_install || true
        fi
    fi

    if ! have_csf; then
        if [[ -n "${CSF_TARBALL_URL:-}" ]]; then
            warn "Installing CSF from CSF_TARBALL_URL=$CSF_TARBALL_URL (unverified third-party code; review it)."
            cd /usr/src && rm -rf csf csf.tgz csf-src && mkdir csf-src
            curl -fsSL "$CSF_TARBALL_URL" -o csf.tgz
            tar -xzf csf.tgz -C csf-src --strip-components=1
            (cd csf-src && sh install.sh)
        else
            warn "Could not install CSF. The original download.configserver.com is offline."
            warn "Set CSF_TARBALL_URL to a maintained fork tarball (after reviewing it) and re-run with --only csf."
            return 1
        fi
    fi
    have_csf || die "CSF installation did not complete."

    [[ -f /usr/local/csf/bin/csftest.pl ]] && { perl /usr/local/csf/bin/csftest.pl || warn "csftest.pl reported problems"; }
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

    # --- ports -----------------------------------------------------------------
    local tcp_in="20,21,25,53,80,110,143,443,465,587,993,995,2082,2083,2086,2087,2095,2096,${FTP_PASV_RANGE}"
    local p
    for p in 22 "$SSH_PORT" "$cur_port"; do
        [[ $p =~ ^[0-9]+$ ]] && tcp_in="$(csv_add "$tcp_in" "$p")"
    done
    log "Configuring CSF ports (SSH 22 stays open until --finalize-ssh; 10050 is Zabbix-only)..."
    csf_set TCP_IN  "$tcp_in"
    csf_set TCP_OUT "20,21,22,25,37,43,53,80,110,113,443,465,587,873,993,995,2086,2087,10051"
    csf_set UDP_IN  "20,21,53,80,443"
    csf_set UDP_OUT "20,21,53,113,123,873"

    # --- protection ------------------------------------------------------------
    csf_set SMTP_BLOCK      "1"
    csf_set CT_LIMIT        "100"
    csf_set CT_PORTS        "80,443"
    csf_set SYNFLOOD        "1"
    csf_set CONNLIMIT       "22;5,${SSH_PORT};5,80;20"
    csf_set PORTFLOOD       "22;tcp;5;300,${SSH_PORT};tcp;5;300,80;tcp;90;5"
    csf_set RESTRICT_SYSLOG "3"

    local k
    for k in LF_PERMBLOCK_ALERT LF_NETBLOCK_ALERT LF_DISTFTP_ALERT LF_DISTSMTP_ALERT LT_EMAIL_ALERT CT_EMAIL_ALERT; do
        csf_set "$k" "0"
    done

    # --- allow / ignore lists (managed blocks, no duplicates on re-run) ---------
    printf 'tcp|in|d=10050|s=%s  # Zabbix server\n' "$ZBX_SERVER_IP" | set_block /etc/csf/csf.allow zabbix
    grep -qxF "$ZBX_SERVER_IP" /etc/csf/csf.ignore 2>/dev/null || echo "$ZBX_SERVER_IP" >>/etc/csf/csf.ignore

    local admin_ips="${ADMIN_IPS:-}"
    if [[ -n $my_ip ]] && ask_yes_no "Whitelist your current SSH client IP ($my_ip) to avoid lockout?" y; then
        admin_ips="$(csv_add "$admin_ips" "$my_ip")"
    fi
    if [[ -n $admin_ips ]]; then
        tr ',' '\n' <<<"$admin_ips" | sed 's/$/  # admin (setup script)/' | set_block /etc/csf/csf.allow admin-ips
    fi

    local cf v6=0
    [[ "$(csf_get IPV6)" == "1" ]] && v6=1
    cf="$(cf_ranges "$v6" | sed 's/$/  # Cloudflare/')"
    if [[ -n $cf ]]; then
        printf '%s\n' "$cf" | set_block /etc/csf/csf.allow cloudflare
        log "Cloudflare ranges whitelisted."
    else
        warn "Could not fetch Cloudflare ranges; existing entries (if any) left unchanged."
    fi

    # --- apply with a safety net ------------------------------------------------
    systemctl enable csf lfd >/dev/null 2>&1 || true
    if (( ASSUME_YES )); then
        csf_set TESTING "0"; csf_restart
        log "CSF applied (TESTING=0)."
    else
        csf_set TESTING "1"; csf_restart
        warn "CSF is in TESTING mode: rules are auto-flushed every 5 minutes."
        echo "  -> Open a NEW terminal and confirm SSH / WHM (2087) still work."
        if ask_yes_no "Everything reachable? Disable testing mode now?" n; then
            csf_set TESTING "0"; csf_restart
            log "CSF is live (TESTING=0)."
        else
            warn "Left in TESTING mode. Set TESTING=\"0\" in /etc/csf/csf.conf and run 'csf -r' when ready."
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
install_pubkey() {  # install_pubkey USER "key"
    local user="$1" key="$2" home grp
    home="$(getent passwd "$user" | cut -d: -f6)"; grp="$(id -gn "$user")"
    install -d -m 700 -o "$user" -g "$grp" "$home/.ssh"
    touch "$home/.ssh/authorized_keys"
    grep -qxF "$key" "$home/.ssh/authorized_keys" || printf '%s\n' "$key" >>"$home/.ssh/authorized_keys"
    chown "$user:$grp" "$home/.ssh/authorized_keys"; chmod 600 "$home/.ssh/authorized_keys"
}
ask_pubkey_for() {  # ask_pubkey_for USER ENVVAR  -> installs key if provided & valid
    local user="$1" var="$2" key=""
    key="${!var:-}"
    if [[ -z $key ]] && (( ! ASSUME_YES )); then
        read -r -p "Paste an SSH public key for '$user' (Enter to skip): " key || key=""
    fi
    [[ -z $key ]] && return 1
    if valid_pubkey "$key"; then install_pubkey "$user" "$key"; log "Key installed for $user."; return 0; fi
    warn "That does not look like a valid public key."; return 1
}

selinux_allow_port() {
    if command -v getenforce &>/dev/null && [[ "$(getenforce)" == "Enforcing" ]]; then
        if command -v semanage &>/dev/null; then
            semanage port -a -t ssh_port_t -p tcp "$1" 2>/dev/null || semanage port -m -t ssh_port_t -p tcp "$1" || true
        else
            warn "SELinux is enforcing but semanage is missing; install policycoreutils-python-utils."
        fi
    fi
}

write_sshd_config() {  # write_sshd_config "ports(csv)" permit_root pass_auth
    local ports="$1" permit_root="$2" pass_auth="$3" body="" p
    for p in ${ports//,/ }; do body+="Port ${p}"$'\n'; done
    body+="PermitRootLogin ${permit_root}"$'\n'
    if [[ -n $pass_auth ]]; then body+="PasswordAuthentication ${pass_auth}"$'\n'; fi
    body+="MaxAuthTries 4"$'\n'"LoginGraceTime 30"

    backup_file "$SSHD_MAIN"
    sed -i -E 's/^([[:space:]]*)Port([[:space:]])/#\1Port\2/' "$SSHD_MAIN"

    if grep -qiE '^[[:space:]]*Include[[:space:]]+/etc/ssh/sshd_config\.d/' "$SSHD_MAIN"; then
        mkdir -p /etc/ssh/sshd_config.d
        printf '# managed by %s\n%s\n' "$SCRIPT_NAME" "$body" >"$SSHD_DROPIN"
    else
        sed -i '/^# BEGIN ssh-hardening /,/^# END ssh-hardening$/d' "$SSHD_MAIN"
        sed -i -E 's/^([[:space:]]*)(PermitRootLogin|PasswordAuthentication|MaxAuthTries|LoginGraceTime)([[:space:]])/#\1\2\3/' "$SSHD_MAIN"
        local tmp; tmp="$(mktemp)"
        { printf '# BEGIN ssh-hardening (managed by %s)\n%s\n# END ssh-hardening\n' "$SCRIPT_NAME" "$body"; cat "$SSHD_MAIN"; } >"$tmp"
        cat "$tmp" >"$SSHD_MAIN"; rm -f "$tmp"
    fi
}

rollback_ssh() {
    warn "Rolling back SSH configuration..."
    [[ -f "$BACKUP_DIR$SSHD_MAIN" ]] && cp -a "$BACKUP_DIR$SSHD_MAIN" "$SSHD_MAIN"
    rm -f "$SSHD_DROPIN"
    systemctl restart "$(ssh_service)" || true
}

restart_sshd_checked() {  # validate config, restart, verify listeners; roll back on failure
    local expect_port="$1" svc; svc="$(ssh_service)"
    mkdir -p /run/sshd
    if ! sshd -t; then rollback_ssh; die "sshd -t rejected the new configuration; rolled back."; fi

    if svc_exists ssh.socket && systemctl is-active --quiet ssh.socket 2>/dev/null; then
        log "Disabling ssh.socket activation so sshd_config Port directives apply."
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
        warn "User $ADMIN_USER already exists; ensuring group membership."
        usermod -aG "$grp" "$ADMIN_USER"
    else
        log "Creating user '$ADMIN_USER' in group '$grp'..."
        useradd -m -s /bin/bash -G "$grp" "$ADMIN_USER"
        if (( ASSUME_YES )); then
            warn "No password set for $ADMIN_USER (non-interactive). Run: passwd $ADMIN_USER  (needed for sudo)"
        else
            passwd "$ADMIN_USER"
        fi
    fi
    if command -v sudo &>/dev/null; then
        sudo -l -U "$ADMIN_USER" 2>/dev/null | grep -qE 'ALL' \
            && log "sudo access verified for $ADMIN_USER." \
            || warn "Could not confirm sudo rights for $ADMIN_USER; check /etc/sudoers for %$grp."
    else
        warn "sudo is not installed; install it or use 'su' from the admin account."
    fi

    local admin_home root_key=0 admin_key=0
    admin_home="$(getent passwd "$ADMIN_USER" | cut -d: -f6)"
    has_pubkey_file "$admin_home/.ssh/authorized_keys" && admin_key=1 || true
    has_pubkey_file /root/.ssh/authorized_keys && root_key=1 || true
    if (( ! admin_key )); then ask_pubkey_for "$ADMIN_USER" ADMIN_PUBKEY && admin_key=1 || true; fi
    if (( ! root_key )); then ask_pubkey_for root ROOT_PUBKEY && root_key=1 || true; fi
    if (( ! admin_key && root_key )) && ask_yes_no "Copy root's authorized_keys to $ADMIN_USER?" y; then
        install -d -m 700 -o "$ADMIN_USER" -g "$(id -gn "$ADMIN_USER")" "$admin_home/.ssh"
        cat /root/.ssh/authorized_keys >>"$admin_home/.ssh/authorized_keys"
        chown "$ADMIN_USER:$(id -gn "$ADMIN_USER")" "$admin_home/.ssh/authorized_keys"
        chmod 600 "$admin_home/.ssh/authorized_keys"; admin_key=1
    fi

    local permit_root="yes" pass_auth=""
    if (( root_key )); then
        permit_root="prohibit-password"
    else
        warn "No SSH key found for root: leaving PermitRootLogin unchanged (password login stays enabled) to avoid lockout."
        permit_root="$(sshd -T 2>/dev/null | awk '/^permitrootlogin /{print $2}')"; permit_root="${permit_root:-yes}"
    fi
    if (( root_key || admin_key )) && ask_yes_no "Also disable SSH PASSWORD authentication for everyone (keys only)?" n; then
        pass_auth="no"
    fi

    open_tcp_port "$SSH_PORT"
    open_tcp_port 22
    selinux_allow_port "$SSH_PORT"

    log "Writing SSH hardening (ports 22 + $SSH_PORT, PermitRootLogin $permit_root)..."
    write_sshd_config "22,${SSH_PORT}" "$permit_root" "$pass_auth"
    restart_sshd_checked "$SSH_PORT"

    log "sshd now listens on 22 and $SSH_PORT."
}

finalize_ssh() {
    ss -ltn | grep -qE "[:.]${SSH_PORT}[[:space:]]" || die "sshd is not listening on ${SSH_PORT}; run the ssh step first."
    ask_yes_no "Confirm you logged in successfully on port $SSH_PORT from a separate session. Remove port 22 now?" n || { log "Nothing changed."; return 0; }

    local f="$SSHD_DROPIN"
    [[ -f $f ]] || f="$SSHD_MAIN"
    backup_file "$f"
    sed -i '/^Port 22$/d' "$f"
    restart_sshd_checked "$SSH_PORT"
    if ss -ltn | grep -qE '[:.]22[[:space:]]'; then warn "Port 22 is still listening; check $SSHD_MAIN for other Port directives."; fi

    if have_csf; then
        csf_set TCP_IN "$(csv_del "$(csf_get TCP_IN)" 22)"
        csf_restart
        log "Port 22 removed from CSF TCP_IN."
    fi
    log "SSH finalized: only port $SSH_PORT is active."
}

# ------------------------------------------------------------------------------
# 4. EasyApache 4: event MPM, mod_lsapi, mod_remoteip, PHP handler = lsapi, no FPM
#    (ModSecurity OWASP CRS is intentionally NOT installed.)
# ------------------------------------------------------------------------------
restart_httpd() {
    if [[ -x /scripts/restartsrv_httpd ]]; then /scripts/restartsrv_httpd >>"$LOG_FILE" 2>&1
    else systemctl restart httpd 2>>"$LOG_FILE" || systemctl restart apache2 2>>"$LOG_FILE"; fi
}

lsapi_available() {  # caches result; sets LSAPI_AVAILABLE
    if (( LSAPI_AVAILABLE >= 0 )); then (( LSAPI_AVAILABLE == 1 )); return; fi
    if pkg_available "$(ea_name ea-apache24-mod_lsapi)"; then LSAPI_AVAILABLE=1; else LSAPI_AVAILABLE=0; fi
    (( LSAPI_AVAILABLE == 1 ))
}

lsapi_unavailable_notice() {
    warn "mod_lsapi is NOT available on this server (package ea-apache24-mod_lsapi not found in any enabled repo)."
    warn "  mod_lsapi is distributed by CloudLinux and needs CloudLinux OS (or the CloudLinux repo + a valid license)."
    warn "  This host is $OS_ID $OS_VERSION_ID. The PHP handler was NOT changed to lsapi."
    if [[ -n $LSAPI_FALLBACK_HANDLER ]]; then
        warn "  LSAPI_FALLBACK_HANDLER=$LSAPI_FALLBACK_HANDLER will be applied instead."
    else
        warn "  Options: convert to CloudLinux, or re-run with LSAPI_FALLBACK_HANDLER=fcgi (mod_fcgid) / cgi / suphp."
    fi
}

set_php_handlers() {  # set_php_handlers HANDLER
    local handler="$1" d v n_ok=0 n_bad=0
    has_whmapi || { warn "whmapi1 not found; cannot set PHP handlers."; return 1; }
    for d in /opt/cpanel/ea-php*; do
        [[ -d $d ]] || continue
        v="$(basename "$d")"
        if whmapi1 php_set_handler version="$v" handler="$handler" 2>>"$LOG_FILE" | grep -q 'result: 1'; then
            log "MultiPHP: $v handler -> $handler"; n_ok=$((n_ok+1))
        else
            warn "MultiPHP: could not set $v to '$handler' (is ea-${v#ea-}-php-${handler} / lsapi support installed for it?)"
            n_bad=$((n_bad+1))
        fi
    done
    (( n_ok + n_bad > 0 )) || { warn "No ea-php versions installed; nothing to set."; return 1; }
    (( n_bad == 0 ))
}

setup_cf_remoteip() {
    local conf=/etc/apache2/conf.d/zz-cloudflare-remoteip.conf ranges httpd l
    httpd="$(httpd_bin)"
    [[ -n $httpd ]] || { warn "httpd binary not found; skipping Cloudflare remoteip."; return 0; }
    ranges="$(cf_ranges 1)"
    if [[ -z $ranges ]]; then
        warn "Could not fetch Cloudflare ranges; remoteip config not (re)written."
        return 0
    fi
    backup_file "$conf"
    {
        printf '# managed by %s - Cloudflare real visitor IP\n' "$SCRIPT_NAME"
        printf '<IfModule remoteip_module>\n    RemoteIPHeader CF-Connecting-IP\n'
        while IFS= read -r l; do printf '    RemoteIPTrustedProxy %s\n' "$l"; done <<<"$ranges"
        printf '</IfModule>\n'
    } >"$conf"
    if "$httpd" -t >>"$LOG_FILE" 2>&1; then
        restart_httpd || warn "Apache restart reported an error; check $LOG_FILE"
        log "Cloudflare mod_remoteip configured: $conf ($(wc -l <<<"$ranges") ranges)."
    else
        warn "Apache config test failed with the remoteip file; reverting it."
        if [[ -f "$BACKUP_DIR$conf" ]]; then cp -a "$BACKUP_DIR$conf" "$conf"; else rm -f "$conf"; fi
    fi
}

step_easyapache() {
    is_cpanel || { warn "cPanel not detected; skipping EasyApache 4 changes."; return 0; }

    local httpd; httpd="$(httpd_bin)"
    [[ -n $httpd ]] && "$httpd" -t >>"$LOG_FILE" 2>&1 || { warn "Apache config test fails BEFORE changes; fix it first (see $LOG_FILE). Skipping."; return 0; }

    local prefork event remoteip fcgid lsapi
    prefork="$(ea_name ea-apache24-mod_mpm_prefork)"; event="$(ea_name ea-apache24-mod_mpm_event)"
    remoteip="$(ea_name ea-apache24-mod_remoteip)";   fcgid="$(ea_name ea-apache24-mod_fcgid)"
    lsapi="$(ea_name ea-apache24-mod_lsapi)"

    # --- 1. MPM: prefork -> event ---------------------------------------------------
    if pkg_installed "$event" && ! pkg_installed "$prefork"; then
        log "mod_mpm_event already active."
    else
        local conflict
        conflict="$(rpm -qa 2>/dev/null | grep -E '^ea-apache24-(mod_ruid2|mod_mpm_itk|mod_php)' || true)"
        [[ -z $conflict ]] || warn "These prefork-only modules will be removed by the MPM swap (lsapi replaces them): $(tr '\n' ' ' <<<"$conflict")"
        log "Switching MPM: mod_mpm_prefork -> mod_mpm_event ..."
        if [[ $OS_FAMILY == rhel ]]; then
            if pkg_installed "$prefork"; then "$PM" -y swap "$prefork" "$event" >>"$LOG_FILE" 2>&1 || warn "MPM swap failed; see $LOG_FILE"
            else pkg_install "$event" >>"$LOG_FILE" 2>&1 || warn "Could not install $event"; fi
        else
            pkg_install "$event" >>"$LOG_FILE" 2>&1 || warn "Could not install $event"
        fi
    fi

    # --- 2. modules --------------------------------------------------------------------
    pkg_installed "$remoteip" || { pkg_install "$remoteip" >>"$LOG_FILE" 2>&1 && log "Installed $remoteip" || warn "Could not install $remoteip"; }
    if [[ $INSTALL_FCGID == 1 ]] && ! pkg_installed "$fcgid"; then
        pkg_install "$fcgid" >>"$LOG_FILE" 2>&1 && log "Installed $fcgid" || warn "Could not install $fcgid"
    fi

    if lsapi_available; then
        pkg_installed "$lsapi" || { pkg_install "$lsapi" >>"$LOG_FILE" 2>&1 && log "Installed $lsapi" || warn "Could not install $lsapi"; }
        if [[ -x /usr/bin/switch_mod_lsapi ]]; then
            /usr/bin/switch_mod_lsapi --setup >>"$LOG_FILE" 2>&1 && log "mod_lsapi set up (switch_mod_lsapi --setup)." || warn "switch_mod_lsapi --setup reported a problem."
        fi
    else
        lsapi_unavailable_notice
    fi

    # --- 3. validate + restart ------------------------------------------------------------
    if "$httpd" -t >>"$LOG_FILE" 2>&1; then
        restart_httpd || warn "Apache restart reported an error; check $LOG_FILE"
    else
        warn "Apache config test failed after module changes: NOT restarting. Run '$httpd -t' and fix it."
        return 0
    fi

    # --- 4. MultiPHP handler + PHP-FPM off ----------------------------------------------------
    if lsapi_available && pkg_installed "$lsapi"; then
        set_php_handlers lsapi || warn "Some PHP versions could not be switched to lsapi (see above)."
    elif [[ -n $LSAPI_FALLBACK_HANDLER ]]; then
        set_php_handlers "$LSAPI_FALLBACK_HANDLER" || true
    fi
    if has_whmapi; then
        whmapi1 php_set_default_accounts_to_fpm default_accounts_to_fpm=0 >>"$LOG_FILE" 2>&1 \
            && log "PHP-FPM disabled for new accounts (not needed with lsapi)." \
            || warn "Could not disable 'default accounts to FPM' via whmapi1."
    fi
    warn "ModSecurity OWASP CRS is intentionally not installed (per configuration)."

    # --- 5. Cloudflare real IP ---------------------------------------------------------------------
    if [[ $ENABLE_CF_REMOTEIP == 1 ]] && pkg_installed "$remoteip"; then setup_cf_remoteip; fi
}

# ------------------------------------------------------------------------------
# 5. PHP (MultiPHP / EasyApache 4) disable_functions
# ------------------------------------------------------------------------------
step_php() {
    is_cpanel || { warn "cPanel not detected; skipping PHP hardening."; return 0; }
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
    (( found )) || { warn "No ea-php installations found."; return 0; }

    [[ -x /scripts/restartsrv_apache_php_fpm ]] && /scripts/restartsrv_apache_php_fpm || true
    [[ -x /scripts/restartsrv_httpd ]] && /scripts/restartsrv_httpd || true
    log "Applied: $PHP_DISABLE_FUNCTIONS"
    warn "curl_exec/curl_multi_exec are intentionally NOT disabled (breaks WordPress updates and most plugins)."
}

# ------------------------------------------------------------------------------
# 6. ImunifyAV
# ------------------------------------------------------------------------------
step_imunify() {
    local cli=""
    if command -v imunify-antivirus &>/dev/null; then cli=imunify-antivirus
    elif command -v imunify360-agent &>/dev/null; then cli=imunify360-agent; fi

    if [[ -z $cli ]]; then
        log "Installing ImunifyAV (official deploy script)..."
        local tmp; tmp="$(mktemp)"
        curl -fsSL https://repo.imunify360.cloudlinux.com/defence360/imav-deploy.sh -o "$tmp"
        [[ -s $tmp ]] || die "Failed to download the ImunifyAV deploy script."
        bash "$tmp"
        rm -f "$tmp"
        command -v imunify-antivirus &>/dev/null && cli=imunify-antivirus || true
    else
        log "$cli already installed."
    fi
    [[ -n $cli ]] || { warn "Imunify CLI not found after install; cron not created."; return 0; }

    remove_root_cron "imunify-antivirus"
    cat >/etc/cron.d/imunifyav-weekly <<CRON
SHELL=/bin/bash
PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
0 3 * * 0 root $cli malware on-demand start --path /home >/dev/null 2>&1
CRON
    chmod 644 /etc/cron.d/imunifyav-weekly
    log "Weekly on-demand scan of /home scheduled (Sundays 03:00)."
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
    [[ $OS_FAMILY != unknown ]] || die "Unsupported distribution ($OS_ID) for automated Zabbix setup."
    local url="" u tmp
    while IFS= read -r u; do
        if curl -fsIL --max-time 15 "$u" >/dev/null 2>&1; then url="$u"; break; fi
    done < <(zbx_repo_candidates)
    [[ -n $url ]] || die "No Zabbix ${ZABBIX_VERSION} release package found for $OS_ID $OS_VERSION_ID. Check https://www.zabbix.com/download"

    log "Using repository package: $url"
    tmp="$(mktemp --suffix=".${url##*.}")"
    curl -fsSL "$url" -o "$tmp"
    if [[ $OS_FAMILY == rhel ]]; then
        rpm -Uvh --replacepkgs "$tmp"
        if [[ -f /etc/yum.repos.d/epel.repo ]] && ! grep -q 'excludepkgs=zabbix' /etc/yum.repos.d/epel.repo; then
            backup_file /etc/yum.repos.d/epel.repo
            sed -i '/^\[epel\]/a excludepkgs=zabbix*' /etc/yum.repos.d/epel.repo
            log "Excluded zabbix* from the EPEL repo."
        fi
        "$PM" clean all >/dev/null; "$PM" makecache >/dev/null
    else
        dpkg -i "$tmp"; apt-get update -y
    fi
    rm -f "$tmp"
}

zbx_set() {  # zbx_set KEY VALUE (values are validated earlier: no sed metacharacters)
    local k="$1" v="$2" f="$ZBX_CONF"
    if grep -qE "^[[:space:]]*${k}=" "$f"; then
        sed -i -E "s|^[[:space:]]*${k}=.*|${k}=${v}|" "$f"
    else
        printf '%s=%s\n' "$k" "$v" >>"$f"
    fi
}

setup_zabbix_mysql() {
    if ! command -v mysql &>/dev/null; then warn "mysql client not found; skipping MySQL monitoring."; return 0; fi
    if ! mysql -NBe 'SELECT 1' >/dev/null 2>&1; then warn "Cannot connect to MySQL as root; skipping MySQL monitoring."; return 0; fi

    local passfile=/root/.zabbix_mysql_password pass sock
    if [[ -s $passfile ]]; then
        pass="$(cat "$passfile")"
    else
        pass="$(openssl rand -hex 16 2>/dev/null || tr -dc 'A-Za-z0-9' </dev/urandom | head -c 32)"
        install -m 600 /dev/null "$passfile"; printf '%s' "$pass" >"$passfile"
        log "Generated a random Zabbix MySQL password (stored in $passfile, mode 600)."
    fi

    if ! mysql <<SQL
CREATE USER IF NOT EXISTS 'zabbix'@'localhost' IDENTIFIED BY '${pass}';
ALTER USER 'zabbix'@'localhost' IDENTIFIED BY '${pass}';
GRANT REPLICATION CLIENT, PROCESS, SHOW DATABASES, SHOW VIEW ON *.* TO 'zabbix'@'localhost';
SQL
    then
        warn "Creating the 'zabbix' MySQL user failed; MySQL monitoring not configured."
        return 0
    fi

    sock="$(mysql -NBe 'SELECT @@socket' 2>/dev/null || true)"; sock="${sock:-/var/lib/mysql/mysql.sock}"

    if [[ -f /etc/zabbix/zabbix_agentd.d/userparameter_mysql.conf ]]; then
        mkdir -p /etc/zabbix/disabled-userparams
        mv /etc/zabbix/zabbix_agentd.d/userparameter_mysql.conf /etc/zabbix/disabled-userparams/ || true
    fi
    if [[ -f /var/lib/zabbix/.my.cnf ]]; then
        rm -f /var/lib/zabbix/.my.cnf
        log "Removed legacy /var/lib/zabbix/.my.cnf (old hardcoded password is now rotated)."
    fi

    grep -qE '^Include=.*zabbix_agent2\.d/\*\.conf' "$ZBX_CONF" \
        || echo 'Include=/etc/zabbix/zabbix_agent2.d/*.conf' >>"$ZBX_CONF"
    install -d /etc/zabbix/zabbix_agent2.d
    cat >/etc/zabbix/zabbix_agent2.d/cpanel_mysql.conf <<CONF
# managed by ${SCRIPT_NAME}
Plugins.Mysql.Default.Uri=unix:${sock}
Plugins.Mysql.Default.User=zabbix
Plugins.Mysql.Default.Password=${pass}
CONF
    chown root:zabbix /etc/zabbix/zabbix_agent2.d/cpanel_mysql.conf
    chmod 640 /etc/zabbix/zabbix_agent2.d/cpanel_mysql.conf
    log "MySQL monitoring configured (socket: $sock)."
}

setup_zabbix_exim() {
    local exim_bin; exim_bin="$(command -v exim || true)"; exim_bin="${exim_bin:-/usr/sbin/exim}"
    if [[ ! -x $exim_bin ]]; then warn "Exim not found; skipping mail queue monitor."; return 0; fi
    local mq=/etc/zabbix/custom/mailqueue
    install -d -m 755 /etc/zabbix/custom /etc/zabbix/zabbix_agent2.d
    remove_root_cron "mailqueue"
    cat >/etc/cron.d/zabbix-mailqueue <<CRON
SHELL=/bin/bash
PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
* * * * * root ${exim_bin} -bpc > ${mq}.tmp 2>/dev/null && mv -f ${mq}.tmp ${mq} && chmod 644 ${mq}
CRON
    chmod 644 /etc/cron.d/zabbix-mailqueue
    "$exim_bin" -bpc >"$mq" 2>/dev/null || echo 0 >"$mq"; chmod 644 "$mq"
    echo "UserParameter=mailqueue,cat ${mq}" >/etc/zabbix/zabbix_agent2.d/userparameter_exim.conf
    log "Exim mail queue monitor configured (key: mailqueue)."
}

step_zabbix() {
    ensure_zbx_ip
    local default_domain default_ip
    default_domain="$(hostname -f 2>/dev/null || hostname)"
    default_ip="$(hostname -I 2>/dev/null | awk '{print $1}')"
    ZABBIX_VERSION="${ZABBIX_VERSION:-$ZABBIX_VERSION_DEFAULT}"
    valid_minor_ver "$ZABBIX_VERSION" || die "Invalid ZABBIX_VERSION: $ZABBIX_VERSION"
    log "Zabbix agent series pinned to $ZABBIX_VERSION"
    ask_value PRIMARY_DOMAIN "Enter Primary Domain Name" "$default_domain" valid_fqdn
    ask_value SERVER_IP "Enter This Server's IP Address" "$default_ip" valid_ipv4
    ask_value HOST_METADATA "Enter HostMetadata (RC for Resellerclub, LB for Logicboxes)" "" valid_hostmeta
    HOST_METADATA="${HOST_METADATA^^}"

    setup_zabbix_repo

    if pkg_installed zabbix-agent; then
        log "Removing legacy zabbix-agent (v1)..."
        systemctl disable --now zabbix-agent 2>/dev/null || true
        pkg_remove zabbix-agent
    fi
    if pkg_installed zabbix-agent2; then
        log "zabbix-agent2 already installed; leaving the package as-is (no upgrade)."
    else
        log "Installing Zabbix Agent 2 from the $ZABBIX_VERSION repository..."
        pkg_install zabbix-agent2
    fi
    log "Installed: $(zabbix_agent2 --version 2>/dev/null | head -1 || echo unknown)"

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
    sleep 2
    if systemctl is-active --quiet zabbix-agent2; then
        log "Zabbix Agent 2 is running."
    else
        warn "zabbix-agent2 failed to start. See: journalctl -u zabbix-agent2 / /var/log/zabbix/zabbix_agent2.log"
    fi
}

# ------------------------------------------------------------------------------
# 8. WordPress Toolkit, MySQLTuner and MySQL baseline tuning
# ------------------------------------------------------------------------------
mycnf_set_default() {  # set only if absent (FORCE_MYSQL_TUNING=1 overwrites)
    local k="$1" v="$2" f=/etc/my.cnf
    if grep -qE "^[[:space:]]*${k}[[:space:]]*=" "$f"; then
        if [[ "${FORCE_MYSQL_TUNING:-0}" == 1 ]]; then
            sed -i -E "s|^[[:space:]]*${k}[[:space:]]*=.*|${k}=${v}|" "$f"
            log "my.cnf: ${k}=${v} (overwritten)"
        else
            log "my.cnf: ${k} already set; keeping existing value."
        fi
    elif grep -q '^\[mysqld\]' "$f"; then
        sed -i "0,/^\[mysqld\]/s//[mysqld]\n${k}=${v}/" "$f"
        log "my.cnf: ${k}=${v}"
    else
        printf '\n[mysqld]\n%s=%s\n' "$k" "$v" >>"$f"
        log "my.cnf: added [mysqld] with ${k}=${v}"
    fi
}

restart_mysql() {
    if [[ -x /scripts/restartsrv_mysql ]]; then /scripts/restartsrv_mysql; return; fi
    local s
    for s in mysqld mariadb mysql; do
        if svc_exists "$s.service"; then systemctl restart "$s"; return; fi
    done
    return 1
}

step_wptoolkit_mysql() {
    if is_cpanel; then
        if [[ -d /usr/local/cpanel/3rdparty/wp-toolkit ]]; then
            log "WP Toolkit already installed."
        else
            log "Installing WP Toolkit..."
            local tmp; tmp="$(mktemp)"
            if curl -fsSL https://wp-toolkit.plesk.com/cPanel/installer.sh -o "$tmp" && [[ -s $tmp ]]; then
                sh "$tmp" || warn "WP Toolkit installer finished with warnings."
            else
                warn "Could not download the WP Toolkit installer."
            fi
            rm -f "$tmp"
        fi
    else
        warn "cPanel not detected; skipping WP Toolkit."
    fi

    log "Downloading MySQLTuner and its data files to /root/mysqltuner ..."
    install -d /root/mysqltuner
    local raw=https://raw.githubusercontent.com/major/MySQLTuner-perl/master
    curl -fsSL https://mysqltuner.pl/ -o /root/mysqltuner/mysqltuner.pl || warn "mysqltuner.pl download failed"
    curl -fsSL "$raw/basic_passwords.txt" -o /root/mysqltuner/basic_passwords.txt || warn "basic_passwords.txt download failed"
    curl -fsSL "$raw/vulnerabilities.csv" -o /root/mysqltuner/vulnerabilities.csv || warn "vulnerabilities.csv download failed"
    chmod +x /root/mysqltuner/mysqltuner.pl 2>/dev/null || true

    [[ -f /etc/my.cnf ]] || { warn "/etc/my.cnf not found; skipping MySQL tuning."; return 0; }
    local ram_mb bp log_sz
    ram_mb="$(awk '/^MemTotal:/{print int($2/1024)}' /proc/meminfo)"
    bp=$(( ram_mb / 4 )); (( bp < 256 )) && bp=256; (( bp > 16384 )) && bp=16384
    if (( ram_mb >= 8192 )); then log_sz=256; else log_sz=128; fi
    log "Detected ${ram_mb} MB RAM: innodb_buffer_pool_size=${bp}M, innodb_log_file_size=${log_sz}M"

    ask_yes_no "Apply MySQL baseline to /etc/my.cnf and restart MySQL now?" n || { log "MySQL tuning skipped."; return 0; }

    backup_file /etc/my.cnf
    mycnf_set_default performance_schema ON
    mycnf_set_default innodb_buffer_pool_size "${bp}M"
    mycnf_set_default innodb_log_file_size "${log_sz}M"
    mycnf_set_default table_open_cache 6000

    if restart_mysql; then
        log "MySQL restarted with the new baseline."
    else
        warn "MySQL failed to restart; restoring /etc/my.cnf from backup."
        cp -a "$BACKUP_DIR/etc/my.cnf" /etc/my.cnf
        restart_mysql || die "MySQL still failing after rollback; check the MySQL error log immediately."
        die "MySQL tuning rolled back. Inspect the error log, then retry."
    fi
}

# ==============================================================================
# VERIFICATION
# ==============================================================================
resolve_a() {  # resolve_a HOST -> IPv4 addresses, one per line
    if command -v dig &>/dev/null; then dig +short +time=3 +tries=1 A "$1" 2>/dev/null | grep -E '^[0-9.]+$' || true
    else getent ahostsv4 "$1" 2>/dev/null | awk '{print $1}' | sort -u || true; fi
    return 0
}

verify_nameservers() {
    v_section "WHM nameservers & contact"
    is_cpanel || { v_warn "cPanel not installed; nameserver checks skipped"; return 0; }
    local k v n host ips local_ips
    local_ips="$(hostname -I 2>/dev/null || true)"
    for k in NS NS2 NS3 NS4; do
        v="$(awk -v k="$k" '$1==k{print $2}' /etc/wwwacct.conf 2>/dev/null || true)"
        [[ -z $v ]] && { [[ $k == NS || $k == NS2 ]] && v_fail "$k is not set in /etc/wwwacct.conf"; continue; }
        v_pass "$k = $v"
        ips="$(resolve_a "$v" | tr '\n' ' ')"
        if [[ -z ${ips// } ]]; then
            v_warn "$v has no A record yet (create it at your DNS host; glue record at the registrar)"
        else
            n=0; for host in $ips; do [[ " $local_ips " == *" $host "* ]] && n=1; done
            if (( n )); then v_pass "$v resolves to this server ($ips)"
            else v_warn "$v resolves to $ips which is not an IP on this server (fine if NAT / another NS server)"; fi
        fi
    done
    v="$(awk '$1=="CONTACTEMAIL"{print $2}' /etc/wwwacct.conf 2>/dev/null || true)"
    if [[ -n $v ]]; then v_pass "Contact email: $v"; else v_warn "No contact email set (re-run with CONTACT_EMAIL=you@domain --only nameservers)"; fi
}

verify_csf() {
    v_section "CSF firewall"
    if ! have_csf; then v_warn "CSF is not installed"; return 0; fi
    v_pass "CSF installed"
    if systemctl is-active --quiet lfd 2>/dev/null; then v_pass "lfd is running"; else v_warn "lfd is not running"; fi
    if [[ "$(csf_get TESTING)" == "0" ]]; then v_pass "TESTING mode is off (rules persistent)"; else v_fail "CSF is in TESTING mode - rules are flushed every 5 minutes"; fi
    if iptables -S 2>/dev/null | grep -q 'LOCALINPUT'; then v_pass "CSF iptables chains are loaded"; else v_fail "CSF chains not found in iptables (run: csf -r)"; fi
    if csv_has "$(csf_get TCP_IN)" "$SSH_PORT"; then v_pass "SSH port $SSH_PORT is in CSF TCP_IN"; else v_fail "SSH port $SSH_PORT missing from CSF TCP_IN"; fi
    if csv_has "$(csf_get TCP_IN)" 2087; then v_pass "WHM port 2087 open"; else v_warn "WHM port 2087 not in TCP_IN"; fi
    if grep -q 'd=10050' /etc/csf/csf.allow 2>/dev/null; then v_pass "Zabbix 10050 allow rule present (restricted to server IP)"; else v_warn "No Zabbix 10050 rule in csf.allow"; fi
}

verify_ssh() {
    v_section "SSH"
    local ports pr pa
    ports="$(sshd -T 2>/dev/null | awk '/^port /{print $2}' | sort -un | tr '\n' ' ')"
    v_pass "sshd effective ports: ${ports:-unknown}"
    if ss -ltn | grep -qE "[:.]${SSH_PORT}[[:space:]]"; then v_pass "sshd is listening on $SSH_PORT"; else v_fail "sshd is NOT listening on $SSH_PORT"; fi
    if timeout 5 bash -c "exec 3<>/dev/tcp/127.0.0.1/${SSH_PORT}; head -c 4 <&3" 2>/dev/null | grep -q '^SSH-'; then
        v_pass "SSH banner received on 127.0.0.1:$SSH_PORT"
    else
        v_fail "No SSH banner on 127.0.0.1:$SSH_PORT"
    fi
    pr="$(sshd -T 2>/dev/null | awk '/^permitrootlogin /{print $2}')"; pa="$(sshd -T 2>/dev/null | awk '/^passwordauthentication /{print $2}')"
    v_pass "PermitRootLogin=${pr:-?}  PasswordAuthentication=${pa:-?}"
    if [[ -n ${ADMIN_USER:-} ]] && id "$ADMIN_USER" &>/dev/null; then
        v_pass "Admin user '$ADMIN_USER' exists ($(id -Gn "$ADMIN_USER" | tr ' ' ','))"
        if has_pubkey_file "$(getent passwd "$ADMIN_USER" | cut -d: -f6)/.ssh/authorized_keys"; then v_pass "Admin user has an authorized SSH key"; else v_warn "Admin user has no SSH key (password login only)"; fi
    fi
    if ss -ltn | grep -qE '[:.]22[[:space:]]'; then
        v_warn "Port 22 is still open. After testing 'ssh -p $SSH_PORT <admin>@<server>' from ANOTHER terminal run: $0 --finalize-ssh"
    else
        v_pass "Port 22 closed (finalized)"
    fi
    if systemctl is-active --quiet "$(ssh_service)"; then v_pass "$(ssh_service) service is active"; else v_fail "ssh service inactive"; fi
}

verify_easyapache() {
    v_section "EasyApache 4 / Apache / PHP handler"
    is_cpanel || { v_warn "cPanel not installed; skipped"; return 0; }
    local httpd mods v h f n=0 conf=/etc/cpanel/ea4/php.conf
    httpd="$(httpd_bin)"
    [[ -n $httpd ]] || { v_fail "httpd binary not found"; return 0; }
    if "$httpd" -t >/dev/null 2>&1; then v_pass "Apache config syntax OK"; else v_fail "Apache config test failed ('$httpd -t')"; fi
    if systemctl is-active --quiet httpd 2>/dev/null || systemctl is-active --quiet apache2 2>/dev/null; then v_pass "Apache is running"; else v_fail "Apache is not running"; fi
    mods="$("$httpd" -M 2>/dev/null || true)"
    if grep -q 'mpm_event_module' <<<"$mods"; then v_pass "MPM: event"; else v_fail "mod_mpm_event not loaded"; fi
    if grep -q 'mpm_prefork_module' <<<"$mods"; then v_warn "mod_mpm_prefork is still loaded"; else v_pass "mod_mpm_prefork not loaded"; fi
    if grep -q 'remoteip_module' <<<"$mods"; then v_pass "mod_remoteip loaded"; else v_fail "mod_remoteip not loaded"; fi
    if [[ $INSTALL_FCGID == 1 ]]; then
        if grep -q 'fcgid_module' <<<"$mods"; then v_pass "mod_fcgid loaded"; else v_warn "mod_fcgid not loaded"; fi
    fi
    if [[ -f /etc/apache2/conf.d/zz-cloudflare-remoteip.conf ]] && grep -q 'RemoteIPHeader CF-Connecting-IP' /etc/apache2/conf.d/zz-cloudflare-remoteip.conf; then
        v_pass "Cloudflare RemoteIP config present ($(grep -c RemoteIPTrustedProxy /etc/apache2/conf.d/zz-cloudflare-remoteip.conf) trusted ranges)"
    else
        v_warn "Cloudflare RemoteIP config not present (real visitor IPs will not be restored)"
    fi

    if grep -q 'lsapi_module' <<<"$mods"; then
        v_pass "mod_lsapi loaded"
        if [[ -f $conf ]]; then
            for f in /opt/cpanel/ea-php*; do
                [[ -d $f ]] || continue; v="$(basename "$f")"
                h="$(awk -F': *' -v v="$v" '$1==v{print $2}' "$conf")"
                n=$((n+1))
                if [[ $h == lsapi ]]; then v_pass "$v handler = lsapi"; else v_fail "$v handler = ${h:-unset} (expected lsapi)"; fi
            done
            (( n )) || v_warn "No ea-php versions installed"
        else
            v_warn "$conf not found; cannot verify handlers"
        fi
    else
        if lsapi_available; then
            v_fail "mod_lsapi is available but not loaded (run --only easyapache, check $LOG_FILE)"
        else
            v_warn "mod_lsapi UNAVAILABLE on this server (needs CloudLinux OS/repo + license). Handler left unchanged; see notice in log."
        fi
    fi

    if has_whmapi; then
        if whmapi1 php_get_default_accounts_to_fpm 2>/dev/null | grep -qE 'default_accounts_to_fpm: *0'; then v_pass "PHP-FPM default for new accounts: OFF"
        else v_warn "PHP-FPM is still the default for new accounts"; fi
    fi
    n="$(grep -l '_is_present: 1' /var/cpanel/userdata/*/*.php-fpm.yaml 2>/dev/null | wc -l || true)"
    if (( ${n:-0} > 0 )); then v_warn "$n domain(s) still use PHP-FPM (WHM >> MultiPHP Manager: untick PHP-FPM for them)"; else v_pass "No domains on PHP-FPM"; fi
    v_pass "ModSecurity OWASP CRS intentionally not installed"
}

verify_php() {
    v_section "PHP hardening"
    local d found=0 bad=0
    for d in /opt/cpanel/ea-php*/root/etc/php.d; do
        [[ -d $d ]] || continue; found=1
        grep -q '^disable_functions' "$d/zz-security-hardening.ini" 2>/dev/null || bad=1
    done
    if (( ! found )); then v_warn "No ea-php installations found"
    elif (( bad )); then v_fail "disable_functions ini missing for some ea-php versions"
    else v_pass "disable_functions ini present for all ea-php versions"; fi
}

zbx_conf_get() { awk -F= -v k="$1" '$1==k{print $2; exit}' "$ZBX_CONF" 2>/dev/null || true; }
zbx_item() {  # zbx_item KEY -> raw test output
    zabbix_agent2 -c "$ZBX_CONF" -t "$1" 2>&1 || true
}

verify_zabbix() {
    v_section "Zabbix Agent 2"
    if ! pkg_installed zabbix-agent2; then v_fail "zabbix-agent2 is not installed"; return 0; fi
    v_pass "installed: $(zabbix_agent2 --version 2>/dev/null | head -1 || echo unknown)"
    pkg_installed zabbix-agent && v_warn "Legacy zabbix-agent (v1) is still installed"

    local srv act host meta out i
    srv="$(zbx_conf_get Server)"; act="$(zbx_conf_get ServerActive)"; host="$(zbx_conf_get Hostname)"; meta="$(zbx_conf_get HostMetadata)"
    ZBX_SERVER_IP="${ZBX_SERVER_IP:-$srv}"
    if [[ -n $srv && $srv == "$act" ]]; then v_pass "Server/ServerActive = $srv"; else v_fail "Server ('$srv') / ServerActive ('$act') missing or different"; fi
    if [[ -n $host ]]; then v_pass "Hostname = $host"; else v_fail "Hostname not set"; fi
    if [[ -n $meta ]]; then v_pass "HostMetadata = $meta"; else v_warn "HostMetadata empty"; fi

    systemctl is-enabled --quiet zabbix-agent2 2>/dev/null && v_pass "Service enabled at boot" || v_warn "Service not enabled at boot"
    if ! systemctl is-active --quiet zabbix-agent2; then
        warn "zabbix-agent2 not running; attempting one restart..."
        systemctl restart zabbix-agent2 || true; sleep 3
    fi
    if systemctl is-active --quiet zabbix-agent2; then v_pass "Service is running"; else v_fail "Service is NOT running (journalctl -u zabbix-agent2 -n 30)"; return 0; fi

    if ss -ltn | grep -qE '[:.]10050[[:space:]]'; then v_pass "Listening on TCP 10050"; else v_fail "Nothing listening on 10050"; fi

    out="$(zbx_item agent.ping)"
    if grep -q '\[s|1\]' <<<"$out"; then v_pass "agent.ping = 1"; else v_fail "agent.ping failed: $(head -c 200 <<<"$out")"; fi

    if [[ -f /etc/zabbix/zabbix_agent2.d/cpanel_mysql.conf ]]; then
        out="$(zbx_item mysql.ping)"
        if grep -q '\[s|1\]' <<<"$out"; then v_pass "mysql.ping = 1 (MySQL monitoring works)"; else v_fail "mysql.ping failed: $(head -c 200 <<<"$out")"; fi
    else
        v_warn "MySQL monitoring not configured (no cpanel_mysql.conf)"
    fi

    if [[ -f /etc/zabbix/zabbix_agent2.d/userparameter_exim.conf ]]; then
        out="$(zbx_item mailqueue)"
        if grep -qE '\[s\|[0-9]+\]' <<<"$out"; then v_pass "mailqueue = $(grep -oE '\[s\|[0-9]+\]' <<<"$out" | head -1)"; else v_warn "mailqueue item failed: $(head -c 150 <<<"$out")"; fi
    fi

    if have_csf; then
        grep -q 'd=10050' /etc/csf/csf.allow 2>/dev/null && v_pass "CSF allows 10050 from the Zabbix server" || v_fail "CSF has no 10050 allow rule"
    elif systemctl is-active --quiet firewalld 2>/dev/null; then
        firewall-cmd --list-rich-rules 2>/dev/null | grep -q '10050' && v_pass "firewalld rule for 10050 present" || v_warn "No firewalld rule for 10050"
    fi

    if [[ -n ${ZBX_SERVER_IP:-} ]]; then
        if timeout 5 bash -c "exec 3<>/dev/tcp/${ZBX_SERVER_IP}/10051" 2>/dev/null; then v_pass "Zabbix server ${ZBX_SERVER_IP}:10051 reachable (active checks can report)"
        else v_warn "Cannot reach ${ZBX_SERVER_IP}:10051 from here (firewall on the server side, or trapper port closed)"; fi
    fi

    if [[ -f /var/log/zabbix/zabbix_agent2.log ]]; then
        i="$(tail -n 30 /var/log/zabbix/zabbix_agent2.log | grep -icE 'cannot|failed|error|refused' || true)"
        if (( ${i:-0} > 0 )); then v_warn "Last 30 log lines contain $i error-like entries (tail /var/log/zabbix/zabbix_agent2.log)"; else v_pass "No errors in recent agent log"; fi
    fi
}

verify_imunify() {
    v_section "ImunifyAV"
    if command -v imunify-antivirus &>/dev/null || command -v imunify360-agent &>/dev/null; then v_pass "Imunify CLI present"; else v_fail "Imunify CLI not found"; fi
    if systemctl is-active --quiet imunify-antivirus 2>/dev/null || systemctl is-active --quiet imunify360 2>/dev/null; then v_pass "Imunify service running"; else v_warn "Imunify service not active"; fi
    [[ -f /etc/cron.d/imunifyav-weekly ]] && v_pass "Weekly scan cron present" || v_warn "Weekly scan cron missing"
}

verify_wptoolkit() {
    v_section "WP Toolkit / MySQLTuner"
    if is_cpanel; then
        [[ -d /usr/local/cpanel/3rdparty/wp-toolkit ]] && v_pass "WP Toolkit installed" || v_warn "WP Toolkit not installed"
    fi
    [[ -s /root/mysqltuner/mysqltuner.pl ]] && v_pass "MySQLTuner downloaded" || v_warn "MySQLTuner missing"
}

verify_all() {
    local all=$VERIFY_ONLY
    echo; echo "=============================== VERIFICATION ==============================="
    if (( all )) || ran nameservers; then verify_nameservers; fi
    if (( all )) || ran csf;         then verify_csf; fi
    if (( all )) || ran ssh;         then verify_ssh; fi
    if (( all )) || ran easyapache;  then verify_easyapache; fi
    if (( all )) || ran php;         then verify_php; fi
    if (( all )) || ran imunify;     then verify_imunify; fi
    if (( all )) || ran zabbix;      then verify_zabbix; fi
    if (( all )) || ran wptoolkit;   then verify_wptoolkit; fi
    return 0
}

print_whm_login() {
    is_cpanel || return 0
    local url=""
    if command -v whmlogin &>/dev/null; then
        echo "WHM login (whmlogin):"; whmlogin 2>/dev/null || true
        return 0
    fi
    if has_whmapi; then
        url="$(whmapi1 create_user_session user=root service=whostmgrd 2>/dev/null | awk '/^ *url:/{print $2; exit}')"
        if [[ -n $url ]]; then echo "WHM one-time login URL (short-lived, not logged): $url"; return 0; fi
    fi
    echo "Could not generate a WHM session; run 'whmlogin' manually."
}

# ------------------------------------------------------------------------------
# Main
# ------------------------------------------------------------------------------
if (( FINALIZE_SSH )); then
    finalize_ssh
    exit 0
fi

if (( ! VERIFY_ONLY )); then
    # Order matters: firewall must be ready before sshd moves ports.
    step_wanted cpanel      "Update cPanel (or install it if missing)?"                              && step_cpanel
    step_wanted nameservers "Set WHM nameservers + contact email?"                                   && step_nameservers
    step_wanted csf         "Install and configure the CSF firewall?"                                && step_csf
    step_wanted ssh         "Create admin user and harden SSH (port $SSH_PORT, keys only for root)?" && step_ssh
    step_wanted easyapache  "Configure EasyApache 4 (event MPM, mod_lsapi, mod_remoteip, no FPM)?"   && step_easyapache
    step_wanted php         "Apply PHP disable_functions hardening (MultiPHP)?"                      && step_php
    step_wanted imunify     "Install ImunifyAV and schedule weekly scans?"                           && step_imunify
    step_wanted zabbix      "Install and configure Zabbix Agent 2?"                                  && step_zabbix
    step_wanted wptoolkit   "Install WP Toolkit & MySQLTuner (optional MySQL baseline)?"             && step_wptoolkit_mysql
fi
true

verify_all

# ------------------------------------------------------------------------------
# Summary
# ------------------------------------------------------------------------------
cat <<SUMMARY

==============================================================================
                     AUTOMATED SCRIPT EXECUTION COMPLETE
==============================================================================
Log: $LOG_FILE    Config backups: $BACKUP_DIR
Verification: ${PASS_N} passed, ${WARN_N} warnings, ${FAIL_N} failed
SUMMARY

if (( WARN_N + FAIL_N > 0 )); then
    echo
    echo "Items needing attention:"
    for r in "${RESULTS[@]:-}"; do
        [[ -n $r && ${r%%|*} != PASS ]] && printf '  [%s] %s\n' "${r%%|*}" "${r#*|}"
    done
fi

cat <<SUMMARY

Still manual (cannot be automated safely):
 1. SSH: from ANOTHER terminal run  ssh -p $SSH_PORT <admin>@<server>  then:  $0 --finalize-ssh
 2. Nameservers: create A records for the nameservers and glue records at the registrar.
 3. Zabbix server: add this host (Hostname from $ZBX_CONF) and link the templates.
    MySQL password is in /root/.zabbix_mysql_password (mode 600); leave {\$MYSQL.DSN} empty.
 4. CSF UI: WHM >> Plugins >> ConfigServer Security & Firewall.
 Skipped by design: ModSecurity OWASP CRS, PHP-FPM (lsapi is used instead).
 Re-run checks anytime:  $0 --verify

SUMMARY

print_whm_login

if (( NEED_REBOOT )); then
    if ask_yes_no "A reboot is recommended after the cPanel install. Reboot now?" n; then
        log "Rebooting..."
        systemctl reboot
    fi
fi

if (( FAIL_N > 0 )); then exit 2; fi
exit 0
