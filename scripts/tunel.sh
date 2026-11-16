#!/usr/bin/env bash
# Enciende el motor de clipping y lo saca a internet por el túnel de Cloudflare.
#
#   cd clipper-web && ./scripts/tunel.sh
#
# El token se escribe a mano cuando el script lo pide: así no queda en el
# historial de la terminal. Solo se guarda en el .env de esta carpeta, que no
# se sube al repositorio.
set -euo pipefail

cd "$(dirname "$0")/.."
ENV_FILE=".env"

say() { printf '\n\033[1m%s\033[0m\n' "$1"; }
bad() { printf '\n\033[31m%s\033[0m\n' "$1" >&2; }

# ---------------------------------------------------------------- comprobaciones

if ! command -v docker >/dev/null 2>&1; then
  bad "No encuentro Docker. Instala Docker Desktop y vuelve a correr esto."
  echo "   https://www.docker.com/products/docker-desktop/"
  exit 1
fi

if ! docker info >/dev/null 2>&1; then
  bad "Docker está instalado pero no está corriendo. Abre Docker Desktop y espera a que la ballena deje de moverse."
  exit 1
fi

# docker compose (nuevo) o docker-compose (viejo), lo que haya
if docker compose version >/dev/null 2>&1; then
  DC="docker compose"
elif command -v docker-compose >/dev/null 2>&1; then
  DC="docker-compose"
else
  bad "No encuentro «docker compose». Actualiza Docker Desktop."
  exit 1
fi

if [ ! -f "$ENV_FILE" ]; then
  say "No había .env: lo creo a partir de .env.example."
  cp .env.example "$ENV_FILE"
  echo "   Ojo: todavía le faltan las claves del motor (AssemblyAI y el LLM)."
  echo "   Sin ellas arranca, pero no podrá clipear."
fi

# ---------------------------------------------------------------- el token

say "Token del túnel"
echo "Lo saca el panel de Cloudflare al crear el túnel (empieza por eyJ…)."
echo "Pégalo y dale enter. No se va a ver mientras escribes."
printf '> '
read -rs TOKEN
echo

TOKEN="$(printf '%s' "$TOKEN" | tr -d '[:space:]')"
if [ -z "$TOKEN" ]; then
  bad "No pegaste nada."
  exit 1
fi
case "$TOKEN" in
  eyJ*) ;;
  *) bad "Eso no parece un token de túnel: tiene que empezar por «eyJ». Copia solo el token, no el comando entero."; exit 1 ;;
esac

# ---------------------------------------------------------------- escribir el .env

# Cambia la línea si ya existe, la añade si no. El archivo se queda solo para ti.
set_env() {
  local clave="$1" valor="$2"
  if grep -q "^${clave}=" "$ENV_FILE"; then
    # Un archivo temporal al lado, para no depender del sed de macOS ni del de Linux.
    local tmp
    tmp="$(mktemp)"
    grep -v "^${clave}=" "$ENV_FILE" > "$tmp"
    printf '%s=%s\n' "$clave" "$valor" >> "$tmp"
    mv "$tmp" "$ENV_FILE"
  else
    printf '%s=%s\n' "$clave" "$valor" >> "$ENV_FILE"
  fi
}

set_env CLOUDFLARE_TUNNEL_TOKEN "$TOKEN"

# El perfil «tunnel» enciende cloudflared sin apagar los perfiles que ya tuvieras.
PERFILES="$(grep '^COMPOSE_PROFILES=' "$ENV_FILE" | head -1 | cut -d= -f2- || true)"
case ",${PERFILES}," in
  *,tunnel,*) ;;
  *) PERFILES="${PERFILES:+${PERFILES},}tunnel" ;;
esac
set_env COMPOSE_PROFILES "$PERFILES"
chmod 600 "$ENV_FILE"

say "Guardado en .env (perfiles: ${PERFILES})."

# ---------------------------------------------------------------- levantar

say "Levantando el motor y el túnel. La primera vez tarda, que se baja todo."
$DC up -d

say "Esperando a que el túnel se registre…"
ok=no
for _ in $(seq 1 30); do
  if $DC logs cloudflared 2>&1 | grep -q "Registered tunnel connection"; then
    ok=si
    break
  fi
  sleep 2
done

if [ "$ok" != "si" ]; then
  bad "El túnel no llegó a registrarse. Esto es lo último que dijo:"
  $DC logs --tail 25 cloudflared || true
  echo
  echo "Lo más común: el token es de otro túnel, o lo borraste y creaste uno nuevo."
  exit 1
fi

say "Túnel conectado."

# ---------------------------------------------------------------- comprobar

echo
echo "¿Cuál es la dirección pública que le pusiste en «Public Hostname»?"
echo "Por ejemplo: clip.tudominio.com   (enter para saltar la comprobación)"
printf '> '
read -r HOST
HOST="$(printf '%s' "$HOST" | tr -d '[:space:]' | sed -e 's#^https\{0,1\}://##' -e 's#/.*$##')"

if [ -z "$HOST" ]; then
  say "Listo. Cuando añadas el Public Hostname (HTTP → backend:8000), pruébalo tú."
  exit 0
fi

say "Probando https://${HOST}/docs …"
CODE="$(curl -s -o /dev/null -w '%{http_code}' --max-time 25 "https://${HOST}/docs" || echo 000)"

case "$CODE" in
  200)
    say "Funciona."
    echo "En el iPhone, Ajustes → Motor de clipping:"
    echo "   Dirección : https://${HOST}"
    echo "   Clave     : la de la web del motor, Ajustes → Claves de API (sk_…)"
    ;;
  502|503)
    bad "El túnel responde pero el motor no (error ${CODE})."
    echo "Mira cómo está: $DC ps backend && $DC logs --tail 40 backend"
    ;;
  530|000)
    bad "Cloudflare no encuentra el túnel por esa dirección (error ${CODE})."
    echo "Te falta el Public Hostname, o lo pusiste en otro subdominio."
    echo "En el panel del túnel: Public Hostname → HTTP → backend:8000"
    ;;
  *)
    bad "Respondió ${CODE}, que no esperaba."
    echo "Ábrela en el navegador a ver qué dice: https://${HOST}/docs"
    ;;
esac
