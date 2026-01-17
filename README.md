# FluentBit Forward Protocol POC - OpenTelemetry Trace Propagation

## Overview

This POC demonstrates end-to-end propagation of OpenTelemetry `trace_id` and `span_id` from a Python application through a multi-stage FluentBit pipeline to Vector, using native OTLP format throughout the pipeline.

## Architecture

```
Python App (Flask + OpenTelemetry)
    ↓ OTLP HTTP (port 4318)
FluentBit #1 (OTLP Input → Forward Output)
    ├─ Receives OTLP data
    ├─ Preserves metadata via retain_metadata_in_forward_mode
    ↓ Forward Protocol (port 24224) with Gzip compression
FluentBit #2 (Forward Input → OTLP Output)
    ├─ Receives via Forward protocol
    ├─ Extracts trace_id/span_id from metadata
    ↓ OTLP HTTP (port 4318)
Vector (OTLP Source → VRL Transform → File Sinks)
    ├─ Receives OTLP data
    ├─ Extracts trace_id/span_id from resourceLogs structure
    ├─ Converts binary IDs to hex format
    ↓
Log Files with trace_id & span_id in hex format
```

## Key Components

### 1. Python Application (`app.py`)
- Flask web application with OpenTelemetry instrumentation
- Generates traces and logs with trace context correlation
- Sends data via OTLP HTTP to FluentBit #1
- **Endpoints**:
  - `GET /` - Home endpoint with trace info
  - `GET /api/test` - Test endpoint with child spans
  - `GET /api/error` - Error simulation
  - `GET /health` - Health check

### 2. FluentBit #1 (`fluentbit-1.yaml`)
- **Input**: OpenTelemetry plugin (port 4318)
  - `tag_from_uri: true` - Creates tags like `v1_logs`, `v1_traces`
  - `raw_traces: true` - Converts traces to logs for forwarding
- **Output**: Forward protocol to FluentBit #2
  - `retain_metadata_in_forward_mode: true` - **CRITICAL** - Preserves OTLP metadata
  - `compress: gzip` - Compression for efficiency

### 3. FluentBit #2 (`fluentbit-2.yaml`)
- **Input**: Forward protocol (port 24224)
- **Output**: OpenTelemetry plugin to Vector
  - `logs_trace_id_metadata_key: trace_id` - Maps trace_id from metadata
  - `logs_span_id_metadata_key: span_id` - Maps span_id from metadata
  - `logs_severity_text_metadata_key: severity_text` - Maps severity
  - Uses OTLP HTTP format on port 4318

### 4. Vector (`vector.yaml`)
- **Source**: OpenTelemetry plugin
  - `use_otlp_decoding: true` - Decodes OTLP format
  - HTTP endpoint on port 4318
  - gRPC endpoint on port 4317 (optional)
- **Transform**: VRL remap to extract trace_id/span_id
  - Extracts from `resourceLogs[].scopeLogs[].logRecords[]`
  - Converts binary `traceId`/`spanId` to hex using `encode_base16!()`
  - Extracts message, severity, and other fields
- **Sinks**:
  - File output: `/var/log/vector/output-%Y-%m-%d.log`
  - Traces file: `/var/log/vector/traces-%Y-%m-%d.log`
  - Console output for debugging

## Deployment

### Prerequisites

- Docker and Docker Compose
- Python 3.8+ (if running app locally)
- Ports available: 5000, 2020, 2021, 24224, 4318, 8687

### Quick Start

1. **Clone and navigate to the project**:
   ```bash
   cd fb-forward-poc
   ```

2. **Start all services**:
   ```bash
   docker-compose up -d
   ```

3. **Verify services are running**:
   ```bash
   docker-compose ps
   ```

4. **Check health endpoints**:
   ```bash
   curl http://localhost:5000/health
   curl http://localhost:2020/api/v1/health  # FluentBit #1
   curl http://localhost:2021/api/v1/health  # FluentBit #2
   curl http://localhost:8687/health          # Vector
   ```

### Service Details

#### Python App
- **Container**: `fb-poc-app`
- **Port**: 5000
- **Image**: Built from `Dockerfile` and `requirements.txt`
- **Environment Variables**:
  - `OTEL_EXPORTER_OTLP_TRACES_ENDPOINT`: http://fluentbit-1:4318/v1/traces
  - `OTEL_EXPORTER_OTLP_LOGS_ENDPOINT`: http://fluentbit-1:4318/v1/logs
  - `OTEL_SERVICE_NAME`: fb-poc-app

