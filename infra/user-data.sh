#!/bin/bash
# User Data: se ejecuta UNA sola vez, como root, en el primer arranque de la instancia.
# Automatiza lo que en la Actividad 01 hicimos a mano.
# El registro completo queda en /var/log/cloud-init-output.log
set -euxo pipefail

REPO_URL="https://github.com/OpinzonUPB/aws-infrastructure-labs.git"
APP_DIR="/opt/aws-infrastructure-labs"

export HOME=/root
export DEBIAN_FRONTEND=noninteractive

# En el primer arranque, Ubuntu puede estar actualizando paquetes en segundo
# plano (unattended-upgrades). En vez de fallar porque apt está ocupado,
# esperamos hasta 5 minutos a que se libere.
APT_WAIT="-o DPkg::Lock::Timeout=300"

# 1. Actualizar paquetes e instalar Git y Docker
apt-get $APT_WAIT update -y
apt-get $APT_WAIT install -y git docker.io
systemctl enable --now docker

# 2. Clonar el repositorio
git clone "$REPO_URL" "$APP_DIR"
cd "$APP_DIR"

# 3. Construir la imagen y ejecutar el contenedor.
#    --restart unless-stopped: Docker vuelve a arrancar el contenedor si la
#    instancia se reinicia (este script NO se vuelve a ejecutar).
docker build -t sizing-app .
docker run -d --name sizing-app --restart unless-stopped -p 8000:8000 sizing-app

echo "User Data terminado: la aplicación responde en el puerto 8000"
