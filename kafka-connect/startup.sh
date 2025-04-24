#!/bin/bash

set -e

echo "⏳ Waiting for Kafka to be ready..."
until kafka-topics --bootstrap-server kafka:9092 --list &>/dev/null; do
  echo "⏱️  Kafka not ready yet, retrying in 5s..."
  sleep 5
done

echo "✅ Kafka is available. Creating internal Kafka Connect topics if needed..."

for topic in connect-offsets connect-configs connect-status; do
  kafka-topics --bootstrap-server kafka:9092 --describe --topic "$topic" &>/dev/null || {
    echo "🌀 Creating topic: $topic"
    kafka-topics --bootstrap-server kafka:9092 \
      --create --if-not-exists \
      --topic "$topic" \
      --replication-factor 1 \
      --partitions 1 \
      --config cleanup.policy=compact
  }
done

echo "🚀 Starting Kafka Connect..."
exec /etc/confluent/docker/run &

sleep 10
bash /etc/kafka-connect/launch-connector.sh

wait