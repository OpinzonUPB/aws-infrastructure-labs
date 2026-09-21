#!/bin/bash
# User Data: se ejecuta UNA sola vez, como root, en el primer arranque de la instancia.
# Automatiza lo que en la Actividad 01 hicimos a mano.
set -euxo pipefail

REPO_URL="https://github.com/OpinzonUPB/aws-infrastructure-labs.git"
APP_DIR="/opt/aws-infrastructure-labs"

export HOME=/root
export DEBIAN_FRONTEND=noninteractive

# 1. Actualizar paquetes e instalar Git y Docker
apt-get update -y
apt-get install -y git docker.io
systemctl enable --now docker

# 2. Clonar el repositorio
git clone "$REPO_URL" "$APP_DIR"
cd "$APP_DIR"

# 3. Construir la imagen y ejecutar el contenedor
docker build -t sizing-app .
docker run -d --name sizing-app -p 8000:8000 sizing-app
