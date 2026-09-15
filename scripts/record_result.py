#!/usr/bin/env python3
"""
Combina el resumen JSON exportado por k6 con las muestras de `docker stats`
tomadas durante la prueba, y agrega una fila a results/results.csv.

Se usa Python puro (sin dependencias adicionales) para no exigir jq ni
otras herramientas: solo lo que ya necesita el laboratorio.
"""

import argparse
import csv
import json
import os
import re

CSV_COLUMNS = [
    "timestamp",
    "cpu_limit",
    "memory_limit",
    "concurrent_users",
    "cpu_percent",
    "memory_usage_mb",
    "requests_per_second",
    "avg_latency_ms",
    "p95_latency_ms",
    "error_percent",
]


def parse_mem_usage(value: str) -> float:
    """Convierte '128.5MiB', '1.2GiB', etc. a megabytes (float)."""
    match = re.match(r"([\d.]+)\s*([KMG]i?B)", value.strip())
    if not match:
        return 0.0
    number, unit = match.groups()
    number = float(number)
    unit = unit.upper()
    if unit in ("KB", "KIB"):
        return number / 1024
    if unit in ("MB", "MIB"):
        return number
    if unit in ("GB", "GIB"):
        return number * 1024
    return number


def read_stats(stats_file: str):
    """
    Lee las líneas 'cpu%,mem_usage / mem_limit' generadas por:
      docker stats <contenedor> --no-stream --format '{{.CPUPerc}},{{.MemUsage}}'
    y devuelve las listas de valores de CPU (%) y memoria (MB) observados.
    """
    cpu_values = []
    mem_values = []
    if not os.path.exists(stats_file):
        return cpu_values, mem_values

    with open(stats_file, "r") as f:
        for line in f:
            line = line.strip()
            if not line or "," not in line:
                continue
            cpu_raw, mem_raw = line.split(",", 1)
            try:
                cpu_values.append(float(cpu_raw.replace("%", "").strip()))
            except ValueError:
                pass
            mem_usage_part = mem_raw.split("/")[0].strip()
            mem_values.append(parse_mem_usage(mem_usage_part))

    return cpu_values, mem_values


def read_k6_summary(summary_path: str):
    """
    Lee el JSON que produce `k6 run --summary-export=archivo.json`.

    En k6 (probado con v2.2.0), cada métrica es un objeto plano, sin un
    nivel "values" intermedio:
      - Métricas tipo contador/tendencia (http_reqs, http_req_duration):
        {"count": ..., "rate": ...} o {"avg": ..., "p(95)": ..., ...}
      - Métricas tipo "rate" (http_req_failed): {"passes", "fails", "value"}
        donde "value" es la fracción (0..1) de peticiones fallidas.
    """
    with open(summary_path, "r") as f:
        data = json.load(f)
    metrics = data.get("metrics", {})

    def get(metric_name, field, default=0.0):
        return metrics.get(metric_name, {}).get(field, default)

    requests_per_second = get("http_reqs", "rate", 0.0)
    avg_latency_ms = get("http_req_duration", "avg", 0.0)
    p95_latency_ms = get("http_req_duration", "p(95)", 0.0)
    error_rate = get("http_req_failed", "value", 0.0) * 100

    return {
        "requests_per_second": round(requests_per_second, 2),
        "avg_latency_ms": round(avg_latency_ms, 2),
        "p95_latency_ms": round(p95_latency_ms, 2),
        "error_percent": round(error_rate, 2),
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--k6-summary", required=True, help="Ruta al JSON exportado por k6 (--summary-export)")
    parser.add_argument("--stats-file", required=True, help="Archivo con las muestras de docker stats")
    parser.add_argument("--cpu-limit", required=True)
    parser.add_argument("--memory-limit-mb", required=True)
    parser.add_argument("--concurrent-users", required=True)
    parser.add_argument("--timestamp", required=True)
    parser.add_argument("--csv", required=True)
    args = parser.parse_args()

    k6_metrics = read_k6_summary(args.k6_summary)
    cpu_values, mem_values = read_stats(args.stats_file)

    # Usamos el máximo observado durante la prueba (no el promedio), porque
    # lo que interesa para dimensionar es el pico de uso, no un promedio
    # que puede esconder momentos de saturación.
    cpu_percent_max = round(max(cpu_values), 2) if cpu_values else ""
    memory_usage_mb_max = round(max(mem_values), 2) if mem_values else ""

    row = {
        "timestamp": args.timestamp,
        "cpu_limit": args.cpu_limit,
        "memory_limit": args.memory_limit_mb,
        "concurrent_users": args.concurrent_users,
        "cpu_percent": cpu_percent_max,
        "memory_usage_mb": memory_usage_mb_max,
        "requests_per_second": k6_metrics["requests_per_second"],
        "avg_latency_ms": k6_metrics["avg_latency_ms"],
        "p95_latency_ms": k6_metrics["p95_latency_ms"],
        "error_percent": k6_metrics["error_percent"],
    }

    file_exists = os.path.exists(args.csv)
    needs_header = (not file_exists) or os.path.getsize(args.csv) == 0

    with open(args.csv, "a", newline="") as f:
        writer = csv.DictWriter(f, fieldnames=CSV_COLUMNS)
        if needs_header:
            writer.writeheader()
        writer.writerow(row)

    print(f">> Resultado registrado en {args.csv}")
    for key in CSV_COLUMNS:
        print(f"   {key}: {row[key]}")


if __name__ == "__main__":
    main()
