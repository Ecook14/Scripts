#!/bin/bash
# Author: Nihar
# ============================================================
# Secure Server Log & Data Collection + Remote Sync Script
# ============================================================
# Collects logs, cPanel data (if available), or both.
# Transfers securely to remote server using password-based rsync.
# Stores results in /usr/local/apache/htdocs/<domain> on remote.
# Automatically applies .htpasswd protection and provides access URL.
# Improvised (Thoda thoda kurachu kurachu) 
# Cpanel pkgacct identification and execution. 
# ============================================================

green=$(tput setaf 2)
red=$(tput setaf 1)
yellow=$(tput setaf 3)
reset=$(tput sgr0)

echo ""
echo "${green}=== Secure Server Log & Data Collection Utility ===${reset}"
echo ""

# Step 1: Choose what to collect
echo "${yellow}What do you want to collect?${reset}"
select collect_type in "Logs" "DomainData" "Both"; do
    case $collect_type in
        Logs|DomainData|Both ) break;;
        * ) echo "Please choose 1, 2, or 3."; ;;
    esac
done

# Step 2: Domain details
echo ""
read -p "Enter the domain name: " dom
read -p "Enter the subdomain (if applicable, or press Enter): " dom1

# Step 3: Remote server details
echo ""
echo "${green}Enter remote server details for rsync storage:${reset}"
read -p "Remote Server IP or Hostname: " remote_ip
read -p "Remote Server Username: " remote_user
read -s -p "Remote Server Password: " remote_pass
echo ""

# Step 4: Prepare working directory
work_dir="/root/${dom}_collection_$(date +%Y%m%d_%H%M%S)"
mkdir -p "$work_dir"

echo ""
echo "${green}Collecting requested data...${reset}"

# Step 5: Collect logs
if [[ "$collect_type" == "Logs" || "$collect_type" == "Both" ]]; then
    echo "→ Collecting logs..."
    mkdir -p "$work_dir/logs"

    zgrep "$dom" /var/log/messages* > "$work_dir/logs/messages.txt" 2>/dev/null
    egrep "$dom|$dom1" /usr/local/apache/domlogs/* > "$work_dir/logs/domain_logs.txt" 2>/dev/null
    grep "$dom" /usr/local/apache/logs/access_log > "$work_dir/logs/apache_access.txt" 2>/dev/null
    zgrep "$dom" /var/log/exim_mainlog* > "$work_dir/logs/exim_logs.txt" 2>/dev/null
    zgrep "$dom" /var/log/maillog* > "$work_dir/logs/mail_logs.txt" 2>/dev/null
fi

# Step 6: Collect website / user data
if [[ "$collect_type" == "DomainData" || "$collect_type" == "Both" ]]; then
    echo ""
    echo "> Checking for cPanel environment..."
    if [[ -x "/scripts/pkgacct" ]]; then
        user=$(/scripts/whoowns "$dom" 2>/dev/null)
        if [[ -n "$user" ]]; then
            echo "→ cPanel detected. Packaging account for user '$user'..."
            /scripts/pkgacct "$user" "$work_dir" >/dev/null 2>&1
        else
            echo "${red}Unable to detect cPanel user for ${dom}.${reset}"
            echo "${yellow}Proceeding to manual home directory selection...${reset}"
            read -p "Enter full home directory path to include: " homedir
            if [[ -d "$homedir" ]]; then
                mkdir -p "$work_dir/data"
                rsync -a "$homedir" "$work_dir/data/" 2>/dev/null
            else
                echo "${red}Invalid directory provided. Skipping domain data.${reset}"
            fi
        fi
    else
        echo "${yellow}No cPanel detected.${reset}"
        read -p "Enter full home directory path to include: " homedir
        if [[ -d "$homedir" ]]; then
            mkdir -p "$work_dir/data"
            rsync -a "$homedir" "$work_dir/data/" 2>/dev/null
        else
            echo "${red}Invalid directory provided. Skipping domain data.${reset}"
        fi
    fi
fi

# Step 7: Create password-protected ZIP archive
echo ""
echo "${green}Creating password-protected ZIP archive...${reset}"
zip_pass=$(openssl rand -base64 10)
cd "$work_dir" || exit
zip_name="${dom}_data_$(date +%s).zip"
zip -r -P "$zip_pass" "$zip_name" . >/dev/null
cd - >/dev/null

# Step 8: Transfer data via rsync
echo ""
echo "${green}Transferring data to remote server...${reset}"

if ! command -v sshpass >/dev/null 2>&1; then
    echo "${yellow}Installing sshpass...${reset}"
    yum install -y sshpass >/dev/null 2>&1 || apt install -y sshpass >/dev/null 2>&1
fi

remote_path="/usr/local/apache/htdocs/${dom}"
sshpass -p "$remote_pass" ssh -o StrictHostKeyChecking=no "${remote_user}@${remote_ip}" "mkdir -p ${remote_path}"

sshpass -p "$remote_pass" rsync -avz -e "ssh -o StrictHostKeyChecking=no" \
"$work_dir/$zip_name" "${remote_user}@${remote_ip}:${remote_path}/" >/dev/null 2>&1

# Step 9: Apply Apache Basic Auth (.htaccess + .htpasswd)
echo ""
echo "${green}Applying Basic Auth protection on remote server...${reset}"

htuser="access_$(date +%s)"
htpass=$(openssl rand -base64 8)

sshpass -p "$remote_pass" ssh -o StrictHostKeyChecking=no "${remote_user}@${remote_ip}" bash <<EOF
htpasswd_file="/usr/local/apache/htdocs/.htpasswd"
mkdir -p \$(dirname "\$htpasswd_file")

# Ensure htpasswd utility or fallback to OpenSSL
if command -v htpasswd >/dev/null 2>&1; then
    htpasswd -bB "\$htpasswd_file" "${htuser}" "${htpass}" >/dev/null
else
    echo "${htuser}:$(openssl passwd -apr1 ${htpass})" >> "\$htpasswd_file"
fi

cat > "${remote_path}/.htaccess" <<EOL
AuthType Basic
AuthName "Restricted Access"
AuthUserFile /usr/local/apache/htdocs/.htpasswd
Require valid-user
EOL

chmod 644 "${remote_path}/.htaccess"
EOF

# Step 10: Display summary
echo ""
echo "${green}=== Transfer Complete ===${reset}"
echo "Files stored at: ${remote_path}"
echo ""
echo "Access URL: ${yellow}http://${remote_ip}/${dom}/${zip_name}${reset}"
echo "HTTP Username: ${yellow}${htuser}${reset}"
echo "HTTP Password: ${yellow}${htpass}${reset}"
echo ""
echo "ZIP Password: ${yellow}${zip_pass}${reset}"
echo ""
echo "${green}All done! Data is securely stored and protected remotely.${reset}"

rm -rf abuse.sh
