#!/bin/bash

# Test script to call the application APIs and verify trace_id/span_id

echo "======================================"
echo "FluentBit Forward POC - API Test Script"
echo "======================================"
echo ""

APP_URL=${APP_URL:-"http://localhost:5000"}

echo "Testing API endpoints at: $APP_URL"
echo ""

# Test 1: Home endpoint
echo "1. Testing Home Endpoint (GET /)"
echo "--------------------------------------"
curl -s "$APP_URL/" | jq '.'
echo ""
sleep 1

# Test 2: Test API endpoint
echo "2. Testing Test API Endpoint (GET /api/test)"
echo "--------------------------------------"
curl -s "$APP_URL/api/test" | jq '.'
echo ""
sleep 1

# Test 3: Error endpoint
echo "3. Testing Error Endpoint (GET /api/error)"
echo "--------------------------------------"
curl -s "$APP_URL/api/error" | jq '.'
echo ""
sleep 1

# Test 4: Multiple requests
echo "4. Sending Multiple Requests"
echo "--------------------------------------"
for i in {1..3}; do
  echo "Request #$i:"
  curl -s "$APP_URL/api/test" | jq '.trace_id, .span_id'
  sleep 0.5
done
echo ""

echo "======================================"
echo "Test Complete!"
echo "======================================"
echo ""
echo "Next steps:"
echo "1. Check Vector logs for trace_id and span_id"
echo "2. Run: docker exec vector cat /var/log/vector/output-$(date +%Y-%m-%d).log | jq '.'"
echo ""