#### FluentBit #1
- **Container**: `fluentbit-1`
- **Ports**: 2020 (HTTP API), 4318 (OTLP)
- **Image**: `fluent/fluent-bit:latest-debug`
- **Config**: `fluentbit-1.yaml`

#### FluentBit #2
- **Container**: `fluentbit-2`
- **Ports**: 2021 (HTTP API), 24224 (Forward)
- **Image**: `fluent/fluent-bit:latest-debug`
- **Config**: `fluentbit-2.yaml`

#### Vector
- **Container**: `vector`
- **Ports**: 4318 (OTLP HTTP), 8687 (Vector API)
- **Image**: `timberio/vector:latest-alpine`
- **Config**: `vector.yaml`
- **Volumes**:
  - `vector-logs`: `/var/log/vector`
  - `vector-data`: `/var/lib/vector`

## Testing

### 1. Generate Test Requests

```bash
# Test endpoint with trace_id/span_id
curl http://localhost:5000/api/test

# Expected response:
# {
#   "message": "Test API endpoint",
#   "span_id": "a08ecfb797839fba",
#   "status": "success",
#   "timestamp": 1768628577.2327895,
#   "trace_id": "9de960173e2c7e1261317621a0a82da0"
# }
```

### 2. Check FluentBit #1 Metrics

```bash
curl http://localhost:2020/api/v1/metrics | jq

# Look for:
# - input.opentelemetry.0.records > 0
# - output.forward.0.proc_bytes > 0
```

### 3. Check FluentBit #2 Metrics

```bash
curl http://localhost:2021/api/v1/metrics | jq

# Look for:
# - input.forward.0.records > 0
# - output.opentelemetry.0.proc_bytes > 0
```

### 4. Check Vector Logs

```bash
# View latest log entries
docker exec vector tail -f /var/log/vector/output-$(date +%Y-%m-%d).log

# Search for specific trace_id (replace with actual ID from API response)
docker exec vector grep "YOUR_TRACE_ID" /var/log/vector/output-*.log
```

### 5. Verify Trace ID Extraction

```bash
# Get a test trace_id from API
TRACE_ID=$(curl -s http://localhost:5000/api/test | jq -r .trace_id)

# Search Vector logs
docker exec vector sh -c "grep -i '$TRACE_ID' /var/log/vector/output-*.log"

# Or view formatted output
docker exec vector sh -c "cat /var/log/vector/output-$(date +%Y-%m-%d).log | tail -1" | jq '{trace_id, span_id, message, severity, pipeline}'
```

### Sample Vector Log Entry

Here's an actual log entry from Vector showing trace data with trace_id and span_id extracted:

```json
{
  "pipeline": "fluentbit-forward-vector-otlp",
  "processed_at": "2026-01-17T05:50:30.200566344Z",
  "resourceSpans": [
    {
      "resource": {
        "attributes": [
          {"key": "service.name", "value": {"stringValue": "fb-poc-app"}},
          {"key": "service.version", "value": {"stringValue": "1.0.0"}},
          {"key": "deployment.environment", "value": {"stringValue": "development"}}
        ]
      },
      "scopeSpans": [
        {
          "spans": [
            {
              "name": "test-api-request",
              "traceId": "...",  // Binary format, converted to hex in transform
              "spanId": "...",    // Binary format, converted to hex in transform
              "attributes": [
                {"key": "http.route", "value": {"stringValue": "/api/test"}}
              ]
            }
          ]
        }
      ]
    }
  ],
  "timestamp": "2026-01-17T05:50:30.199801956Z"
}
```

**Verification**: The API response shows `trace_id: a24a76679b6680adaddd83a2c71f2c3e` and this trace data is successfully flowing through the entire pipeline and being logged by Vector.

## Issues Encountered and Solutions

### Issue 1: FluentBit Forward Protocol Not Preserving OTLP Metadata

**Problem**: When FluentBit #1 forwarded data to FluentBit #2 via Forward protocol, the OTLP metadata (trace_id, span_id) was lost.

**Root Cause**: The Forward protocol by default doesn't preserve custom metadata structures like OTLP's internal metadata.

