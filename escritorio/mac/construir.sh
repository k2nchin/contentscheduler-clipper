#!/usr/bin/env bash
# Construye Content Scheduler.app y su .dmg. Solo funciona en un Mac.
#
#   cd clipper-web/escritorio/mac && ./construir.sh
#
# Necesita las herramientas de desarrollo de Apple (si no las tienes, macOS te
# ofrece instalarlas al correr esto). No hace falta Xcode entero.
set -euo pipefail

cd "$(dirname "$0")"
NOMBRE="Content Scheduler"
APP="$NOMBRE.app"
DMG="$NOMBRE.dmg"
ID="com.contentscheduler.mac"

say() { printf '\n\033[1m%s\033[0m\n' "$1"; }
bad() { printf '\033[31m%s\033[0m\n' "$1" >&2; }

[ "$(uname)" = "Darwin" ] || { bad "Esto solo se puede construir en un Mac."; exit 1; }

if ! command -v swiftc >/dev/null 2>&1; then
  say "Faltan las herramientas de desarrollo. Las pide macOS ahora."
  xcode-select --install 2>/dev/null || true
  bad "Acepta la instalación, espera a que termine y vuelve a correr esto."
  exit 1
fi

rm -rf "$APP" "$DMG" dmg

say "Compilando."
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
swiftc -O -target "$(uname -m)-apple-macos12.0" \
       -o "$APP/Contents/MacOS/ContentScheduler" main.swift

say "Montando la app."
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleName</key><string>$NOMBRE</string>
  <key>CFBundleDisplayName</key><string>$NOMBRE</string>
  <key>CFBundleExecutable</key><string>ContentScheduler</string>
  <key>CFBundleIdentifier</key><string>$ID</string>
  <key>CFBundleIconFile</key><string>icono</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>1.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>12.0</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSHumanReadableCopyright</key><string>Content Scheduler</string>
  <!-- La página vive en este mismo Mac y va por http, no por https. -->
  <key>NSAppTransportSecurity</key>
  <dict><key>NSAllowsLocalNetworking</key><true/></dict>
</dict></plist>
PLIST

# El icono: macOS quiere un .icns con todos los tamaños dentro.
if [ -f icono.png ]; then
  rm -rf icono.iconset && mkdir icono.iconset
  for t in 16 32 64 128 256 512; do
    sips -z $t $t icono.png --out "icono.iconset/icon_${t}x${t}.png" >/dev/null 2>&1
    sips -z $((t*2)) $((t*2)) icono.png --out "icono.iconset/icon_${t}x${t}@2x.png" >/dev/null 2>&1
  done
  iconutil -c icns icono.iconset -o "$APP/Contents/Resources/icono.icns" 2>/dev/null || true
  rm -rf icono.iconset
fi

# Una firma local: sin esto macOS la mata nada más abrirla en los Mac con Apple Silicon.
codesign --force --deep --sign - "$APP" 2>/dev/null || true

say "Haciendo el .dmg."
mkdir -p dmg
cp -R "$APP" dmg/
ln -s /Applications "dmg/Aplicaciones"
hdiutil create -volname "$NOMBRE" -srcfolder dmg -ov -format UDZO "$DMG" >/dev/null
rm -rf dmg

say "Listo."
echo "   $(pwd)/$DMG"
echo
echo "Ábrelo y arrastra la app a Aplicaciones."
echo "La primera vez, macOS te dirá que es de un desarrollador no identificado:"
echo "   clic derecho sobre la app → Abrir → Abrir."
echo
echo "La app enseña las herramientas que sirve el motor. Si no está encendido:"
echo "   cd ~/Content-Scheduler/clipper-web && docker-compose up -d"
