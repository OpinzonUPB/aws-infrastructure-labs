#!/usr/bin/env bash
# Reconstruye la imagen y arranca el contenedor sizing-app con un límite
# explícito de CPU y de memoria.
#
# Uso:
#   ./scripts/start_container.sh <cpus> <memoria>
#
# Ejemplos:
#   ./scripts/start_container.sh 0.5 256m
#   ./scripts/start_container.sh 1   512m
#   ./scripts/start_container.sh 2   2g

set -euo pipefail

CPUS="${1:?Uso: ./scripts/start_container.sh <cpus> <memoria>   (ej: 1 512m)}"
MEMORY="${2:?Uso: ./scripts/start_container.sh <cpus> <memoria>   (ej: 1 512m)}"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
NAME="sizing-app"
IMAGE="sizing-app"

echo ">> Deteniendo contenedor previo (si existe)..."
docker rm -f "$NAME" >/dev/null 2>&1 || true

echo ">> Construyendo imagen $IMAGE..."
docker build -t "$IMAGE" "$ROOT_DIR"

echo ">> Iniciando contenedor:"
echo "     docker run -d --name $NAME --cpus=$CPUS --memory=$MEMORY -p 8000:8000 $IMAGE"
docker run -d \
  --name "$NAME" \
  --cpus="$CPUS" \
  --memory="$MEMORY" \
  -p 8000:8000 \
  "$IMAGE"

echo ">> Esperando a que /health responda..."
for i in $(seq 1 30); do
  if curl -sf http://localhost:8000/health >/dev/null 2>&1; then
    echo ">> Listo. La aplicación responde en http://localhost:8000"
    exit 0
  fi
  sleep 0.5
done

echo "ERROR: la aplicación no respondió después de ~15 segundos." >&2
echo "Revisa los logs con: docker logs $NAME" >&2
exit 1
