"""
Aplicación de ejemplo para el laboratorio de dimensionamiento de contenedores.

Expone tres endpoints con perfiles de consumo muy distintos a propósito:

- /health   -> prácticamente no consume nada. Sirve para comprobar que el
              contenedor está vivo, incluso bajo carga.
- /compute  -> consume CPU de forma intencionalmente ineficiente, para que
              el efecto de --cpus sea fácil de observar en docker stats.
- /memory   -> reserva una cantidad de memoria controlada durante unos
              segundos, para que el efecto de --memory sea observable.

No hay base de datos ni llamadas externas: todo el consumo ocurre dentro
del propio proceso de Python.
"""

import gc
import time

from fastapi import FastAPI

app = FastAPI(title="sizing-app")

# Límite de seguridad: por muy alto que sea el valor que pida un estudiante,
# nunca reservamos más de esto en una sola llamada. Así, aunque el
# contenedor tenga un límite de memoria bajo (ej. 256 MB) y el estudiante
# pida más de lo que cabe, lo único que puede pasar es que el propio
# contenedor sea terminado por el OOM killer de Docker -- no el host.
MAX_MEMORY_MB = 512
MAX_HOLD_SECONDS = 30.0


@app.get("/health")
def health():
    """Respuesta inmediata, sin cómputo. Sirve como línea base de referencia."""
    return {"status": "ok"}


def _is_prime(number: int) -> bool:
    if number < 2:
        return False
    limit = int(number ** 0.5) + 1
    for divisor in range(2, limit):
        if number % divisor == 0:
            return False
    return True


def _count_primes(upper_bound: int) -> int:
    # Implementación deliberadamente simple (fuerza bruta), no optimizada.
    # El objetivo pedagógico es generar carga de CPU real y predecible,
    # no calcular primos de la forma más rápida posible.
    count = 0
    for number in range(2, upper_bound):
        if _is_prime(number):
            count += 1
    return count


@app.get("/compute")
def compute(n: int = 100000):
    """
    Cuenta cuántos números primos hay por debajo de `n`.

    El valor por defecto (n=100000) está pensado para que una sola llamada
    tome un tiempo perceptible (decenas a cientos de milisegundos), pero
    el tiempo real depende del hardware donde corra el contenedor. Puedes
    ajustarlo con ?n=, por ejemplo /compute?n=200000 para generar más carga.
    """
    start = time.perf_counter()
    primes_found = _count_primes(n)
    elapsed_ms = (time.perf_counter() - start) * 1000

    return {
        "n": n,
        "primes_found": primes_found,
        "elapsed_ms": round(elapsed_ms, 2),
    }


@app.get("/memory")
def memory(mb: int = 50, hold_seconds: float = 5.0):
    """
    Reserva `mb` megabytes de memoria durante `hold_seconds` segundos y
    luego los libera.

    Se "tocan" todas las páginas de memoria reservada (se escribe en cada
    bloque de 4 KB) para forzar que el sistema operativo la asigne de
    verdad, y no de forma perezosa. Así lo que ves en `docker stats`
    refleja memoria realmente usada, no solo reservada.
    """
    requested_mb = mb
    clamped = False
    if mb > MAX_MEMORY_MB:
        mb = MAX_MEMORY_MB
        clamped = True

    hold_seconds = min(max(hold_seconds, 0.0), MAX_HOLD_SECONDS)

    block = bytearray(mb * 1024 * 1024)
    page_size = 4096
    for offset in range(0, len(block), page_size):
        block[offset] = 1

    time.sleep(hold_seconds)

    allocated_bytes = len(block)
    del block
    gc.collect()

    return {
        "requested_mb": requested_mb,
        "allocated_mb": mb,
        "clamped_to_max": clamped,
        "held_seconds": hold_seconds,
        "allocated_bytes": allocated_bytes,
    }
