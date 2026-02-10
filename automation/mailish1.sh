#! /bin/sh
echo Hello, name?
read name
echo Please Enter the Google Authentication code associated with $name.
read -s code
if [[ $code == 1 ]]
then
#!/bin/bash

# Calculate total RSS of Apache processes
total_rss=$(ps -C httpd -o rss= | awk '{sum += $1} END {print sum}')

# Number of Apache processes
num_processes=$(pgrep -c httpd)

# Average RSS per Apache process
average_rss=$(echo "scale=2; $total_rss / $num_processes" | bc)

# Convert average RSS to MB
average_rss_mb=$(echo "scale=2; $average_rss / 1024" | bc)

# Total available memory in MB
total_memory_mb=$(free -m | awk '/^Mem:/{print $2}')

# Memory required for non-Apache processes in MB
non_apache_memory_mb=2048

# Remaining memory for Apache in MB
remaining_memory_mb=$(echo "$total_memory_mb - $non_apache_memory_mb" | bc)

# Average memory usage per Apache process in MB
average_memory_per_process_mb=$(echo "scale=2; $remaining_memory_mb / $average_rss_mb" | bc)

# Round up to nearest integer
max_request_workers=$(echo "scale=0; $average_memory_per_process_mb / 1" | bc)

# Use WHM API to set MaxRequestWorkers
whmapi1 set_tweaksetting key=apache_max_clients value=$max_request_workers

echo "MaxRequestWorkers set to $max_request_workers"

# Restart Apache via WHM API
whmapi1 restartservice service=httpd

else
 echo Enter the correct code. Come back later. Byeee....$name
fi