#!/bin/bash

# Quick setup script for FluentBit Forward POC

set -e

echo "======================================"
echo "FluentBit Forward POC - Setup"
echo "======================================"
echo ""

# Make scripts executable
echo "Making scripts executable..."
chmod +x test-api.sh check-vector-logs.sh setup.sh

# Check Docker
echo "Checking Docker..."
if ! command -v docker &> /dev/null; then
    echo "ERROR: Docker is not installed!"
    exit 1
fi

if ! command -v docker-compose &> /dev/null; then
    echo "ERROR: Docker Compose is not installed!"
    exit 1
fi

echo "✓ Docker and Docker Compose are available"
echo ""

# Build and start services
echo "Building and starting services..."
docker-compose down -v 2>/dev/null || true
docker-compose up -d --build

echo ""
echo "Waiting for services to be healthy..."
sleep 5

# Check service health
echo ""
echo "Checking service health..."
services=("app" "fluentbit-1" "fluentbit-2" "vector")
all_healthy=true

for service in "${services[@]}"; do
    if docker ps | grep -q "$service"; then
        echo "✓ $service is running"
    else
        echo "✗ $service is not running"
        all_healthy=false
    fi
done

echo ""
if [ "$all_healthy" = true ]; then
    echo "======================================"
    echo "Setup Complete! ✓"
    echo "======================================"
    echo ""
    echo "Services are running:"
    echo "  - Python App: http://localhost:5000"
    echo "  - FluentBit #1: http://localhost:2020"
    echo "  - FluentBit #2: http://localhost:2021"
    echo "  - Vector: http://localhost:8687"
    echo ""
    echo "Next steps:"
    echo "  1. Run: ./test-api.sh"
    echo "  2. Check logs: ./check-vector-logs.sh"
    echo "  3. View live logs: docker-compose logs -f"
    echo ""
else
    echo "======================================"
    echo "Setup encountered issues"
    echo "======================================"
    echo ""
    echo "Check logs with: docker-compose logs"
    exit 1
fi
