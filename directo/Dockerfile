FROM python:3.12-slim
RUN apt-get update && apt-get install -y --no-install-recommends ffmpeg \
    && rm -rf /var/lib/apt/lists/*
RUN pip install --no-cache-dir "yt-dlp==2026.10.26" requests==2.32.5
WORKDIR /app
COPY grabar.py .
ENTRYPOINT ["python", "-u", "grabar.py"]
