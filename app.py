"""
Sample Python application with OpenTelemetry instrumentation
Sends both traces and logs with trace_id and span_id correlation
"""
from flask import Flask, jsonify
import logging
import time
import os

from opentelemetry import trace
from opentelemetry.sdk.trace import TracerProvider
from opentelemetry.sdk.trace.export import BatchSpanProcessor
from opentelemetry.exporter.otlp.proto.http.trace_exporter import OTLPSpanExporter
from opentelemetry.sdk.resources import Resource
from opentelemetry.instrumentation.flask import FlaskInstrumentor

from opentelemetry._logs import set_logger_provider
from opentelemetry.sdk._logs import LoggerProvider, LoggingHandler
from opentelemetry.sdk._logs.export import BatchLogRecordProcessor
from opentelemetry.exporter.otlp.proto.http._log_exporter import OTLPLogExporter

# Configure OpenTelemetry Resource
resource = Resource.create({
    "service.name": "fb-poc-app",
    "service.version": "1.0.0",
    "deployment.environment": "development"
})

# Configure Tracer Provider
trace_provider = TracerProvider(resource=resource)
otlp_trace_endpoint = os.getenv("OTEL_EXPORTER_OTLP_TRACES_ENDPOINT", "http://fluentbit-1:4318/v1/traces")
trace_exporter = OTLPSpanExporter(endpoint=otlp_trace_endpoint)
trace_provider.add_span_processor(BatchSpanProcessor(trace_exporter))
trace.set_tracer_provider(trace_provider)

# Configure Logger Provider
logger_provider = LoggerProvider(resource=resource)
otlp_log_endpoint = os.getenv("OTEL_EXPORTER_OTLP_LOGS_ENDPOINT", "http://fluentbit-1:4318/v1/logs")
log_exporter = OTLPLogExporter(endpoint=otlp_log_endpoint)
logger_provider.add_log_record_processor(BatchLogRecordProcessor(log_exporter))
set_logger_provider(logger_provider)

# Configure Python logging to use OTLP
handler = LoggingHandler(level=logging.INFO, logger_provider=logger_provider)
logging.getLogger().addHandler(handler)
logging.getLogger().setLevel(logging.INFO)

# Create Flask app
app = Flask(__name__)

# Instrument Flask with OpenTelemetry
FlaskInstrumentor().instrument_app(app)

# Get tracer
tracer = trace.get_tracer(__name__)

@app.route('/')
def home():
    with tracer.start_as_current_span("home-request") as span:
        span.set_attribute("http.route", "/")
        span.set_attribute("custom.attribute", "home-page")
        
        logging.info("Home endpoint accessed")
        
        return jsonify({
            "message": "FluentBit Forward POC",
            "status": "running",
            "trace_id": format(span.get_span_context().trace_id, '032x'),
            "span_id": format(span.get_span_context().span_id, '016x')
        })

@app.route('/api/test')
def test_api():
    with tracer.start_as_current_span("test-api-request") as span:
        span.set_attribute("http.route", "/api/test")
        span.set_attribute("api.version", "v1")
        
        # Log with trace context
        logging.info("Test API endpoint called - processing request")
        
        # Simulate some processing with child span
        with tracer.start_as_current_span("process-data") as child_span:
            child_span.set_attribute("operation", "data-processing")
            logging.info("Processing data in child span")
            time.sleep(0.1)  # Simulate processing
            child_span.add_event("Data processing completed")
        
        logging.info("Test API request completed successfully")
        
        return jsonify({
            "status": "success",
            "message": "Test API endpoint",
            "trace_id": format(span.get_span_context().trace_id, '032x'),
            "span_id": format(span.get_span_context().span_id, '016x'),
            "timestamp": time.time()
        })

@app.route('/api/error')
def error_api():
    with tracer.start_as_current_span("error-api-request") as span:
        span.set_attribute("http.route", "/api/error")
        
        logging.error("Error endpoint called - simulating error condition")
        span.set_attribute("error", True)
        span.add_event("Error occurred")
        
        return jsonify({
            "status": "error",
            "message": "Simulated error",
            "trace_id": format(span.get_span_context().trace_id, '032x'),
            "span_id": format(span.get_span_context().span_id, '016x')
        }), 500

@app.route('/health')
def health():
    return jsonify({"status": "healthy"}), 200

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=5000, debug=False)
