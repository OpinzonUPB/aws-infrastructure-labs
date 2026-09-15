# Laboratorio: dimensionamiento de CPU y memoria de una aplicación contenerizada

Este laboratorio complementa el Módulo 6 (Cómputo) del curso: Amazon EC2, optimización
de costos (en particular el **Pilar 1: dimensionamiento adecuado**) y contenedores.

**Pregunta que vas a responder:** si tuvieras que llevar esta aplicación a una VPS o a
una instancia EC2, ¿cuántas vCPU y cuánta RAM necesitarías? Al empezar, **no lo sabes**.
Al terminar, lo vas a saber porque lo mediste tú mismo/a.

Proceso que vas a seguir:

```
Aplicación → Docker → prueba de carga → medición de CPU/RAM → límites de recursos
           → análisis → propuesta de dimensionamiento
```

---

## Inicio rápido en GitHub Codespaces

1. En GitHub, abre este repositorio.
2. Haz clic en **Code → Codespaces → Create codespace on main**.
3. Espera a que termine de construirse el entorno (instala Python y habilita Docker
   dentro del Codespace). La primera vez puede tardar 1-2 minutos.
4. Abre una terminal (`Ctrl+ñ` / `Ctrl+backtick`) y construye la imagen:

   ```bash
   docker build -t sizing-app .
   ```

5. Ejecuta el contenedor:

   ```bash
   docker run -d --name sizing-app -p 8000:8000 sizing-app
   ```

6. Comprueba que responde:

   ```bash
   curl http://localhost:8000/health
   ```

   Deberías ver `{"status":"ok"}`. Si Codespaces te muestra una notificación de
   "puerto 8000 disponible", también puedes abrirlo en el navegador (aunque para este
   laboratorio usaremos casi todo por línea de comandos, ya que `docker stats` y `k6`
   son herramientas de terminal).

Si esto funcionó, ya tienes lo mínimo para empezar la Etapa 1. El resto de las etapas
usan los scripts de `scripts/` en lugar de estos comandos manuales.

