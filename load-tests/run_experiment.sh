#!/usr/bin/env bash
# Recorre las 4 configuraciones de CPU/RAM del laboratorio (A, B, C, D) y,
# para cada una, ejecuta pruebas de carga con distintos niveles de usuarios
# concurrentes.
#
# Este script NO oculta nada: solo llama, en el mismo orden en que lo
# harías a mano, a start_container.sh y load_test.sh. Cada paso se anuncia
# por pantalla antes de ejecutarse.
#
# Uso:
#   ./load-tests/run_experiment.sh                    # usuarios y duración por defecto
#   ./load-tests/run_experiment.sh "10 50"             # solo esos niveles de usuarios
#   ./load-tests/run_experiment.sh "10 50" 15          # y 15s por prueba en vez de 30s

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
USERS_LIST="${1:-1 10 25 50 100}"
DURATION="${2:-15}"

# Configuraciones del laboratorio (ver actividades/06-dimensionamiento/README.md).
CONFIGS=(
  "A 0.5 256m"
  "B 1 512m"
  "C 1 1g"
  "D 2 2g"
)

for CONFIG in "${CONFIGS[@]}"; do
  read -r LABEL CPUS MEMORY <<< "$CONFIG"

  echo ""
  echo "##################################################################"
  echo "# Configuración $LABEL: $CPUS CPU / $MEMORY RAM"
  echo "##################################################################"

  "$ROOT_DIR/load-tests/start_container.sh" "$CPUS" "$MEMORY"

  for USERS in $USERS_LIST; do
    echo ""
    echo "------------------------------------------------------------------"
    echo "Configuración $LABEL ($CPUS CPU / $MEMORY RAM) -> $USERS usuarios"
    echo "------------------------------------------------------------------"
    "$ROOT_DIR/load-tests/load_test.sh" "$USERS" "$DURATION" "/compute"
  done
done

"$ROOT_DIR/load-tests/stop_container.sh"

echo ""
echo ">> Experimento completo. Revisa los resultados en load-tests/results/results.csv"
