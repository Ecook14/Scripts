#!/bin/bash
# Author: Nihar
# Description: Highload system monitoring with Atop and Inotify.

clear
echo "#####################################################"
echo "#           HIGH LOAD MONITOR – ONE-TIME SETUP      #"
echo "#####################################################"

# Log start
mkdir -p /var/log/monitoring
LOG="/var/log/monitoring/setup_$(date +%Y%m%d).log"
echo "Setup started at $(date)" > "$LOG"

# Root check
if [[ $EUID -ne 0 ]]; then
   echo "This script must be run as root" 
   exit 1
fi

# Detect OS
if [ -e /etc/centos-release ]; then
    VERSION=$(rpm -q --queryformat '%{VERSION}' centos-release)
    [ "$VERSION" == "6" ] && distro="centos6" || distro="centos7"
elif [ -e /etc/os-release ] && grep -qi "ubuntu" /etc/os-release; then
    distro="ubuntu"
elif [ -e /etc/redhat-release ]; then
    distro="rhel_based"
fi

echo "Detected OS: $distro"

# Prerequisites
case $distro in
    ubuntu)
        apt update && apt install -y atop inotify-tools
        systemctl enable --now atop
        ;;
    centos7|rhel_based)
        yum install -y epel-release atop inotify-tools
        systemctl enable --now atop
        ;;
    centos6)
        yum install -y epel-release
        yum install -y atop inotify-tools
        chkconfig atop on
        service atop start
        ;;
esac

# Create Inotify Watcher Script
WATCHER="/usr/local/bin/inotify-watcher.sh"
cat > "$WATCHER" <<'EOF'
#!/bin/bash
WATCH_DIR="/var/www/html"
LOG_FILE="/var/log/monitoring/inotify_events.log"
inotifywait -m -r -e create,modify,delete "$WATCH_DIR" | while read path action file; do
    echo "$(date): $action on $path$file" >> "$LOG_FILE"
done
EOF

chmod +x "$WATCHER"

# Start Watcher
if command -v systemctl >/dev/null 2>&1; then
    # Create systemd service
    cat > /etc/systemd/system/inotify-watcher.service <<EOF
[Unit]
Description=Inotify File System Watcher
After=network.target

[Service]
ExecStart=$WATCHER
Restart=always

[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reload
    systemctl enable --now inotify-watcher
else
    nohup bash "$WATCHER" &
fi

echo "Setup complete. Atop and Inotify watcher are now running."
