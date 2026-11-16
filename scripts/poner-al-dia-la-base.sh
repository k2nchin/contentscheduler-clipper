#!/usr/bin/env bash
# Aplica a la base de datos las migraciones que init.sql no trae.
#
#   cd clipper-web && ./scripts/poner-al-dia-la-base.sh
#
# init.sql crea el esqueleto, pero se quedó atrás: faltan tablas y columnas
# añadidas después (publicación en redes, contadores de uso, Stripe…). Sin
# ellas la web falla al crear la cuenta con «column does not exist».
#
# Las migraciones son SQL normal y casi todas traen IF NOT EXISTS, así que
# aplicarlas sobre una base que ya existe es seguro: lo que ya está se salta.
set -uo pipefail

cd "$(dirname "$0")/.."
MIGR="frontend/prisma/migrations"
PG="supoclip-postgres"
DB="supoclip"
USUARIO="supoclip"

say() { printf '\n\033[1m%s\033[0m\n' "$1"; }
bad() { printf '\033[31m%s\033[0m\n' "$1" >&2; }

if ! docker ps --format '{{.Names}}' | grep -qx "$PG"; then
  bad "La base de datos no está corriendo. Levanta todo primero: docker-compose up -d"
  exit 1
fi

[ -d "$MIGR" ] || { bad "No encuentro $MIGR"; exit 1; }

say "Aplicando migraciones."
aplicadas=0
for dir in "$MIGR"/*/; do
  archivo="${dir}migration.sql"
  [ -f "$archivo" ] || continue
  nombre="$(basename "$dir")"
  # Sin ON_ERROR_STOP: un «ya existe» no debe parar el resto.
  salida="$(docker exec -i "$PG" psql -U "$USUARIO" -d "$DB" -q < "$archivo" 2>&1)"
  graves="$(printf '%s' "$salida" | grep -i "^ERROR" | grep -vi "already exists\|ya existe\|duplicate" || true)"
  if [ -n "$graves" ]; then
    printf '  \033[33m! %s\033[0m\n' "$nombre"
    printf '%s\n' "$graves" | sed 's/^/      /'
  else
    printf '  ✓ %s\n' "$nombre"
  fi
  aplicadas=$((aplicadas + 1))
done

say "Revisando que no falte nada de lo importante."
FALTA=0
for tabla in users social_accounts social_posts social_post_metrics social_oauth_states \
             service_statuses email_deliveries minute_usage_events ai_edit_usage_events \
             stripe_account_migrations; do
  if docker exec -i "$PG" psql -U "$USUARIO" -d "$DB" -tAc \
      "SELECT to_regclass('public.${tabla}') IS NOT NULL" 2>/dev/null | grep -q t; then
    printf '  ✓ %s\n' "$tabla"
  else
    bad "  ✗ falta la tabla ${tabla}"
    FALTA=1
  fi
done

if docker exec -i "$PG" psql -U "$USUARIO" -d "$DB" -tAc \
    "SELECT 1 FROM information_schema.columns WHERE table_name='users' AND column_name='stripe_account_id'" \
    2>/dev/null | grep -q 1; then
  printf '  ✓ users.stripe_account_id\n'
else
  bad "  ✗ falta la columna users.stripe_account_id"
  FALTA=1
fi

if [ "$FALTA" -ne 0 ]; then
  bad "Algo quedó fuera. Pega esta salida entera y lo miramos."
  exit 1
fi

say "Base al día (${aplicadas} migraciones revisadas)."
echo "Reinicia la web para que coja los cambios:"
echo "   docker-compose restart frontend"
echo
echo "Y vuelve a intentar crear la cuenta."
