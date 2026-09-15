#!/usr/bin/env bash
# Ejecuta una prueba de carga contra el contenedor sizing-app y registra
# el resultado como una fila nueva en results/results.csv.
#
# Uso:
#   ./scripts/load_test.sh <usuarios_concurrentes> [duracion_segundos] [endpoint]
#
# Ejemplos:
#   ./scripts/load_test.sh 10
#   ./scripts/load_test.sh 25
#   ./scripts/load_test.sh 50 30 /compute
#
# Requiere que el contenedor ya esté corriendo, por ejemplo:
#   ./scripts/start_container.sh 1 512m

set -euo pipefail

USERS="${1:?Uso: ./scripts/load_test.sh <usuarios_concurrentes> [duracion_segundos] [endpoint]}"
DURATION="${2:-30}"
ENDPOINT="${3:-/compute}"

CONTAINER="sizing-app"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RESULTS_DIR="$ROOT_DIR/results"
RAW_DIR="$RESULTS_DIR/raw"
CSV="$RESULTS_DIR/results.csv"

mkdir -p "$RAW_DIR"

if ! docker inspect "$CONTAINER" >/dev/null 2>&1; then
  echo "ERROR: el contenedor '$CONTAINER' no existe todavía." >&2
  echo "Ejecuta primero: ./scripts/start_container.sh <cpus> <memoria>" >&2
  exit 1
fi

# 1. Leer los límites configurados en el contenedor, para dejarlos registrados
#    junto al resultado (así el CSV queda autocontenido).
CPU_NANO=$(docker inspect "$CONTAINER" --format '{{.HostConfig.NanoCpus}}')
if [ "$CPU_NANO" = "0" ]; then
  CPU_LIMIT="sin_limite"
else
  CPU_LIMIT=$(awk "BEGIN { printf \"%.2f\", $CPU_NANO/1000000000 }")
fi

MEM_BYTES=$(docker inspect "$CONTAINER" --format '{{.HostConfig.Memory}}')
if [ "$MEM_BYTES" = "0" ]; then
  MEM_LIMIT_MB="sin_limite"
else
  MEM_LIMIT_MB=$(( MEM_BYTES / 1024 / 1024 ))
fi

echo "=================================================================="
echo " Prueba de carga"
echo "   Contenedor       : $CONTAINER"
echo "   CPU asignada     : $CPU_LIMIT"
echo "   Memoria asignada : ${MEM_LIMIT_MB} MB"
echo "   Usuarios (VUs)   : $USERS"
echo "   Duración         : ${DURATION}s"
echo "   Endpoint         : $ENDPOINT"
echo "=================================================================="

# 2. Muestrear docker stats una vez por segundo mientras dura la prueba,
#    en segundo plano.
STATS_FILE=$(mktemp)
(
  while true; do
    docker stats "$CONTAINER" --no-stream --format '{{.CPUPerc}},{{.MemUsage}}' >> "$STATS_FILE" 2>/dev/null || true
    sleep 1
  done
) &
STATS_PID=$!
trap 'kill "$STATS_PID" 2>/dev/null || true' EXIT

# 3. Ejecutar k6 dentro de un contenedor Docker (imagen oficial grafana/k6),
#    así no hace falta instalar nada más en Codespaces ni en EC2.
#    Se conecta a la misma red "sizing-net" que start_container.sh, y
#    llega a la app por su nombre de contenedor (sizing-app), en lugar de
#    usar --network host (que no funciona igual en Docker Desktop para
#    Windows/macOS y no es necesario en Linux si ya existe la red).
NETWORK="sizing-net"
TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
RUN_ID="${USERS}users_$(date +%s)"
SUMMARY_FILENAME="k6_${RUN_ID}_summary.json"

echo ">> Ejecutando k6 (docker run grafana/k6)..."
# MSYS_NO_PATHCONV=1 solo para este comando: evita que Git Bash en Windows
# "traduzca" por error las rutas destinadas al interior del contenedor
# (p. ej. /scripts/script.js) a rutas del sistema de archivos de Windows.
# En Linux (Codespaces/EC2) esta variable no tiene ningún efecto.
MSYS_NO_PATHCONV=1 docker run --rm --network "$NETWORK" \
  -e BASE_URL="http://sizing-app:8000${ENDPOINT}" \
  -v "$ROOT_DIR/loadtest:/scripts:ro" \
  -v "$RAW_DIR:/out" \
  grafana/k6 run \
    --vus "$USERS" \
    --duration "${DURATION}s" \
    --summary-export "/out/${SUMMARY_FILENAME}" \
    /scripts/script.js

# 4. Detener el muestreo de docker stats.
kill "$STATS_PID" 2>/dev/null || true
wait "$STATS_PID" 2>/dev/null || true
trap - EXIT

# 5. Registrar el resultado combinado en results/results.csv.
python3 "$ROOT_DIR/scripts/record_result.py" \
  --k6-summary "$RAW_DIR/${SUMMARY_FILENAME}" \
  --stats-file "$STATS_FILE" \
  --cpu-limit "$CPU_LIMIT" \
  --memory-limit-mb "$MEM_LIMIT_MB" \
  --concurrent-users "$USERS" \
  --timestamp "$TIMESTAMP" \
  --csv "$CSV"

rm -f "$STATS_FILE"
