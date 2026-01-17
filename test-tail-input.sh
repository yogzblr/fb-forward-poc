#!/bin/bash
# Script to create test log file for tail input
echo '{"message":"test tail input 1","timestamp":"2026-01-16T19:30:00Z","level":"info"}' > /tmp/test-tail.log
echo '{"message":"test tail input 2","timestamp":"2026-01-16T19:31:00Z","level":"info"}' >> /tmp/test-tail.log
cat /tmp/test-tail.log
