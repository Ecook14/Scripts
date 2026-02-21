#!/bin/bash
# Author: Nihar
# Description: Mail spam investigation and activity reporting.

SERVER=$(hostname -i)
REPORT_DIR="/usr/local/apache/htdocs"
QUEUE_REPORT="$REPORT_DIR/exim_email_reports.txt"
DATE_REPORT="$REPORT_DIR/requested_logs_for_dates.txt"
MAIL_LOG="/var/log/exim_mainlog"

# Prerequisites Checks
REQUIRED_CMDS=(exim eximstats exiqsumm netstat awk grep cut sort uniq ps hostname)
for cmd in "${REQUIRED_CMDS[@]}"; do
    command -v "$cmd" >/dev/null 2>&1 || {
        echo "Error: Required command '$cmd' not found. Please install it."
        exit 1
    }
done

# Delivery Report Directory
mkdir -p "$REPORT_DIR"
chmod 755 "$REPORT_DIR"

# Helper Safe Report Writr
write_report() {
    local file="$1"
    shift
    {
        echo "===== $(date) ====="
        "$@"
    } >> "$file" 2>/dev/null
}

# Timer/ETA helper
start_timer() {
    SECONDS=0
    START_TS=$(date +%s)
}
end_timer() {
    END_TS=$(date +%s)
    ELAPSED=$((END_TS - START_TS))
    echo "⏱ Completed in ${ELAPSED}s."
}

# Option 1: Generic email report....
generic_report() {
    echo "Generating generic email report..."
    start_timer
    > "$QUEUE_REPORT"

    echo "Step 1/9: Mail queue count..."
    write_report "$QUEUE_REPORT" exim -bpc

    echo "Step 2/9: Sorted senders..."
    write_report "$QUEUE_REPORT" bash -c \
        "exim -bpr | awk '/</ {gsub(/[<>]/, \"\", \$4); print \$4}' | sort | uniq -c | sort -n"

    echo "Step 3/9: Script cwd origins..."
    write_report "$QUEUE_REPORT" bash -c \
        "awk '/cwd=\\/home/ {for(i=1;i<=NF;i++) if(\$i ~ /cwd=/) print \$i}' $MAIL_LOG \
        | sort | uniq -c | sort -n"

    echo "Step 4/9: PHP script mails..."
    write_report "$QUEUE_REPORT" bash -c \
        "egrep -R 'X-PHP-Script' /var/spool/exim/input/* || echo 'No PHP mail scripts found'"

    echo "Step 5/9: Top domains..."
    write_report "$QUEUE_REPORT" eximstats -ne -nr "$MAIL_LOG"

    echo "Step 6/9: User home dirs..."
    write_report "$QUEUE_REPORT" bash -c \
        "ps -C exim -fH ewww | grep home || echo 'No home directories detected'"

    echo "Step 7/9: Nobody spam..."
    write_report "$QUEUE_REPORT" bash -c \
        "ps -C exim -fH ewww | awk '{for(i=1;i<=40;i++) if(\$i ~ /PWD/) print \$i}' \
        | sort | uniq -c | sort -n || echo 'No nobody spam detected'"

    echo "Step 8/9: Mail queue summary..."
    write_report "$QUEUE_REPORT" bash -c \
        "exim -bpr | exiqsumm -c | head || echo 'No mail in queue'"

    echo "Step 9/9: Port 25 connections..."
    write_report "$QUEUE_REPORT" bash -c \
        "netstat -plan 2>/dev/null | awk '\$4 ~ /:25$/ {split(\$5,a,\":\"); print a[1]}' \
        | sort | uniq -c | sort -nk1"

    chmod 644 "$QUEUE_REPORT"
    echo "Report saved at: http://$SERVER/$(basename "$QUEUE_REPORT")"
    end_timer
}

# Option 2: Report for specific dates...
date_report() {
    read -p "Enter start date (YYYY-MM-DD): " sd
    read -p "Enter end date (YYYY-MM-DD): " ed

    echo "Generating log report for $sd to $ed..."
    start_timer
    > "$DATE_REPORT"

    # More efficient: single awk match instead of multiple greps
    awk -v sd="$sd" -v ed="$ed" '
        $0 ~ sd || $0 ~ ed {print}
    ' $MAIL_LOG* >> "$DATE_REPORT"

    chmod 644 "$DATE_REPORT"
    echo "Report saved at: http://$SERVER/$(basename "$DATE_REPORT")"
    end_timer
}

# Menubar
options() {
    echo -e "\n\n ** OPTIONS **\n"
    echo "[1] Generic maillog report"
    echo "[2] Find mail report for dates"
    echo "[3] Exit"
    echo -e "\n *** END *** \n"

    read -p "Enter your choice: " choice
    case $choice in
        1) generic_report ;;
        2) date_report ;;
        3) echo "Exiting..."; exit 0 ;;
        *) echo "Invalid choice. Try again." ;;
    esac
}

while true; do
    options
done
