#!/bin/bash
# Author: Nihar
# Description: Automated Zabbix Agent2 installation and configuration.

set -e

# Prompt for user input
read -p "Enter Zabbix Server IP: " ZBX_SERVER_IP
read -p "Enter Primary Domain Name: " PRIMARY_DOMAIN
read -p "Enter This Server's IP Address: " SERVER_IP
read -p "Enter HostMetadata (RC for Resellerclub, LB for Logicboxes): " HOST_METADATA

# Detect OS version
if [[ -f /etc/os-release ]]; then
  source /etc/os-release
  OS_ID=$ID
  OS_VERSION_ID=$VERSION_ID
  REPO_MAJOR_VERSION=${OS_VERSION_ID%%.*}
else
  echo "Cannot detect OS version. Exiting."
  exit 1
fi

echo "Detected OS: $OS_ID $OS_VERSION_ID"

# Determine correct Zabbix repo
case "$OS_ID" in
  almalinux|rocky|centos)
    ZABBIX_REPO_URL="https://repo.zabbix.com/zabbix/7.0/rhel/${REPO_MAJOR_VERSION}/x86_64/zabbix-release-latest-7.0.el${REPO_MAJOR_VERSION}.noarch.rpm"
    ;;
  ubuntu|debian)
    ZABBIX_REPO_DEB="zabbix-release_latest_7.0+debian12_all.deb"
    wget -q "https://repo.zabbix.com/zabbix/7.0/debian/pool/main/z/zabbix-release/${ZABBIX_REPO_DEB}"
    dpkg -i "$ZABBIX_REPO_DEB"
    apt update
    ;;
  *)
    echo "Unsupported OS. Exiting."
    exit 1
    ;;
esac

# Install Zabbix repo if not already installed
if [[ "$OS_ID" =~ (centos|almalinux|rocky) ]]; then
  if ! rpm -q zabbix-release &>/dev/null; then
    rpm -Uvh "$ZABBIX_REPO_URL"
  fi
  dnf clean all || yum clean all
  dnf makecache || yum makecache
fi

# Uninstall any old zabbix-agent
if rpm -q zabbix-agent &>/dev/null; then
  echo "Removing old Zabbix agent..."
  dnf remove -y zabbix-agent || yum remove -y zabbix-agent
fi

# Install Agent2 safely
echo "Installing Zabbix Agent2 (latest 7.x)..."
if ! dnf install -y zabbix-agent2; then
  echo "⚠️  Could not install Agent2 from repo, refreshing cache..."
  dnf clean all && dnf makecache
  dnf install -y zabbix-agent2 || yum install -y zabbix-agent2
fi

# Enable and start agent2
systemctl enable zabbix-agent2
systemctl restart zabbix-agent2

# Config file path
CONF_FILE="/etc/zabbix/zabbix_agent2.conf"

# Function to safely set a config parameter
set_zabbix2_param() {
  local key="$1"
  local value="$2"
  grep -q "^${key}=" "$CONF_FILE" && sudo sed -i "s|^${key}=.*|${key}=${value}|" "$CONF_FILE" || echo "${key}=${value}" >> "$CONF_FILE"
}

# Apply configuration
set_zabbix2_param "Server" "$ZBX_SERVER_IP"
set_zabbix2_param "ServerActive" "$ZBX_SERVER_IP"
set_zabbix2_param "Hostname" "${PRIMARY_DOMAIN}_${SERVER_IP}"
set_zabbix2_param "HostMetadata" "$HOST_METADATA"

# Firewall rule
iptables -I INPUT -p tcp -s "$ZBX_SERVER_IP" --dport 10050 -j ACCEPT
csf -a "$ZBX_SERVER_IP" || echo "CSF not installed, skipping firewall step."

# Mail queue monitor setup
MAILQUEUE_PATH="/etc/zabbix/custom/mailqueue"
mkdir -p /etc/zabbix/custom
touch "$MAILQUEUE_PATH"

EXIM_CONF="/etc/zabbix/zabbix_agent2.d/userparameter_exim.conf"
cat > "$EXIM_CONF" <<EOF
UserParameter=mailqueue,cat $MAILQUEUE_PATH
EOF

(crontab -l 2>/dev/null | grep -v "mailqueue"; echo "*/1 * * * * /usr/sbin/exim -bpc > $MAILQUEUE_PATH") | crontab -

# MySQL Monitoring Setup (Agent2-safe)
echo "======== Configuring MySQL Monitoring ========="

# Detect and disable conflicting legacy parameters
LEGACY_MYSQL_CONF="/etc/zabbix/zabbix_agentd.d/userparameter_mysql.conf"
if [ -f "$LEGACY_MYSQL_CONF" ]; then
  echo "⚠️  Found legacy MySQL config. Disabling to prevent key conflicts..."
  mkdir -p /etc/zabbix/disabled-userparams
  mv "$LEGACY_MYSQL_CONF" /etc/zabbix/disabled-userparams/ 2>/dev/null || true
fi

# Ensure Zabbix MySQL user exists
if command -v mysql &>/dev/null; then
  mysql -e "CREATE USER IF NOT EXISTS 'zabbix'@'localhost' IDENTIFIED BY 'outbFE@6789@';"
  mysql -e "GRANT REPLICATION CLIENT, PROCESS, SHOW DATABASES, SHOW VIEW ON *.* TO 'zabbix'@'localhost';"
  mysql -e "FLUSH PRIVILEGES;"
fi

# Create .my.cnf for Zabbix Agent2 plugin
mkdir -p /var/lib/zabbix
cat > /var/lib/zabbix/.my.cnf <<EOF
[client]
user=zabbix
password=outbFE@6789@
EOF
chown zabbix:zabbix /var/lib/zabbix/.my.cnf
chmod 600 /var/lib/zabbix/.my.cnf

# Enable built-in MySQL plugin if disabled
if ! grep -q "Plugins.Mysql.Enable" "$CONF_FILE"; then
  echo "Plugins.Mysql.Enable=true" >> "$CONF_FILE"
fi

# Restart agent2
systemctl restart zabbix-agent2

# Verification Output
echo
echo "======================================================="
echo "✅ Zabbix Agent2 installation & configuration complete!"
echo "Server: $ZBX_SERVER_IP"
echo "Hostname: ${PRIMARY_DOMAIN}_${SERVER_IP}"
echo "Metadata: $HOST_METADATA"
echo
echo "To verify MySQL plugin:"
echo "   zabbix_agent2 -t mysql.ping"
echo "   zabbix_agent2 -t mysql.version"
echo
echo "To verify logs:"
echo "   tail -f /var/log/zabbix/zabbix_agent2.log"
echo "======================================================="
