#!/bin/bash

set -uo pipefail

DRY_RUN=0

ERROR_DOCS=$(cat <<'EOF'
ErrorDocument 400 "Bad Request. Please check your request and try again."
ErrorDocument 401 "Unauthorized access. Please login to continue."
ErrorDocument 403 "Access forbidden. Please contact support."
ErrorDocument 404 "Page not found. Please check the URL or go back to the homepage."
ErrorDocument 500 "Internal server error. Please try again later or contact support."
ErrorDocument 502 "Bad Gateway. The server received an invalid response."
ErrorDocument 503 "Service unavailable. The server is temporarily overloaded. Please try again later."
ErrorDocument 504 "Gateway timeout. The server took too long to respond."
EOF
)

usage() {
cat <<EOF
Usage:

$0 domain.com

$0 --reseller reselleruser

$0 --dry-run domain.com

$0 --dry-run --reseller reselleruser
EOF
exit 1
}

log() {
printf '[%s] %s\n' "$(date '+%F %T')" "$*"
}

get_docroot() {
local domain="$1"

whmapi1 domainuserdata domain="$domain" 2>/dev/null \
| awk '
    /documentroot:/ {
        print $2
        exit
    }
'

}

already_configured() {
local htaccess="$1"

[[ -f "$htaccess" ]] || return 1

grep -q '^ErrorDocument 400 ' "$htaccess" &&
grep -q '^ErrorDocument 401 ' "$htaccess" &&
grep -q '^ErrorDocument 403 ' "$htaccess" &&
grep -q '^ErrorDocument 404 ' "$htaccess"

}

process_htaccess() {

local domain="$1"
local docroot="$2"
local htaccess="${docroot}/.htaccess"

if [[ -z "$docroot" ]]; then
    log "ERROR: Unable to determine document root for $domain"
    return 1
fi

if [[ ! -d "$docroot" ]]; then
    log "ERROR: Document root does not exist: $docroot"
    return 1
fi

if already_configured "$htaccess"; then
    log "SKIP: $domain already configured"
    return 0
fi

log "Domain: $domain"
log "Docroot: $docroot"

if [[ "$DRY_RUN" -eq 1 ]]; then
    log "DRY RUN: Would update $htaccess"
    return 0
fi

touch "$htaccess"

{
    echo
    echo "# Added by monetization.sh ($(date))"
    echo "$ERROR_DOCS"
} >> "$htaccess"

log "UPDATED: $htaccess"

}

process_domain() {

local domain="$1"
local docroot

docroot=$(get_docroot "$domain")

if [[ -z "$docroot" ]]; then
    log "ERROR: Failed to retrieve document root for $domain"
    return 1
fi

process_htaccess "$domain" "$docroot"

}

process_reseller() {

local reseller="$1"
local found=0

log "Processing reseller: $reseller"

for acct in /var/cpanel/users/*; do

    [[ -f "$acct" ]] || continue

    local owner
    owner=$(grep '^OWNER=' "$acct" | cut -d= -f2)

    [[ "$owner" == "$reseller" ]] || continue

    found=1

    local domain
    domain=$(grep '^DNS=' "$acct" | cut -d= -f2)

    [[ -n "$domain" ]] || continue

    process_domain "$domain" || true

done

if [[ "$found" -eq 0 ]]; then
    log "ERROR: No accounts found under reseller '$reseller'"
    exit 1
fi

}

while [[ $# -gt 0 ]]; do
case "$1" in


    --dry-run)
        DRY_RUN=1
        shift
        ;;

    --reseller)
        [[ $# -lt 2 ]] && usage
        process_reseller "$2"
        exit 0
        ;;

    -*)
        usage
        ;;

    *)
        process_domain "$1"
        exit 0
        ;;

esac

done

usage
