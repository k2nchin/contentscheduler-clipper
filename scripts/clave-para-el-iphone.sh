#!/usr/bin/env bash
# Saca la clave que el iPhone necesita, sin pasar por la web.
#
#   cd clipper-web && ./scripts/clave-para-el-iphone.sh
#
# La web del motor pide crear una cuenta y encima exige verificar el correo
# antes de dar una clave, cosa imposible en un servidor de casa que no manda
# correos. Esto hace lo mismo directamente contra la base de datos: crea el
# usuario una sola vez y te imprime la clave.
set -euo pipefail

cd "$(dirname "$0")/.."
PG="supoclip-postgres"
DB="supoclip"
USUARIO="supoclip"
CORREO="${1:-iphone@content.local}"

say() { printf '\n\033[1m%s\033[0m\n' "$1"; }
bad() { printf '\033[31m%s\033[0m\n' "$1" >&2; }

if ! docker ps --format '{{.Names}}' | grep -qx "$PG"; then
  bad "La base de datos no está corriendo. Levanta el motor: docker-compose up -d"
  exit 1
fi

sql() { docker exec -i "$PG" psql -U "$USUARIO" -d "$DB" -tAc "$1"; }

# La clave: el mismo formato que genera el servidor (sk_ + 32 bytes en base64url).
CLAVE="sk_$(python3 -c 'import secrets;print(secrets.token_urlsafe(32))')"
HASH="$(printf '%s' "$CLAVE" | shasum -a 256 | cut -d' ' -f1)"
PREFIJO="${CLAVE:0:11}"

# El usuario, si no estaba ya. Correo dado por verificado: aquí no hay a quién verificar.
ID="$(sql "SELECT id FROM users WHERE email = '${CORREO}'" | tr -d '[:space:]')"
if [ -z "$ID" ]; then
  ID="$(sql "INSERT INTO users (name, email, \"emailVerified\", is_admin)
             VALUES ('iPhone', '${CORREO}', true, true) RETURNING id" | tr -d '[:space:]')"
  [ -n "$ID" ] || { bad "No se pudo crear el usuario. ¿Corriste ./scripts/poner-al-dia-la-base.sh?"; exit 1; }
  say "Usuario creado para el iPhone (${CORREO})."
else
  say "Ya había un usuario para ${CORREO}; le añado una clave nueva."
fi

sql "INSERT INTO api_keys (user_id, name, key_hash, key_prefix)
     VALUES ('${ID}', 'iPhone', '${HASH}', '${PREFIJO}')" >/dev/null

# La dirección de este Mac en la wifi, que es la que el iPhone tiene que marcar.
IP="$(ipconfig getifaddr en0 2>/dev/null || ipconfig getifaddr en1 2>/dev/null || true)"
ABIERTO="$(docker port supoclip-backend 8000 2>/dev/null | head -1)"

say "Ponle esto al iPhone, en Ajustes → Motor de clipping:"
echo
if printf '%s' "$ABIERTO" | grep -q '^0\.0\.0\.0'; then
  if [ -n "$IP" ]; then
    printf '    Dirección  \033[1m http://%s:8000\033[0m\n' "$IP"
  else
    printf '    Dirección   la IP de este Mac en la wifi, con :8000 al final\n'
  fi
else
  printf '    \033[33mDirección   todavía ninguna: el motor solo escucha dentro de este Mac.\033[0m\n'
  printf '                Para abrirlo a tu wifi, pon BACKEND_BIND=0.0.0.0 en el .env y\n'
  printf '                levanta otra vez: docker-compose up -d backend\n'
  printf '                Para usarlo desde la calle: ./scripts/tunel.sh\n'
fi
printf '    Clave      \033[1;35m %s\033[0m\n\n' "$CLAVE"
echo "Cópiala ahora."
echo "No se guarda en ningún archivo: si la pierdes, vuelve a correr esto y saca otra."
echo
echo "Para anular todas las que hayas sacado:"
echo "   docker exec -i ${PG} psql -U ${USUARIO} -d ${DB} -c \"UPDATE api_keys SET revoked_at = NOW()\""
