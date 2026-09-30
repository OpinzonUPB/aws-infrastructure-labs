FROM python:3.12-slim

WORKDIR /app

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY app/ ./app/

EXPOSE 8000

# Un solo worker a propósito: así los límites de --cpus y --memory que
# apliquemos al contenedor se reflejan directamente en lo que se observa,
# sin que uvicorn reparta la carga entre varios procesos.
CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8000", "--workers", "1"]
