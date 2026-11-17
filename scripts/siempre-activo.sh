#!/usr/bin/env bash
# Deja el motor y el túnel encendidos para siempre, sin ventanas abiertas.
#
#   ./scripts/siempre-activo.sh
#
# Hace tres cosas:
#   1. El Mac no se duerme mientras esté enchufado.
#   2. Docker se abre solo al encender el Mac.
#   3. El túnel corre como servicio y, si se cae, se vuelve a levantar solo.
#
# Para quitarlo todo:  ./scripts/siempre-activo.sh --quitar
set -euo pipefail

cd "$(dirname "$0")/.."
RAIZ="$(pwd)"
AGENTES="$HOME/Library/LaunchAgents"
ETIQUETA="com.contentscheduler.motor"
PLIST="$AGENTES/$ETIQUETA.plist"
VIGILANTE="$RAIZ/scripts/.mantener-vivo.sh"
DIRECCION="$HOME/Content-Scheduler-direccion.txt"
REGISTRO="$HOME/Library/Logs/content-scheduler.log"

say() { printf '\n\033[1m%s\033[0m\n' "$1"; }
bad() { printf '\033[31m%s\033[0m\n' "$1" >&2; }
ok()  { printf '\033[32m  ✓ %s\033[0m\n' "$1"; }

# ─────────────────────────── Quitarlo

if [ "${1:-}" = "--quitar" ]; then
  launchctl bootout "gui/$(id -u)/$ETIQUETA" 2>/dev/null || true
  rm -f "$PLIST" "$VIGILANTE"
  sudo pmset -c sleep 10 2>/dev/null || true
  say "Quitado. El Mac vuelve a dormirse y el túnel ya no arranca solo."
  exit 0
fi

[ "$(uname)" = "Darwin" ] || { bad "Esto es solo para macOS."; exit 1; }

# ─────────────────────────── 1. Que no se duerma

say "Que el Mac no se duerma mientras esté enchufado."
echo "Te va a pedir la contraseña."
sudo pmset -c sleep 0
sudo pmset -c disksleep 0
ok "Despierto con el cable puesto"
echo "   (la pantalla sí se apaga; eso no corta nada)"

# ─────────────────────────── 2. Docker al encender

say "Docker al arrancar el Mac."
osascript -e 'tell application "System Events" to make login item at end with properties {path:"/Applications/Docker.app", hidden:true}' >/dev/null 2>&1 \
  && ok "Docker se abrirá solo" \
  || echo "   No pude añadirlo. Hazlo a mano: Ajustes del sistema → General → Ítems de inicio"

# ─────────────────────────── 3. El vigilante

cat > "$VIGILANTE" <<SCRIPT
#!/usr/bin/env bash
# Mantiene el motor y el túnel en pie. Lo lanza macOS al encender.
cd "$RAIZ"
export PATH="/usr/local/bin:/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin"

# Docker tarda en estar listo después de encender el Mac.
for _ in \$(seq 1 60); do
  docker info >/dev/null 2>&1 && break
  sleep 10
done

docker compose up -d >/dev/null 2>&1 || docker-compose up -d >/dev/null 2>&1

# El túnel en bucle: si se cae, se vuelve a abrir con dirección nueva.
while true; do
  LOG="\$(mktemp -t tunel)"
  cloudflared tunnel --url http://localhost:8000 --no-autoupdate > "\$LOG" 2>&1 &
  TUNEL=\$!
  for _ in \$(seq 1 40); do
    DIR="\$(grep -o 'https://[a-z0-9-]*\.trycloudflare\.com' "\$LOG" 2>/dev/null | head -1)"
    [ -n "\$DIR" ] && break
    sleep 2
  done
  if [ -n "\$DIR" ]; then
    printf '%s\n' "\$DIR" > "$DIRECCION"
    echo "\$(date '+%F %T')  túnel: \$DIR"
  else
    echo "\$(date '+%F %T')  no se pudo abrir el túnel"
  fi
  wait \$TUNEL
  rm -f "\$LOG"
  echo "\$(date '+%F %T')  el túnel se cayó; reabriendo"
  sleep 5
done
SCRIPT
chmod +x "$VIGILANTE"

mkdir -p "$AGENTES"
cat > "$PLIST" <<PLISTF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>Label</key><string>$ETIQUETA</string>
  <key>ProgramArguments</key><array><string>$VIGILANTE</string></array>
  <key>RunAtLoad</key><true/>
  <key>KeepAlive</key><true/>
  <key>StandardOutPath</key><string>$REGISTRO</string>
  <key>StandardErrorPath</key><string>$REGISTRO</string>
</dict></plist>
PLISTF

launchctl bootout "gui/$(id -u)/$ETIQUETA" 2>/dev/null || true
launchctl bootstrap "gui/$(id -u)" "$PLIST"
ok "Servicio instalado"

# ─────────────────────────── Listo

say "Esperando la primera dirección…"
for _ in $(seq 1 45); do
  [ -s "$DIRECCION" ] && break
  sleep 2
done

if [ -s "$DIRECCION" ]; then
  printf '\n    \033[1;35m%s\033[0m\n\n' "$(cat "$DIRECCION")"
  echo "Esa es la dirección de ahora. Al reiniciar el Mac será otra."
else
  bad "Todavía no hay dirección. Mira el registro: tail -f $REGISTRO"
fi

cat <<FIN

A partir de ahora el motor y el túnel se levantan solos al encender el Mac,
sin ventanas abiertas, y si el túnel se cae se vuelve a abrir.

La dirección de cada momento está siempre aquí:
   $DIRECCION

Para verla rápido:   cat $DIRECCION
Para ver qué pasa:   tail -f $REGISTRO
Para quitarlo todo:  ./scripts/siempre-activo.sh --quitar

Un aviso: SIN DOMINIO la dirección cambia cada vez que el túnel se reabre, y
hay que cambiarla en el iPhone. Con un dominio en Cloudflare queda una fija
para siempre: ./scripts/tunel.sh
FIN
