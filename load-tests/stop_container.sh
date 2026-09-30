#!/usr/bin/env bash
# Detiene y elimina el contenedor sizing-app, si existe.
set -euo pipefail

if docker rm -f sizing-app >/dev/null 2>&1; then
  echo ">> Contenedor sizing-app detenido y eliminado."
else
  echo ">> No había un contenedor sizing-app en ejecución."
fi
