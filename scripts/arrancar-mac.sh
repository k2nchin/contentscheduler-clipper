#!/usr/bin/env bash
# Deja el motor de clipping funcionando en el Mac, sin claves de pago.
#
#   cd clipper-web && ./scripts/arrancar-mac.sh
#
# Transcribe con Whisper en el propio Mac y elige los momentos con un modelo
# local (Ollama). No se registra nada en ningún sitio ni se paga nada.
# Si luego quieres las versiones de pago, están explicadas en docs/arrancar-en-el-mac.md.
set -euo pipefail

cd "$(dirname "$0")/.."
ENV_FILE=".env"
MODELO="${OLLAMA_MODEL:-gpt-oss:20b}"

say() { printf '\n\033[1m%s\033[0m\n' "$1"; }
bad() { printf '\n\033[31m%s\033[0m\n' "$1" >&2; }
ok()  { printf '\033[32m  ✓ %s\033[0m\n' "$1"; }

# ------------------------------------------------------------------ Docker

if ! command -v docker >/dev/null 2>&1; then
  say "Falta Docker. Lo instalo con Homebrew."
  if ! command -v brew >/dev/null 2>&1; then
    bad "Tampoco tienes Homebrew. Instálalo primero, pega esto y vuelve a correr el script:"
    echo '   /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"'
    exit 1
  fi
  brew install --cask docker
  say "Docker instalado. Ábrelo una vez desde Aplicaciones (pide permiso) y vuelve a correr este script."
  open -a Docker 2>/dev/null || true
  exit 0
fi
ok "Docker instalado"

if ! docker info >/dev/null 2>&1; then
  say "Docker está pero no corre. Lo abro; espera a que la ballena deje de moverse."
  open -a Docker 2>/dev/null || true
  for _ in $(seq 1 60); do
    if docker info >/dev/null 2>&1; then break; fi
    sleep 2
  done
  if ! docker info >/dev/null 2>&1; then
    bad "Docker no terminó de arrancar. Ábrelo a mano y vuelve a correr esto."
    exit 1
  fi
fi
ok "Docker corriendo"

if docker compose version >/dev/null 2>&1; then
  DC="docker compose"
elif command -v docker-compose >/dev/null 2>&1; then
  DC="docker-compose"
else
  bad "No encuentro «docker compose». Actualiza Docker Desktop."
  exit 1
fi

# ------------------------------------------------------------------ Ollama

if ! command -v ollama >/dev/null 2>&1; then
  say "Falta Ollama, que es el que elige los momentos. Lo instalo."
  if ! command -v brew >/dev/null 2>&1; then
    bad "Necesitas Homebrew para esto. Instálalo y repite."
    exit 1
  fi
  brew install ollama
fi
ok "Ollama instalado"

# El servicio tiene que quedarse encendido: el motor le pregunta por el puerto 11434.
if ! curl -fsS --max-time 3 http://localhost:11434/api/version >/dev/null 2>&1; then
  say "Encendiendo Ollama."
  brew services start ollama >/dev/null 2>&1 || true
  for _ in $(seq 1 20); do
    if curl -fsS --max-time 3 http://localhost:11434/api/version >/dev/null 2>&1; then break; fi
    sleep 2
  done
fi
if ! curl -fsS --max-time 3 http://localhost:11434/api/version >/dev/null 2>&1; then
  bad "Ollama no responde en el puerto 11434. Prueba a mano: ollama serve"
  exit 1
fi
ok "Ollama respondiendo"

if ! ollama list 2>/dev/null | grep -q "^${MODELO%%:*}"; then
  say "Bajando el modelo ${MODELO}. Son unos cuantos gigas, una sola vez."
  ollama pull "$MODELO"
fi
ok "Modelo ${MODELO} listo"

# ------------------------------------------------------------------ .env

if [ ! -f "$ENV_FILE" ]; then
  cp .env.example "$ENV_FILE"
  ok "Creado .env"
fi

set_env() {
  local clave="$1" valor="$2" tmp
  if grep -q "^${clave}=" "$ENV_FILE"; then
    tmp="$(mktemp)"
    grep -v "^${clave}=" "$ENV_FILE" > "$tmp"
    printf '%s=%s\n' "$clave" "$valor" >> "$tmp"
    mv "$tmp" "$ENV_FILE"
  else
    printf '%s=%s\n' "$clave" "$valor" >> "$ENV_FILE"
  fi
}

# Todo en local: Whisper transcribe, Ollama decide. Ninguna clave de pago.
set_env TRANSCRIPTION_PROVIDER whisper
set_env WHISPER_MODEL "${WHISPER_MODEL:-base}"
set_env LLM "ollama:${MODELO}"
# Desde el contenedor, el Mac anfitrión se llama host.docker.internal.
set_env OLLAMA_BASE_URL "http://host.docker.internal:11434/v1"
# Los workflows abiertos: es tu propio servidor, no hay a quién limitarle nada.
set_env WORKFLOWS_ACCESS all
chmod 600 "$ENV_FILE"
ok "Configurado sin claves de pago (Whisper + ${MODELO})"

# ------------------------------------------------------------------ arrancar

say "Levantando el motor. La primera vez tarda bastante: se construyen las imágenes."
$DC up -d

say "Esperando a que la API conteste…"
listo=no
for _ in $(seq 1 60); do
  if curl -fsS --max-time 3 http://localhost:8000/docs >/dev/null 2>&1; then listo=si; break; fi
  sleep 3
done

if [ "$listo" != "si" ]; then
  bad "La API no contestó. Lo último que dijo el backend:"
  $DC logs --tail 30 backend || true
  exit 1
fi

say "El motor está vivo."
echo "   API      : http://localhost:8000/docs"
echo "   Web      : http://localhost:3001"
echo
echo "Ahora, en la web, créate la cuenta y saca una clave en Ajustes → Claves de API."
echo "Esa clave (sk_…) es la que va en el iPhone, en Ajustes → Motor de clipping."
echo
echo "Para usarlo desde la calle: ./scripts/tunel.sh"
echo "Para apagarlo: $DC down"