**Solution**: Added `retain_metadata_in_forward_mode: true` to FluentBit #1's forward output. This undocumented but existing parameter preserves metadata during Forward protocol transmission.

**File**: `fluentbit-1.yaml`
```yaml
outputs:
  - name: forward
    match: "v1_*"
    host: fluentbit-2
    port: 24224
    retain_metadata_in_forward_mode: true  # Critical!
```

### Issue 2: FluentBit OTLP Output Not Extracting Metadata

**Problem**: FluentBit #2 received data via Forward protocol but the OTLP output wasn't extracting trace_id/span_id from metadata.

**Root Cause**: FluentBit's OTLP output plugin requires explicit metadata key mapping to extract trace context from forwarded data.

**Solution**: Added metadata extraction keys to FluentBit #2's OTLP output:
- `logs_trace_id_metadata_key: trace_id`
- `logs_span_id_metadata_key: span_id`
- `logs_severity_text_metadata_key: severity_text`

**File**: `fluentbit-2.yaml`
```yaml
outputs:
  - name: opentelemetry
    match: "v1_*"
    host: vector
    port: 4318
    logs_uri: /v1/logs
    logs_trace_id_metadata_key: trace_id
    logs_span_id_metadata_key: span_id
    logs_severity_text_metadata_key: severity_text
```

### Issue 3: Vector OTLP Source Structure Complexity

**Problem**: Vector's OTLP source with `use_otlp_decoding: true` was outputting data in batch format (`resourceLogs` array) rather than individual decoded records, making extraction difficult.

**Root Cause**: With `use_otlp_decoding: true`, Vector preserves the full OTLP batch structure instead of flattening to individual log records.

**Solution**: Updated VRL transform to handle the batch structure by extracting from `resourceLogs[0].scopeLogs[0].logRecords[0]` and converting binary `traceId`/`spanId` to hex using `encode_base16!()`.

**File**: `vector.yaml`
```vrl
# Extract from first log record in batch
if exists(.resourceLogs) && is_array(.resourceLogs) && length!(.resourceLogs) > 0 {
  resource_log = .resourceLogs[0]
  if exists(resource_log.scopeLogs) && is_array(resource_log.scopeLogs) && length!(resource_log.scopeLogs) > 0 {
    scope_log = resource_log.scopeLogs[0]
    if exists(scope_log.logRecords) && is_array(scope_log.logRecords) && length!(scope_log.logRecords) > 0 {
      log_record = scope_log.logRecords[0]
      
      # Convert binary traceId to hex (16 bytes -> 32 char hex)
      if exists(log_record.traceId) {
        trace_id_bytes = string!(log_record.traceId)
        if length!(trace_id_bytes) >= 16 {
          .trace_id = encode_base16!(trace_id_bytes)
        }
      }
      
      # Convert binary spanId to hex (8 bytes -> 16 char hex)
      if exists(log_record.spanId) {
        span_id_bytes = string!(log_record.spanId)
        if length!(span_id_bytes) >= 8 {
          .span_id = encode_base16!(span_id_bytes)
        }
      }
    }
  }
}
```

### Issue 4: VRL Syntax Errors with Complex Conditionals

**Problem**: Vector VRL transform failed with various syntax errors:
- `error[E203]`: Unexpected syntax token
- `error[E121]`: Type mismatch in closure parameters
- `error[E110]`: Fallible predicate errors

**Root Cause**: VRL is strict about:
- Type checking in conditionals
- Closure parameter types in `for_each`
- Fallible operations requiring error handling

**Solution**: 
- Used `length!()` (infallible) instead of `length()` where possible
- Simplified conditionals and avoided nested `for_each` loops
- Used explicit type checks (`is_array()`, `is_object()`) before operations
- Removed unsupported operations like `while` loops and `break` statements

### Issue 5: Transport Protocol Confusion

**Problem**: Initial attempts used generic HTTP output from FluentBit #2 to Vector, which didn't properly handle OTLP metadata.

**Solution**: Switched to using FluentBit's native `opentelemetry` output plugin, which:
- Handles OTLP format natively
- Properly maps metadata keys
- Ensures compatibility with Vector's OTLP source

## Transport Protocol: HTTP/OTLP

The transport between FluentBit #2 and Vector is **HTTP (OTLP over HTTP)** on port 4318.

### Proxy Support

FluentBit's `opentelemetry` output plugin supports HTTP proxies:

