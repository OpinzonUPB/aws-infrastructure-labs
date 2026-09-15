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
#   ./scripts/run_experiment.sh                    # usuarios y duración por defecto
#   ./scripts/run_experiment.sh "10 50"             # solo esos niveles de usuarios
#   ./scripts/run_experiment.sh "10 50" 15          # y 15s por prueba en vez de 30s

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
USERS_LIST="${1:-1 10 25 50 100}"
DURATION="${2:-15}"

# Configuraciones del laboratorio (ver README, sección "Configuraciones a probar").
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

  "$ROOT_DIR/scripts/start_container.sh" "$CPUS" "$MEMORY"

  for USERS in $USERS_LIST; do
    echo ""
    echo "------------------------------------------------------------------"
    echo "Configuración $LABEL ($CPUS CPU / $MEMORY RAM) -> $USERS usuarios"
    echo "------------------------------------------------------------------"
    "$ROOT_DIR/scripts/load_test.sh" "$USERS" "$DURATION" "/compute"
  done
done

"$ROOT_DIR/scripts/stop_container.sh"

echo ""
echo ">> Experimento completo. Revisa los resultados en results/results.csv"
