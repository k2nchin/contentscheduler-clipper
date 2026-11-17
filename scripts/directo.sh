#!/usr/bin/env bash
# Graba un directo y lo va clipeando mientras sigue en vivo.
#
#   cd clipper-web && ./scripts/directo.sh https://youtube.com/watch?v=...
#
# Graba sin parar y, cada vez que se cierra un trozo, lo manda a clipear. Así
# tienes clips de lo que pasó hace unos minutos sin esperar a que el streamer
# termine. Ctrl+C para parar; lo grabado se queda y el último trozo se manda.
set -euo pipefail

cd "$(dirname "$0")/.."
ENV_FILE=".env"

say() { printf '\n\033[1m%s\033[0m\n' "$1"; }
bad() { printf '\033[31m%s\033[0m\n' "$1" >&2; }

FONDO=no
ENLACE=""
for arg in "$@"; do
  case "$arg" in
    --fondo|-f) FONDO=si ;;
    --parar|--stop) PARAR=si ;;
    *) ENLACE="$arg" ;;
  esac
done

if docker compose version >/dev/null 2>&1; then DC="docker compose"; else DC="docker-compose"; fi

# Parar una grabación que quedó en marcha
if [ "${PARAR:-no}" = "si" ]; then
  EN_MARCHA="$(docker ps --filter "name=supoclip-directo" --format '{{.Names}}' | head -1)"
  if [ -z "$EN_MARCHA" ]; then
    echo "No hay ninguna grabación en marcha."
  else
    docker stop "$EN_MARCHA" >/dev/null
    echo "Grabación parada. El último trozo se manda a clipear solo."
  fi
  exit 0
fi

if [ -z "$ENLACE" ]; then
  bad "Dime qué directo grabar:"
  echo "   ./scripts/directo.sh https://www.youtube.com/watch?v=..."
  echo
  echo "Opciones:"
  echo "   --fondo    graba sin ocupar la terminal; puedes cerrarla"
  echo "   --parar    para la grabación que esté en marcha"
  exit 1
fi

if ! curl -fsS --max-time 5 http://localhost:8000/docs >/dev/null 2>&1; then
  bad "El motor no está encendido. Levántalo: $DC up -d"
  exit 1
fi

# La clave del motor: la del .env, o se saca una al momento.
CLAVE="$(grep '^CLIP_API_KEY=' "$ENV_FILE" 2>/dev/null | head -1 | cut -d= -f2- | tr -d '[:space:]' || true)"
if [ -z "$CLAVE" ]; then
  say "Hace falta una clave del motor para esto. Saco una."
  SALIDA="$(./scripts/clave-para-el-iphone.sh directo@content.local 2>/dev/null || true)"
  CLAVE="$(printf '%s' "$SALIDA" | grep -oE 'sk_[A-Za-z0-9_-]+' | head -1)"
  if [ -z "$CLAVE" ]; then
    bad "No pude sacar la clave. Hazlo a mano: ./scripts/clave-para-el-iphone.sh"
    bad "y añádela al .env como CLIP_API_KEY=sk_…"
    exit 1
  fi
  printf 'CLIP_API_KEY=%s\n' "$CLAVE" >> "$ENV_FILE"
  chmod 600 "$ENV_FILE"
fi

MIN="${MINUTOS_POR_TROZO:-10}"
say "Grabando el directo. Trozos de ${MIN} minutos."
echo "Cada trozo se manda a clipear al cerrarse, así que los primeros clips"
echo "aparecen unos ${MIN} minutos después de empezar."
echo "Van saliendo en http://localhost:3200 y en el iPhone."
echo

if [ "$FONDO" = "si" ]; then
  # Detached y con nombre fijo, para poder mirarlo y pararlo después.
  docker rm -f supoclip-directo >/dev/null 2>&1 || true
  CLIP_API_KEY="$CLAVE" $DC run -d --name supoclip-directo directo "$ENLACE" >/dev/null
  say "Grabando en segundo plano. Ya puedes cerrar la terminal."
  echo "   Ver cómo va:  docker logs -f supoclip-directo"
  echo "   Parar:        ./scripts/directo.sh --parar"
  echo
  echo "Si el Mac no se duerme, sigue grabando aunque te vayas."
else
  echo "Ctrl+C para parar. Si vas a irte, usa --fondo."
  echo
  CLIP_API_KEY="$CLAVE" $DC run --rm directo "$ENLACE"
fi
