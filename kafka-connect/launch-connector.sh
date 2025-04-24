#!/bin/bash

set -e

echo "⏳ Waiting for Kafka Connect REST API..."

until curl -s http://kafka-connect:8083/connectors &>/dev/null; do
  echo "⌛ Kafka Connect not ready, retrying in 10s..."
  sleep 10
done

echo "🚀 Registering Aiven JDBC Source Connector..."

curl -s -X POST http://kafka-connect:8083/connectors \
  -H "Content-Type: application/json" \
  --data @/etc/kafka-connect/connectors/cdc-timescale-connector.json

echo "✅ Connector registered."