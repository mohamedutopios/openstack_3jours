#!/bin/bash
set -eux

# Mettre à jour le système
apt-get update -y
apt-get upgrade -y

# Installer Docker et Docker Compose
apt-get install -y docker.io docker-compose

# Activer et démarrer Docker
systemctl enable docker
systemctl start docker

# Créer le répertoire pour Spark
mkdir -p /opt/spark

# Définir le docker-compose Spark
cat > /opt/spark/docker-compose.yml <<'EOF'
version: "3.8"
services:
  spark-master:
    image: bitnami/spark:3.5
    environment:
      - SPARK_MODE=master
    ports:
      - "7077:7077"
      - "8080:8080"

  spark-worker:
    image: bitnami/spark:3.5
    environment:
      - SPARK_MODE=worker
      - SPARK_MASTER_URL=spark://spark-master:7077
    depends_on:
      - spark-master
    ports:
      - "8081:8081"
EOF

# Lancer Spark avec Docker Compose
docker compose -f /opt/spark/docker-compose.yml up -d
