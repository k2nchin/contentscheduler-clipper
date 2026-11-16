"""Autoriza al Mac a subir a TU Google Drive, una sola vez.

Una cuenta de servicio no tiene disco propio en Drive, así que no puede guardar
archivos. Esto usa tu cuenta: abres el navegador, dices que sí, y el Mac se
queda con un permiso duradero. Los clips serán tuyos y ocuparán tu espacio.

  cd clipper-web && python3 drive/autorizar.py

Necesita el json de un cliente de OAuth de tipo «Aplicación de escritorio»,
guardado en drive/credenciales/cliente-oauth.json. Al terminar escribe
drive/credenciales/usuario.json, que es lo que lee el subidor.
"""

from __future__ import annotations

import http.server
import json
import secrets
import sys
import threading
import urllib.parse
import urllib.request
import webbrowser
from pathlib import Path

AQUI = Path(__file__).resolve().parent
CLIENTE = AQUI / "credenciales" / "cliente-oauth.json"
SALIDA = AQUI / "credenciales" / "usuario.json"
# El estrecho: la app solo ve lo que ella misma crea. Es el que queremos.
SOLO_LO_SUYO = "https://www.googleapis.com/auth/drive.file"
# El amplio: hace falta para escribir en una carpeta que creaste tú a mano.
TODO_EL_DRIVE = "https://www.googleapis.com/auth/drive"
PUERTO = 8765


def alcance() -> tuple[str, bool]:
    """El permiso a pedir. Si apuntas a una carpeta tuya, hace falta el amplio."""
    env = AQUI.parent / ".env"
    carpeta = ""
    if env.is_file():
        for linea in env.read_text().splitlines():
            if linea.startswith("GOOGLE_DRIVE_FOLDER_ID="):
                carpeta = linea.split("=", 1)[1].strip()
    return (TODO_EL_DRIVE, True) if carpeta else (SOLO_LO_SUYO, False)


class Recogida(http.server.BaseHTTPRequestHandler):
    """Se queda con el código que Google devuelve al navegador."""

    codigo: str | None = None
    estado: str = ""

    def do_GET(self) -> None:  # noqa: N802
        datos = urllib.parse.parse_qs(urllib.parse.urlparse(self.path).query)
        bien = datos.get("state", [""])[0] == Recogida.estado and "code" in datos
        if bien:
            Recogida.codigo = datos["code"][0]
        self.send_response(200)
        self.send_header("Content-Type", "text/html; charset=utf-8")
        self.end_headers()
        mensaje = ("Listo. Ya puedes cerrar esta pestaña."
                   if bien else "Algo salió mal. Vuelve a la Terminal.")
        self.wfile.write(f"""<!doctype html><html><head><meta charset="utf-8"></head>
            <body style="margin:0;height:100vh;display:flex;align-items:center;
                         justify-content:center;background:#070708;color:#F5F3EF;
                         font-family:-apple-system,sans-serif">
            <div style="text-align:center">
              <div style="width:46px;height:46px;border-radius:12px;background:#FF0A8A;
                          margin:0 auto 18px"></div>
              <h1 style="font-size:19px;margin:0 0 8px">Content Scheduler</h1>
              <p style="color:#8B8890;font-size:14px;margin:0">{mensaje}</p>
            </div></body></html>""".encode())

    def log_message(self, *_args) -> None:
        pass  # sin ruido en la terminal


def main() -> int:
    if not CLIENTE.is_file():
        print("Falta el archivo del cliente de OAuth.\n")
        print(f"  1. Entra en console.cloud.google.com → tu proyecto")
        print("  2. APIs y servicios → Credenciales → Crear credenciales")
        print("  3. ID de cliente de OAuth → Aplicación de escritorio → Crear")
        print("  4. Descarga el json y guárdalo como:")
        print(f"     {CLIENTE}")
        return 1

    datos = json.loads(CLIENTE.read_text())
    conf = datos.get("installed") or datos.get("web") or {}
    cliente, secreto = conf.get("client_id"), conf.get("client_secret")
    if not cliente or not secreto:
        print("Ese json no parece de un cliente de escritorio. Vuelve a bajarlo.")
        return 1

    permiso, amplio = alcance()
    if amplio:
        print("Vas a dar acceso a tu Drive entero, porque le indicaste una carpeta")
        print("que creaste tú a mano. Si prefieres el permiso mínimo, deja vacío")
        print("GOOGLE_DRIVE_FOLDER_ID en el .env y la app se hará su carpeta.\n")
    else:
        print("Permiso mínimo: la app solo verá los archivos que ella cree.\n")

    destino = f"http://localhost:{PUERTO}"
    Recogida.estado = secrets.token_urlsafe(16)
    url = "https://accounts.google.com/o/oauth2/v2/auth?" + urllib.parse.urlencode({
        "client_id": cliente,
        "redirect_uri": destino,
        "response_type": "code",
        "scope": permiso,
        "access_type": "offline",
        "prompt": "consent",          # obliga a devolver el permiso duradero
        "state": Recogida.estado,
    })

    servidor = http.server.HTTPServer(("localhost", PUERTO), Recogida)
    threading.Thread(target=servidor.handle_request, daemon=True).start()

    print("Se va a abrir el navegador. Entra con la cuenta de Google donde")
    print("quieres que se guarden los clips y dale a Permitir.\n")
    print("Si ves un aviso de que la app no está verificada:")
    print("   Configuración avanzada → Ir a … (no seguro)\n")
    print(f"Si no se abre solo, pega esto en el navegador:\n{url}\n")
    webbrowser.open(url)

    print("Esperando…")
    for _ in range(300):
        if Recogida.codigo:
            break
        threading.Event().wait(1)
    servidor.server_close()

    if not Recogida.codigo:
        print("No llegó la autorización. Vuelve a intentarlo.")
        return 1

    peticion = urllib.request.Request(
        "https://oauth2.googleapis.com/token",
        data=urllib.parse.urlencode({
            "code": Recogida.codigo,
            "client_id": cliente,
            "client_secret": secreto,
            "redirect_uri": destino,
            "grant_type": "authorization_code",
        }).encode(),
        headers={"Content-Type": "application/x-www-form-urlencoded"},
    )
    try:
        with urllib.request.urlopen(peticion, timeout=60) as r:
            respuesta = json.loads(r.read())
    except Exception as e:
        print(f"Google no aceptó el intercambio: {e}")
        return 1

    duradero = respuesta.get("refresh_token")
    if not duradero:
        print("Google no devolvió el permiso duradero.")
        print("Quita el acceso en myaccount.google.com/permissions y repite.")
        return 1

    SALIDA.write_text(json.dumps({
        "client_id": cliente,
        "client_secret": secreto,
        "refresh_token": duradero,
        "scope": permiso,
    }, indent=2))
    SALIDA.chmod(0o600)

    print(f"\nListo. Permiso guardado en {SALIDA.name}")
    print("Ahora los clips subirán a TU Drive, con tu espacio.\n")
    print("Reinicia el subidor:")
    print("   docker compose up -d --build drive && docker compose logs -f drive")
    return 0


if __name__ == "__main__":
    sys.exit(main())
