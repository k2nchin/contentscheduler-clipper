#!/usr/bin/env bash
# Saca el motor a internet en treinta segundos, sin dominio y sin cuenta.
#
#   cd clipper-web && ./scripts/tunel-rapido.sh
#
# Cloudflare regala una dirección temporal acabada en trycloudflare.com. Sirve
# cuando el router no deja que el iPhone vea al Mac por la wifi, o cuando estás
# en la calle. La pega: la dirección cambia cada vez que lo arrancas.
#
# Para una dirección fija hace falta un dominio: ./scripts/tunel.sh
set -uo pipefail

cd "$(dirname "$0")/.."
PUERTO=8000
LOG="$(mktemp -t tunel-rapido)"

say() { printf '\n\033[1m%s\033[0m\n' "$1"; }
bad() { printf '\033[31m%s\033[0m\n' "$1" >&2; }

if ! command -v cloudflared >/dev/null 2>&1; then
  say "Instalando cloudflared."
  command -v brew >/dev/null 2>&1 || { bad "Necesitas Homebrew."; exit 1; }
  brew install cloudflared
fi

if ! curl -fsS --max-time 5 "http://localhost:${PUERTO}/docs" >/dev/null 2>&1; then
  bad "El motor no responde en el puerto ${PUERTO}. Levántalo: docker-compose up -d"
  exit 1
fi

say "Abriendo el túnel…"
cloudflared tunnel --url "http://localhost:${PUERTO}" --no-autoupdate > "$LOG" 2>&1 &
TUNEL=$!
# Si cierras esta ventana, el túnel se cierra con ella.
trap 'kill $TUNEL 2>/dev/null; rm -f "$LOG"' EXIT INT TERM

DIR=""
for _ in $(seq 1 40); do
  DIR="$(grep -o 'https://[a-z0-9-]*\.trycloudflare\.com' "$LOG" 2>/dev/null | head -1)"
  [ -n "$DIR" ] && break
  kill -0 $TUNEL 2>/dev/null || break
  sleep 2
done

if [ -z "$DIR" ]; then
  bad "No se pudo abrir el túnel. Esto es lo que dijo:"
  tail -20 "$LOG"
  exit 1
fi

say "Listo. Ponle esto al iPhone, en Ajustes → Motor de clipping:"
printf '\n    \033[1;35m%s\033[0m\n\n' "$DIR"
echo "La clave sigue siendo la misma: ./scripts/clave-para-el-iphone.sh"
echo
echo "Deja esta ventana abierta: si la cierras, el túnel se cae y la dirección muere."
echo "Al volver a abrirlo te dará OTRA dirección distinta, y habrá que cambiarla en la app."
echo "Si te cansa, monta el túnel fijo con un dominio: ./scripts/tunel.sh"
echo
echo "Ctrl+C para cerrarlo."
wait $TUNEL
