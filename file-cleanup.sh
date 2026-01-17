#!/bin/bash
# File cleanup script to manage otel-logs.json rotation
# This script should run periodically via cron or systemd timer
# to prevent disk space issues

LOG_FILE="/tmp/otel-logs.json"
MAX_SIZE_MB=10
MAX_FILES=5
TOTAL_SIZE_MB=$((MAX_SIZE_MB * MAX_FILES))

# Function to get total size of log files in MB
get_total_size() {
    du -sm /tmp/otel-logs.json* 2>/dev/null | awk '{s+=$1} END {print s+0}'
}

# Function to get number of log files
get_file_count() {
    ls -1 /tmp/otel-logs.json* 2>/dev/null | wc -l
}

# Get current stats
TOTAL_SIZE=$(get_total_size)
FILE_COUNT=$(get_file_count)

echo "[$(date)] Current stats: ${FILE_COUNT} files, ${TOTAL_SIZE}MB total"

# Rotate main file if it exceeds max size
if [ -f "$LOG_FILE" ]; then
    FILE_SIZE_MB=$(du -sm "$LOG_FILE" | cut -f1)
    if [ "$FILE_SIZE_MB" -ge "$MAX_SIZE_MB" ]; then
        TIMESTAMP=$(date +%Y%m%d_%H%M%S)
        mv "$LOG_FILE" "${LOG_FILE}.${TIMESTAMP}"
        echo "[$(date)] Rotated ${LOG_FILE} to ${LOG_FILE}.${TIMESTAMP}"
    fi
fi

# Remove old files if total size or count exceeds limits
while [ "$TOTAL_SIZE" -gt "$TOTAL_SIZE_MB" ] || [ "$FILE_COUNT" -gt "$MAX_FILES" ]; do
    # Find oldest file
    OLDEST_FILE=$(ls -t /tmp/otel-logs.json* 2>/dev/null | tail -1)
    
    if [ -n "$OLDEST_FILE" ] && [ "$OLDEST_FILE" != "$LOG_FILE" ]; then
        echo "[$(date)] Removing old file: $OLDEST_FILE"
        rm -f "$OLDEST_FILE"
    else
        break
    fi
    
    # Recalculate
    TOTAL_SIZE=$(get_total_size)
    FILE_COUNT=$(get_file_count)
done

# Compress old files (optional, to save space but keep history)
find /tmp -name "otel-logs.json.*" -mtime +1 ! -name "*.gz" -exec gzip {} \; 2>/dev/null

echo "[$(date)] Cleanup complete: ${FILE_COUNT} files, ${TOTAL_SIZE}MB total"
