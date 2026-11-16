#!/usr/bin/env bash
# Pone el motor a correr a su velocidad real en un Mac con Apple Silicon.
#
#   cd clipper-web && ./scripts/acelerar.sh
#
# Dos cosas lo frenan de fábrica:
#   1. Docker emula un procesador Intel aunque el Mac sea Apple Silicon.
#   2. Transcribir en el propio Mac, por procesador, es lento de por sí.
#
# Lo primero se arregla gratis. Lo segundo, con AssemblyAI, que transcribe en
# la nube en segundos. El script pregunta por la clave y, si no la tienes a
# mano, deja Whisper pero con un modelo más ligero.
set -euo pipefail

cd "$(dirname "$0")/.."
ENV_FILE=".env"

say() { printf '\n\033[1m%s\033[0m\n' "$1"; }
bad() { printf '\033[31m%s\033[0m\n' "$1" >&2; }
ok()  { printf '\033[32m  ✓ %s\033[0m\n' "$1"; }

[ -f "$ENV_FILE" ] || { bad "No hay .env. Corre antes ./scripts/arrancar-mac.sh"; exit 1; }

if docker compose version >/dev/null 2>&1; then DC="docker compose"; else DC="docker-compose"; fi

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

# ─────────────────────────── 1. Sin emulación

ARQ="$(uname -m)"
ACTUAL="$(grep '^BACKEND_PLATFORM=' "$ENV_FILE" | head -1 | cut -d= -f2- | tr -d '[:space:]')"

if [ "$ARQ" = "arm64" ] && [ "$ACTUAL" != "linux/arm64" ]; then
  say "Tu Mac es Apple Silicon y el motor corría emulado como Intel."
  set_env BACKEND_PLATFORM linux/arm64
  set_env BACKEND_CPU_ONLY true
  ok "Ahora correrá nativo"
  RECONSTRUIR=si
elif [ "$ARQ" = "arm64" ]; then
  ok "Ya corría nativo (linux/arm64)"
  RECONSTRUIR=no
else
  ok "Mac con Intel: no hay emulación que quitar"
  RECONSTRUIR=no
fi

# ─────────────────────────── 2. Transcripción

say "Transcripción"
echo "Ahora mismo transcribe en este Mac, por procesador, y es lo que más tarda."
echo "AssemblyAI lo hace en la nube en segundos y tiene capa gratis:"
echo "   https://www.assemblyai.com  →  Sign up  →  la clave sale en el panel"
echo
echo "Pega la clave y dale enter. No se va a ver mientras escribes."
echo "Si la dejas vacía, sigue transcribiendo aquí pero con un modelo más ligero."
printf '> '
read -rs CLAVE
echo
CLAVE="$(printf '%s' "$CLAVE" | tr -d '[:space:]')"

if [ -n "$CLAVE" ]; then
  set_env TRANSCRIPTION_PROVIDER assemblyai
  set_env ASSEMBLY_AI_API_KEY "$CLAVE"
  ok "AssemblyAI puesto"
else
  set_env TRANSCRIPTION_PROVIDER whisper
  set_env WHISPER_MODEL tiny
  ok "Whisper con el modelo ligero (más rápido, algo menos fino)"
fi
chmod 600 "$ENV_FILE"

# ─────────────────────────── 3. Aplicarlo

if [ "$RECONSTRUIR" = "si" ]; then
  say "Reconstruyendo para tu procesador. Esto tarda un rato, y es una sola vez."
  $DC build backend worker
fi

say "Reiniciando el motor."
$DC up -d --force-recreate backend worker

say "Listo."
grep -E "^(BACKEND_PLATFORM|TRANSCRIPTION_PROVIDER|WHISPER_MODEL)=" "$ENV_FILE" | sed 's/^/   /'
echo
echo "Prueba otra vez con un video corto y compara."
echo "Si algo falla: $DC logs --tail 40 worker"
