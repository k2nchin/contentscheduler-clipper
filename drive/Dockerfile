# Debian y no Alpine: psycopg solo trae binarios para Debian, y en Alpine
# tendría que compilarse desde cero.
FROM python:3.12-slim
RUN pip install --no-cache-dir \
      google-auth==2.62.2 \
      requests==2.32.5 \
      "psycopg[binary]==3.3.9"
WORKDIR /app
COPY subir.py .
CMD ["python", "-u", "subir.py"]
