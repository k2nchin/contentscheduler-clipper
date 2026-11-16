#!/usr/bin/env bash
# Enciende todo lo que el iPhone necesita, de una vez.
#
#   encender
#
# Levanta el motor, espera a que responda, saca la dirección pública con el
# túnel y te enseña lo que hay que poner en la app. Deja la ventana abierta:
# si la cierras, el túnel se cae y el teléfono deja de llegar.
set -uo pipefail

cd "$(dirname "$0")/.."
ENV_FILE=".env"

say()  { printf '\n\033[1m%s\033[0m\n' "$1"; }
bad()  { printf '\033[31m%s\033[0m\n' "$1" >&2; }
ok()   { printf '\033[32m  ✓ %s\033[0m\n' "$1"; }

if docker compose version >/dev/null 2>&1; then DC="docker compose"; else DC="docker-compose"; fi

# ─────────────────────────── Docker

if ! docker info >/dev/null 2>&1; then
  say "Abriendo Docker."
  open -a Docker 2>/dev/null || { bad "Docker no está instalado. Corre ./scripts/arrancar-mac.sh"; exit 1; }
  for _ in $(seq 1 60); do
    docker info >/dev/null 2>&1 && break
    sleep 2
  done
  docker info >/dev/null 2>&1 || { bad "Docker no terminó de arrancar."; exit 1; }
fi
ok "Docker"

# ─────────────────────────── El motor

say "Levantando el motor."
$DC up -d >/dev/null 2>&1

printf '   esperando'
listo=no
for _ in $(seq 1 60); do
  if curl -fsS --max-time 3 http://localhost:8000/docs >/dev/null 2>&1; then listo=si; break; fi
  printf '.'
  sleep 3
done
echo
if [ "$listo" != "si" ]; then
  bad "La API no contestó. Mira qué pasa:  $DC logs --tail 30 backend"
  exit 1
fi
ok "Motor respondiendo"

if $DC ps drive 2>/dev/null | grep -q Up; then
  ok "Subida a Drive encendida"
fi

# ─────────────────────────── La clave

CLAVE="$(grep '^CLIP_API_KEY=' "$ENV_FILE" 2>/dev/null | head -1 | cut -d= -f2- | tr -d '[:space:]' || true)"
if [ -z "$CLAVE" ]; then
  SALIDA="$(./scripts/clave-para-el-iphone.sh 2>/dev/null || true)"
  CLAVE="$(printf '%s' "$SALIDA" | grep -oE 'sk_[A-Za-z0-9_-]+' | head -1)"
  if [ -n "$CLAVE" ]; then
    printf 'CLIP_API_KEY=%s\n' "$CLAVE" >> "$ENV_FILE"
    chmod 600 "$ENV_FILE"
  fi
fi

# ─────────────────────────── La dirección

say "Abriendo el túnel. La dirección cambia cada vez."
echo
if [ -n "$CLAVE" ]; then
  printf '   Clave para el iPhone:  \033[1;35m%s\033[0m\n' "$CLAVE"
  echo "   (la misma de siempre; solo cambia la dirección)"
  echo
fi
echo "   En el Mac: http://localhost:3200"
echo

exec ./scripts/tunel-rapido.sh
