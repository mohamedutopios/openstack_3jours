#!/bin/bash
set -e

apt update -y
apt install -y docker.io docker-compose

mkdir -p /opt/kafka
cat > /opt/kafka/docker-compose.yml <<'EOF'
version: "3.8"
services:
  redpanda:
    image: redpandadata/redpanda:latest
    command: redpanda start --overprovisioned --smp 1 --reserve-memory 0M --node-id 0 --check=false
    ports:
      - "9092:9092"
      - "9644:9644"
    volumes:
      - /var/lib/redpanda:/var/lib/redpanda/data
    restart: unless-stopped
  console:
    image: redpandadata/console:latest
    environment:
      - KAFKA_BROKERS=redpanda:9092
    ports: ["8080:8080"]
    depends_on: [redpanda]
EOF

systemctl enable docker
systemctl start docker
docker compose -f /opt/kafka/docker-compose.yml up -d
