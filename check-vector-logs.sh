#!/bin/bash

# Script to check Vector logs for trace_id and span_id

echo "======================================"
echo "Checking Vector Logs"
echo "======================================"
echo ""

CURRENT_DATE=$(date +%Y-%m-%d)
OUTPUT_LOG="/var/log/vector/output-${CURRENT_DATE}.log"
TRACES_LOG="/var/log/vector/traces-${CURRENT_DATE}.log"

echo "Fetching logs from Vector container..."
echo ""

# Check if container is running
if ! docker ps | grep -q vector; then
  echo "ERROR: Vector container is not running!"
  exit 1
fi

# Display output logs
echo "=== OUTPUT LOG (Last 10 entries) ==="
echo "--------------------------------------"
docker exec vector sh -c "if [ -f '$OUTPUT_LOG' ]; then tail -10 '$OUTPUT_LOG'; else echo 'Log file not found'; fi" | jq '.' 2>/dev/null || docker exec vector sh -c "tail -10 '$OUTPUT_LOG' 2>/dev/null || echo 'No logs yet'"
echo ""

# Search for trace_id and span_id
echo "=== SEARCHING FOR TRACE_ID AND SPAN_ID ==="
echo "--------------------------------------"
docker exec vector sh -c "if [ -f '$OUTPUT_LOG' ]; then cat '$OUTPUT_LOG'; else echo '{}'; fi" | jq 'select(.data.trace_id != null or .data.span_id != null or .data.traceId != null or .data.spanId != null) | {trace_id: (.data.trace_id // .data.traceId), span_id: (.data.span_id // .data.spanId), timestamp: .timestamp, record_type: .record_type}' 2>/dev/null || echo "Processing logs..."
echo ""

# Count entries with trace context
echo "=== STATISTICS ==="
echo "--------------------------------------"
TOTAL_LOGS=$(docker exec vector sh -c "wc -l < '$OUTPUT_LOG' 2>/dev/null || echo 0")
echo "Total log entries: $TOTAL_LOGS"

# Alternative: Show raw logs if JSON parsing fails
echo ""
echo "=== RAW LOGS (Last 5 entries) ==="
echo "--------------------------------------"
docker exec vector sh -c "tail -5 '$OUTPUT_LOG' 2>/dev/null || echo 'No logs available yet'"
echo ""

echo "======================================"
echo "Log Check Complete!"
echo "======================================"
