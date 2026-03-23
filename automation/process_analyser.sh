#!/bin/bash

######################################################################
# Process Analyzer - Detect High CPU / High IO / Long Running Jobs
# Finds exact script, plugin, or PHP file behind the process.
# Logs everything to /root/process-monitor.log
#
# Author: Nihar (Custom Build)
######################################################################

LOGFILE="/root/process-monitor.log"
THRESHOLD_CPU=80      # processes using more than 80% CPU
THRESHOLD_MEM=20      # processes using more than 20% memory
THRESHOLD_TIME=3600   # running for more than 1 hour (3600 sec)

echo "-------------------------------------------------------" | tee -a $LOGFILE
echo "Process Scan Started: $(date)" | tee -a $LOGFILE
echo "-------------------------------------------------------" | tee -a $LOGFILE

# Get PIDs with high CPU or MEM
PIDS=$(ps -eo pid,%cpu,%mem,etime --sort=-%cpu | \
       awk -v cpu="$THRESHOLD_CPU" -v mem="$THRESHOLD_MEM" '
       NR>1 {
           split($4, t, ":");
           sec = (t[1]*3600)+(t[2]*60)+t[3];
           if ($2 > cpu || $3 > mem || sec > 3600) print $1
       }')

for PID in $PIDS; do
    echo "" | tee -a $LOGFILE
    echo "=== PROCESS FOUND: PID $PID ===" | tee -a $LOGFILE

    USER=$(ps -o user= -p $PID)
    CPU=$(ps -p $PID -o %cpu=)
    MEM=$(ps -p $PID -o %mem=)
    ETIME=$(ps -p $PID -o etime=)
    CMD=$(cat /proc/$PID/cmdline | tr '\0' ' ')

    EXE=$(readlink -f /proc/$PID/exe 2>/dev/null)
    CWD=$(readlink -f /proc/$PID/cwd 2>/dev/null)

    echo "User: $USER" | tee -a $LOGFILE
    echo "CPU Usage: $CPU%" | tee -a $LOGFILE
    echo "Memory Usage: $MEM%" | tee -a $LOGFILE
    echo "Elapsed Time: $ETIME" | tee -a $LOGFILE
    echo "Executable: $EXE" | tee -a $LOGFILE
    echo "Working Directory: $CWD" | tee -a $LOGFILE
    echo "Command: $CMD" | tee -a $LOGFILE

    # Detect WordPress Plugin / Theme files
    WPFILE=$(ls -lah /proc/$PID/cwd 2>/dev/null | grep -E "wp-content/" | awk '{print $NF}')

    if [[ -n "$WPFILE" ]]; then
        echo "WordPress Plugin/Theme Detected: $WPFILE" | tee -a $LOGFILE
    fi

    # Show file access via strace (light scan)
    echo "--- File Operations (strace sample) ---" | tee -a $LOGFILE
    strace -p $PID -e trace=file -s 200 -o /tmp/trace_$PID.log -t -T 2>/dev/null &
    sleep 2
    kill $! 2>/dev/null

    grep -E "\.php|\.js|\.sql|\.log" /tmp/trace_$PID.log | head -n 10 | tee -a $LOGFILE

    echo "---------------------------------------" | tee -a $LOGFILE

    #### OPTIONAL AUTO-KILL (disabled by default)
    # kill -9 $PID
    # echo "Process $PID killed." | tee -a $LOGFILE
done

echo "Scan Completed: $(date)" | tee -a $LOGFILE
echo "-------------------------------------------------------" | tee -a $LOGFILE
