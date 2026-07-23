#!/bin/bash

WLFILE="/opt/mod_security/whitelist.conf"

echo "================================="
echo " ModSecurity Rule Whitelisting"
echo "================================="
echo

read -rp "Enter cPanel Username OR Domain: " TARGET
read -rp "Enter Rule ID: " RULEID

# Validate Rule ID
if ! [[ "$RULEID" =~ ^[0-9]+$ ]]; then
    echo "[ERROR] Invalid Rule ID"
    exit 1
fi

#
# Determine if input is username or domain
#
if [[ -f "/var/cpanel/users/$TARGET" ]]; then

    USERNAME="$TARGET"

    echo "[INFO] Username detected: $USERNAME"

    if [[ -f "/var/cpanel/suspended/$USERNAME" ]]; then
        echo "[ERROR] Account is suspended."
        exit 1
    fi

    if command -v uapi >/dev/null 2>&1; then

        DOMAINS=$(
            uapi --user="$USERNAME" DomainInfo list_domains 2>/dev/null |
            grep -E '^\s*-\s|main_domain:' |
            sed 's/main_domain:[[:space:]]*//g' |
            sed 's/^- //g'
        )

    else

        DOMAINS=$(awk -F': *' -v u="$USERNAME" '$2==u {print $1}' /etc/userdomains)

    fi

else

    DOMAIN="$TARGET"

    USERNAME=$(awk -F': *' -v d="$DOMAIN" '$1==d {print $2}' /etc/userdomains)

    if [[ -z "$USERNAME" ]]; then
        echo "[ERROR] Domain not found."
        exit 1
    fi

    if [[ -f "/var/cpanel/suspended/$USERNAME" ]]; then
        echo "[ERROR] Account is suspended."
        exit 1
    fi

    DOMAINS="$DOMAIN"

    echo "[INFO] Domain detected: $DOMAIN"
    echo "[INFO] Owner: $USERNAME"

fi

echo
echo "[INFO] Domains to whitelist:"
echo "$DOMAINS"
echo

for DOMAIN in $DOMAINS
do

    ENTRY="SecRule SERVER_NAME \"$DOMAIN\" phase:1,nolog,pass,ctl:ruleRemoveByID=$RULEID"

    if grep -Fq "$ENTRY" "$WLFILE" 2>/dev/null; then
        echo "[SKIP] $DOMAIN already has Rule $RULEID"
        continue
    fi

    echo "# user=$USERNAME domain=$DOMAIN rule=$RULEID" >> "$WLFILE"
    echo "$ENTRY" >> "$WLFILE"

    echo "[OK] Added Rule $RULEID for $DOMAIN"

done

echo
echo "[INFO] Validating Apache configuration..."

if apachectl configtest >/dev/null 2>&1; then

    echo "[OK] Apache configuration valid"

    if [[ -x /scripts/restartsrv_httpd ]]; then
        /scripts/restartsrv_httpd >/dev/null 2>&1
    else
        apachectl graceful
    fi

    echo "[OK] Apache reloaded"

else

    echo "[ERROR] Apache configuration test failed."
    echo "[ERROR] Reload aborted."
    exit 1

fi

echo
echo "[DONE]"
