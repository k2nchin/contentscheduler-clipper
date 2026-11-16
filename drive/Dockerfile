FROM python:3.12-alpine
RUN pip install --no-cache-dir google-auth==2.43.0 requests==2.32.5
WORKDIR /app
COPY subir.py .
CMD ["python", "-u", "subir.py"]
