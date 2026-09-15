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
NETWORK="sizing-net"

echo ">> Deteniendo contenedor previo (si existe)..."
docker rm -f "$NAME" >/dev/null 2>&1 || true

# Red dedicada para que el contenedor de k6 (en load_test.sh) pueda
# encontrar a sizing-app por nombre, en lugar de depender de
# --network host (que no funciona igual en Docker Desktop para
# Windows/macOS). Crearla es una operación idempotente.
docker network create "$NETWORK" >/dev/null 2>&1 || true

echo ">> Construyendo imagen $IMAGE..."
docker build -t "$IMAGE" "$ROOT_DIR"

echo ">> Iniciando contenedor:"
echo "     docker run -d --name $NAME --network $NETWORK --cpus=$CPUS --memory=$MEMORY -p 8000:8000 $IMAGE"
docker run -d \
  --name "$NAME" \
  --network "$NETWORK" \
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
