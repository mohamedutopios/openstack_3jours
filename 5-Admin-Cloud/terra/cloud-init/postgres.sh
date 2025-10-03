#!/bin/bash
set -eux

# Mettre à jour les paquets
apt-get update -y
apt-get upgrade -y

# Installer Docker et Docker Compose
apt-get install -y docker.io docker-compose

# Démarrer et activer Docker
systemctl enable docker
systemctl start docker

# Créer le dossier de déploiement
mkdir -p /opt/postgres

# Définir le docker-compose
cat > /opt/postgres/docker-compose.yml <<'EOF'
version: "3.8"
services:
  postgres:
    image: postgres:15
    environment:
      POSTGRES_USER: spark
      POSTGRES_PASSWORD: sparkpass
      POSTGRES_DB: pipeline
    ports:
      - "5432:5432"
    volumes:
      - /var/lib/postgresql/data:/var/lib/postgresql/data
    restart: unless-stopped
EOF

# Lancer Postgres
docker compose -f /opt/postgres/docker-compose.yml up -d
