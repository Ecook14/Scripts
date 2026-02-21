#!/bin/sh
# Author: Nihar
# Description: Automates HTTPS redirection setup in .htaccess.

echo "Enter home directory path (e.g. /home/user):"
read home
echo "Enter location (e.g. public_html):"
read loc
echo "Enter domain (without TLD):"
read domain
echo "Enter TLD (e.g. com):"
read tld

TARGET="$home/$loc/.htaccess"

if [ ! -f "$TARGET" ]; then
    touch "$TARGET"
fi

cat >> "$TARGET" <<EOF
RewriteEngine On
RewriteCond %{HTTPS} off
RewriteRule ^(.*)\$ https://%{HTTP_HOST}%{REQUEST_URI} [L,R=301]
EOF

echo "SSL rewrite rules added to $TARGET"