> **Nota:** este mismo proyecto puede ejecutarse después en una instancia Ubuntu de
> AWS EC2. Ver la sección [Ejecutar en una instancia EC2](#ejecutar-en-una-instancia-ec2-opcional)
> al final de este documento.

---

## La aplicación

`app/main.py` expone tres endpoints con perfiles de consumo muy distintos:

| Endpoint    | Qué hace                                                              |
|-------------|------------------------------------------------------------------------|
| `GET /health`  | Responde de inmediato. Consumo mínimo. Sirve como línea base.       |
| `GET /compute` | Cuenta números primos por fuerza bruta hasta `n` (por defecto 100000). Consume CPU de forma intencional e ineficiente. |
| `GET /memory`  | Reserva `mb` megabytes de memoria (por defecto 50) durante `hold_seconds` segundos (por defecto 5) y luego los libera. |

No hay base de datos ni servicios externos: todo el consumo de recursos ocurre dentro
del propio proceso de Python, para que lo que midas refleje solo a la aplicación y al
límite que le pusiste al contenedor.

---

## Configuraciones que vas a probar

A lo largo del laboratorio vas a repetir el mismo experimento variando cuánta CPU y
memoria le das al contenedor:

| Config | CPU   | RAM    |
|--------|-------|--------|
| A      | 0.5   | 256 MB |
| B      | 1     | 512 MB |
| C      | 1     | 1 GB   |
| D      | 2     | 2 GB   |

Y, para cada configuración, distintos niveles de carga concurrente: **1, 10, 25, 50 y
100 usuarios**.

---

## Etapas del laboratorio

En cada etapa: **objetivo**, **comando**, **qué observar** y una o dos **preguntas**.
Las preguntas no tienen una respuesta única correcta — se responden con lo que tú
mediste, no con lo que "debería" pasar.

### Etapa 1 — Comprender la aplicación

**Objetivo:** entender qué hace cada endpoint antes de medir nada.

Abre `app/main.py` y lee las funciones `health`, `compute` y `memory`.

**Preguntas:**
- ¿Por qué `/compute` usa un algoritmo de fuerza bruta en lugar de uno optimizado?
- ¿Por qué `/memory` "toca" cada página de memoria (`block[offset] = 1`) en lugar de
  solo reservar el espacio con `bytearray(...)`?

### Etapa 2 — Construir la imagen

**Objetivo:** empaquetar la aplicación en una imagen Docker.

```bash
docker build -t sizing-app .
```

**Qué observar:** el tamaño final de la imagen (`docker images sizing-app`) y cuánto
tarda la construcción.

**Pregunta:**
- ¿Por qué el `Dockerfile` copia primero `requirements.txt` e instala las
  dependencias, y solo después copia el código de `app/`?

### Etapa 3 — Ejecutar el contenedor (sin límites)

**Objetivo:** confirmar que la aplicación funciona antes de empezar a limitarla.

```bash
docker run -d --name sizing-app -p 8000:8000 sizing-app
curl http://localhost:8000/health
curl http://localhost:8000/compute
```

**Qué observar:** el campo `elapsed_ms` que devuelve `/compute`.

**Pregunta:**
- Sin ningún límite de CPU o memoria, ¿cuánto tarda una sola llamada a `/compute`?

Cuando termines esta etapa, elimina el contenedor de prueba:

```bash
./scripts/stop_container.sh
```

### Etapa 4 — Medir en reposo

**Objetivo:** aprender a leer `docker stats` antes de meter carga.

```bash
./scripts/start_container.sh 1 512m
docker stats sizing-app
```

**Qué observar:**
- **CPU %**: en `docker stats`, **100% ≈ un núcleo lógico completo**. Si ves 200%,
  el contenedor está usando el equivalente a dos núcleos. Estos porcentajes son
  orientativos y dependen de la máquina donde corras el laboratorio (Codespaces y
  EC2 pueden dar números distintos para el mismo experimento).
- **MEM USAGE / LIMIT**: memoria usada frente al límite que le pusiste al contenedor.
- **NET I/O**: tráfico de red entrante/saliente.

Sal de `docker stats` con `Ctrl+C` (no detiene el contenedor, solo el monitor).

**Pregunta:**
- Con el contenedor en reposo (sin recibir peticiones), ¿cuánta CPU y memoria está
  usando? ¿Es lo que esperabas?

### Etapa 5 — Generar carga

**Objetivo:** ejecutar tu primera prueba de carga real.

```bash
./scripts/load_test.sh 10
```

Esto lanza k6 (en un contenedor Docker aparte, sin necesidad de instalar nada) contra
`/compute` durante 30 segundos con 10 usuarios virtuales concurrentes, mientras
muestrea `docker stats` en segundo plano, y agrega una fila a `results/results.csv`.

**Qué observar:** al terminar, el script imprime `requests_per_second`,
`avg_latency_ms`, `p95_latency_ms`, `error_percent`, y el máximo de CPU/memoria
observado durante la prueba.

**Preguntas:**
- ¿Qué significa `p95_latency_ms`? ¿Por qué el laboratorio usa el percentil 95 y no
  solo el promedio?
- Con 10 usuarios, ¿el contenedor (1 CPU / 512 MB) llegó a saturarse?

### Etapa 6 — Limitar CPU y memoria

**Objetivo:** repetir el experimento con menos recursos y ver qué cambia.

```bash
./scripts/start_container.sh 0.5 256m
./scripts/load_test.sh 10
```

`start_container.sh` reconstruye la imagen y reinicia el contenedor con los límites
que le indiques (usa `docker run --cpus=... --memory=...` por debajo).

**Qué observar:** compara `p95_latency_ms` y `error_percent` de esta corrida contra la
de la Etapa 5.

**Pregunta:**
- ¿Qué pasó con la latencia al reducir la CPU disponible a la mitad?

### Etapa 7 — Repetir pruebas

**Objetivo:** cubrir toda la matriz de configuraciones (A-D) y niveles de usuarios
(1, 10, 25, 50, 100).

Puedes hacerlo manualmente, combinando `start_container.sh` y `load_test.sh`:

```bash
./scripts/start_container.sh 1 1g
./scripts/load_test.sh 1
./scripts/load_test.sh 10
./scripts/load_test.sh 25
./scripts/load_test.sh 50
./scripts/load_test.sh 100
```

O usar el script que automatiza la matriz completa (sin ocultar los comandos: los
verás impresos en pantalla a medida que se ejecutan):

```bash
./scripts/run_experiment.sh
```

Por defecto prueba las 4 configuraciones × 5 niveles de usuarios con 15 segundos por
prueba (20 corridas en total). Puedes ajustar qué niveles de usuarios y cuánto dura
cada prueba:

```bash
./scripts/run_experiment.sh "10 50" 20
```

**Qué observar:** cómo van llenándose las filas de `results/results.csv`.

**Pregunta:**
- ¿En qué configuración empezaste a ver `error_percent > 0`? ¿Qué usuarios
  concurrentes lo provocaron?

### Etapa 8 — Registrar resultados

**Objetivo:** tener toda la evidencia en un solo lugar.

Cada corrida de `load_test.sh` (manual o desde `run_experiment.sh`) agrega
automáticamente una fila a `results/results.csv` con estas columnas:

```
timestamp, cpu_limit, memory_limit, concurrent_users,
cpu_percent, memory_usage_mb,
requests_per_second, avg_latency_ms, p95_latency_ms, error_percent
```

`cpu_percent` y `memory_usage_mb` son los **valores máximos** observados durante la
prueba (el pico, no el promedio), porque para dimensionar importa el peor momento, no
el comportamiento típico.

Además, en `results/raw/` quedan los JSON crudos que exporta k6, por si quieres
revisar una corrida con más detalle.

**Si algo no se pudo registrar automáticamente** (por ejemplo, si el contenedor murió
a mitad de la prueba por falta de memoria y `docker stats` no alcanzó a tomar
muestras), anota manualmente en el CSV lo que sí puedas observar: al menos
`timestamp`, `cpu_limit`, `memory_limit`, `concurrent_users`, y una nota de que el
contenedor fue terminado (puedes usarlo como evidencia de que esa configuración *no*
es suficiente).

### Etapa 9 — Identificar el cuello de botella

**Objetivo:** interpretar los datos, no solo recolectarlos.

Abre `results/results.csv` (en Codespaces puedes usar la vista de tabla del editor, o
copiarlo a una hoja de cálculo).

**Preguntas:**
- Para una misma configuración, ¿qué subió más rápido al aumentar los usuarios:
  `cpu_percent` o `memory_usage_mb`? ¿Qué te dice eso sobre si esta aplicación está
  limitada por CPU o por memoria?
- ¿En qué punto aumentar recursos (por ejemplo, pasar de B a C, o de C a D) dejó de
  mejorar significativamente `p95_latency_ms`? ¿Qué explicación tiene eso?

### Etapa 10 — Proponer el dimensionamiento

**Objetivo:** tomar una decisión, con criterios explícitos.

El objetivo **no** es encontrar la configuración más potente. Es encontrar la
**configuración mínima que cumple** unos criterios de servicio.

Criterios didácticos de este laboratorio (no son reglas universales de producción,
son los que usamos aquí para poder comparar de forma objetiva):

```
errores < 1%
p95 < 500 ms
sin saturación sostenida de CPU (cpu_percent no permanece pegado al límite)
memoria utilizada < 80% del límite del contenedor
```

Con base en `results/results.csv`, completa esta conclusión para una carga objetivo de
**50 usuarios concurrentes**:

```
Carga objetivo: 50 usuarios concurrentes

Configuración mínima que cumple:
CPU: ...
RAM: ...

p95 obtenido: ...
errores: ...
CPU máxima observada: ...
RAM máxima observada: ...

Dimensionamiento recomendado:
... vCPU
... GB RAM
```

**Preguntas:**
- ¿Cuál fue la configuración mínima que cumplió los cuatro criterios a la vez?
- ¿Qué configuración habrías elegido si solo te hubieras fijado en la latencia
  promedio en lugar del p95? ¿Habría sido un error, y por qué?

### Etapa 11 — Relacionarlo con una VPS o EC2

**Objetivo:** traducir tu conclusión a una decisión de infraestructura real.

Con el "Dimensionamiento recomendado" de la Etapa 10, busca:

- En la [documentación de tipos de instancia de Amazon EC2](https://docs.aws.amazon.com/ec2/),
  qué tipo de instancia (familia y tamaño) ofrece esa combinación de vCPU y RAM.
- En un proveedor de VPS alterno (por ejemplo, el que estés usando en clase), qué plan
  ofrece una combinación equivalente.

**Preguntas:**
- ¿El tipo de instancia EC2 que encontraste da *exactamente* lo que necesitas, o te
  obliga a sobredimensionar (llevarte más CPU o RAM de la que pediste) porque los
  tamaños vienen en pasos fijos?
- Si esta aplicación tuviera picos de tráfico impredecibles en lugar de una carga
  constante, ¿seguiría teniendo sentido reservar de forma fija el dimensionamiento que
  calculaste, o considerarías otro modelo (auto scaling, spot, serverless)? Relaciona
  tu respuesta con los cuatro pilares de optimización de costos vistos en el módulo.

---

## Ejecutar en una instancia EC2 (opcional)

Este mismo laboratorio corre igual en una instancia Ubuntu de EC2 (probado
conceptualmente sobre Ubuntu 22.04/24.04):

1. Lanza una instancia con Ubuntu Server (una `t3.micro` o `t3.small` alcanza para las
   configuraciones A-C; la configuración D pide 2 GB de RAM, que **no** caben en una
   `t2.micro`/`t3.micro` de la capa gratuita, que solo tiene 1 GB).
2. Abre el puerto **8000** en el grupo de seguridad (solo mientras dure la práctica;
   ciérralo o restríngelo a tu IP después).
3. Conéctate por SSH e instala Docker:

   ```bash
   sudo apt-get update
   curl -fsSL https://get.docker.com | sudo sh
   sudo usermod -aG docker $USER
   # cierra la sesión SSH y vuelve a conectarte para que el grupo "docker" tome efecto
   ```

4. Clona este repositorio y repite las mismas etapas:

   ```bash
   git clone <url-de-tu-repo>
   cd docker-sizing-lab
   ./scripts/start_container.sh 1 512m
   ./scripts/load_test.sh 10
   ```

**Pregunta puente:** ¿los resultados que obtuviste en Codespaces se parecen a los que
obtienes en EC2 para la misma configuración de CPU/RAM? Si no se parecen, ¿a qué
factores (CPU compartida vs. dedicada, tipo de disco, región, ruido de otros
procesos) le atribuyes la diferencia?

---

## Qué NO incluye este laboratorio (a propósito)

Para mantener el foco en el dimensionamiento, este laboratorio evita
deliberadamente: Kubernetes, bases de datos, microservicios, herramientas de
observabilidad complejas y dependencias de servicios cloud. Es un laboratorio
introductorio de dimensionamiento, no un proyecto de DevOps completo.

## Referencia rápida de comandos

```bash
./scripts/start_container.sh <cpus> <memoria>   # ej: ./scripts/start_container.sh 1 512m
./scripts/load_test.sh <usuarios> [duracion] [endpoint]   # ej: ./scripts/load_test.sh 25
./scripts/run_experiment.sh [usuarios] [duracion]          # matriz completa A-D
./scripts/stop_container.sh                                 # limpiar
```