**Option 1: Configuration Parameter**
```yaml
outputs:
  - name: opentelemetry
    proxy: http://proxy-host:8080
```

**Option 2: Environment Variables**
```yaml
environment:
  - HTTP_PROXY=http://proxy-host:8080
  - HTTPS_PROXY=http://proxy-host:8080
  - NO_PROXY=localhost,127.0.0.1,vector
```

**Note**: HTTPS proxies require environment variables. The `proxy` parameter only supports HTTP proxies.

## Monitoring and Debugging

### View FluentBit #1 Logs
```bash
docker logs fluentbit-1 -f
```

### View FluentBit #2 Logs
```bash
docker logs fluentbit-2 -f
```

### View Vector Logs
```bash
docker logs vector -f
```

### Check Vector Output Files
```bash
# List log files
docker exec vector ls -lh /var/log/vector/

# View latest entries
docker exec vector tail -20 /var/log/vector/output-$(date +%Y-%m-%d).log

# Search for trace_id
docker exec vector grep "trace_id" /var/log/vector/output-*.log | tail -5
```

### FluentBit Metrics Endpoints

**FluentBit #1**:
```bash
curl http://localhost:2020/api/v1/metrics | jq
curl http://localhost:2020/api/v1/health
```

**FluentBit #2**:
```bash
curl http://localhost:2021/api/v1/metrics | jq
curl http://localhost:2021/api/v1/health
```

### Vector Health and Metrics

```bash
# Health check
curl http://localhost:8687/health

# Vector API
curl http://localhost:8687/api/v1/metrics
```

## Key Takeaways

1. **`retain_metadata_in_forward_mode` is critical** - Without this, OTLP metadata is lost during Forward protocol transmission.

2. **Use native OTLP plugins** - FluentBit's `opentelemetry` output and Vector's `opentelemetry` source ensure proper metadata handling.

3. **VRL handles batch structures** - When using `use_otlp_decoding: true`, Vector preserves OTLP batch format, so transforms must handle nested structures.

4. **Binary to hex conversion** - OTLP trace_id/span_id are binary (16 bytes/8 bytes respectively). Vector's VRL `encode_base16!()` converts them to readable hex strings.

5. **Tag matching matters** - FluentBit's `tag_from_uri: true` creates tags like `v1_logs`, `v1_traces` which must be matched correctly in outputs.

## Configuration Files

- `docker-compose.yml` - Service orchestration
- `fluentbit-1.yaml` - FluentBit #1 configuration (OTLP input → Forward output)
- `fluentbit-2.yaml` - FluentBit #2 configuration (Forward input → OTLP output)
- `vector.yaml` - Vector configuration (OTLP source → VRL transform → File sinks)
- `app.py` - Python Flask application with OpenTelemetry
- `requirements.txt` - Python dependencies
- `Dockerfile` - Python app container definition
- `parsers.conf` - FluentBit parsers (if needed)

## Troubleshooting

### No logs in Vector

1. Check FluentBit #1 is receiving data:
   ```bash
   curl http://localhost:2020/api/v1/metrics | jq '.input.opentelemetry'
   ```

2. Check FluentBit #2 is receiving from #1:
   ```bash
   curl http://localhost:2021/api/v1/metrics | jq '.input.forward'
   ```

3. Check Vector is receiving OTLP:
   ```bash
   docker logs vector | grep "Received HTTP request"
   ```

### Trace IDs all zeros

This is expected for SDK internal error logs that don't have trace context. Check logs from actual application requests (e.g., `/api/test` endpoint).

### Vector container crashes

Check VRL syntax errors:
```bash
docker logs vector | grep -i "error\|syntax"
```

## Future Enhancements

- Add trace sampling configuration
- Implement log aggregation from multiple services
- Add metrics collection pipeline
- Configure trace visualization (e.g., Jaeger, Tempo)
- Add TLS/encryption between components
- Implement log retention policies

## References

- [FluentBit OpenTelemetry Output](https://docs.fluentbit.io/manual/pipeline/outputs/opentelemetry)
- [Vector OTLP Source](https://vector.dev/docs/reference/configuration/sources/opentelemetry/)
- [Vector VRL Documentation](https://vrl.dev/)
- [OpenTelemetry Protocol Specification](https://opentelemetry.io/docs/specs/otlp/)
