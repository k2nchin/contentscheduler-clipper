"""Sube a Google Drive cada clip que el motor termina de cortar.

Mira la carpeta de clips cada pocos segundos y, cuando aparece uno nuevo y ya
no está creciendo, lo sube a la carpeta de Drive que se le diga. Al lado de
cada archivo deja un `.drive` con el identificador, que es como sabe lo que ya
subió: sobrevive a reinicios y no hace falta tocar la base de datos.

Entra en marcha solo si hay credenciales. Sin ellas se duerme y no estorba.

Variables:
  GOOGLE_DRIVE_SA_JSON    ruta al json de la cuenta de servicio (obligatoria)
  GOOGLE_DRIVE_FOLDER_ID  carpeta de Drive donde dejarlos (obligatoria)
  CLIPS_DIR               dónde mirar (por defecto /app/uploads/clips)
  DRIVE_BORRAR_LOCAL      "true" borra el clip del Mac tras subirlo
  DRIVE_INTERVALO         segundos entre vistazos (por defecto 15)
"""

from __future__ import annotations

import json
import logging
import os
import sys
import time
from pathlib import Path

import google.auth.transport.requests
import psycopg
import requests
from google.oauth2 import service_account

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s  %(levelname)s  %(message)s",
    datefmt="%H:%M:%S",
)
log = logging.getLogger("drive")

SA_JSON = os.getenv("GOOGLE_DRIVE_SA_JSON", "/credenciales/cuenta-de-servicio.json")
CARPETA = os.getenv("GOOGLE_DRIVE_FOLDER_ID", "").strip()
CLIPS = Path(os.getenv("CLIPS_DIR", "/app/uploads/clips"))
BORRAR = os.getenv("DRIVE_BORRAR_LOCAL", "false").lower() == "true"
INTERVALO = max(5, int(os.getenv("DRIVE_INTERVALO", "15")))
EXTENSIONES = {".mp4", ".mov", ".m4v"}
ALCANCE = ["https://www.googleapis.com/auth/drive.file"]

# Un archivo a medio escribir no se sube: tiene que llevar quieto este rato.
ESPERA_ESTABLE = 6

# Para poder nombrar las carpetas con el video del que salió cada clip.
BD = os.getenv("DRIVE_DATABASE_URL", "postgresql://supoclip:supoclip_password@postgres:5432/supoclip")
ORGANIZAR = os.getenv("DRIVE_ORGANIZAR", "true").lower() != "false"

# Carpetas de Drive ya creadas, para no preguntar por cada clip.
_carpetas: dict[str, str] = {}


def credenciales():
    if not CARPETA:
        log.error("Falta GOOGLE_DRIVE_FOLDER_ID. Mira docs/clips-a-drive.md")
        return None
    if not Path(SA_JSON).is_file():
        log.error("No encuentro el json de la cuenta de servicio en %s", SA_JSON)
        return None
    try:
        return service_account.Credentials.from_service_account_file(SA_JSON, scopes=ALCANCE)
    except Exception as e:
        log.error("El json de la cuenta de servicio no sirve: %s", e)
        return None


def origen(nombre: str) -> tuple[str, str] | None:
    """De qué video salió este clip: (identificador del trabajo, título)."""
    try:
        with psycopg.connect(BD, connect_timeout=10) as con, con.cursor() as cur:
            cur.execute(
                """
                SELECT t.id, COALESCE(NULLIF(s.title, ''), s.url, 'Sin titulo'),
                       to_char(t.created_at, 'YYYY-MM-DD')
                FROM generated_clips g
                JOIN tasks t ON t.id = g.task_id
                LEFT JOIN sources s ON s.id = t.source_id
                WHERE g.filename = %s
                LIMIT 1
                """,
                (nombre,),
            )
            fila = cur.fetchone()
    except Exception as e:
        log.warning("No pude mirar de qué video salió %s: %s", nombre, e)
        return None
    if not fila:
        return None
    ident, titulo, fecha = fila
    return ident, f"{fecha} · {limpiar(titulo)}"


def limpiar(titulo: str) -> str:
    """Un nombre de carpeta corto y sin caracteres que molesten."""
    malos = '\\/:*?"<>|'
    limpio = "".join(" " if c in malos else c for c in (titulo or "")).strip()
    limpio = " ".join(limpio.split())
    return (limpio[:70] or "Sin titulo")


def carpeta_para(creds, trabajo: str, nombre: str) -> str:
    """Devuelve la carpeta de Drive de ese video, creándola la primera vez."""
    if trabajo in _carpetas:
        return _carpetas[trabajo]
    creds.refresh(google.auth.transport.requests.Request())
    cabecera = {"Authorization": f"Bearer {creds.token}"}

    # Si ya existe de una vuelta anterior, se reutiliza en vez de duplicarla.
    consulta = (f"name = '{nombre.replace(chr(39), chr(92) + chr(39))}' and "
                f"'{CARPETA}' in parents and "
                "mimeType = 'application/vnd.google-apps.folder' and trashed = false")
    r = requests.get("https://www.googleapis.com/drive/v3/files",
                     params={"q": consulta, "fields": "files(id)", "supportsAllDrives": "true",
                             "includeItemsFromAllDrives": "true"},
                     headers=cabecera, timeout=60)
    if r.status_code < 300:
        encontradas = (r.json() or {}).get("files") or []
        if encontradas:
            _carpetas[trabajo] = encontradas[0]["id"]
            return _carpetas[trabajo]

    r = requests.post("https://www.googleapis.com/drive/v3/files",
                      params={"supportsAllDrives": "true"},
                      headers={**cabecera, "Content-Type": "application/json"},
                      json={"name": nombre, "parents": [CARPETA],
                            "mimeType": "application/vnd.google-apps.folder"},
                      timeout=60)
    if r.status_code >= 300:
        log.warning("No pude crear la carpeta «%s»: %s", nombre, r.status_code)
        return CARPETA
    ident = (r.json() or {}).get("id") or CARPETA
    _carpetas[trabajo] = ident
    log.info("Carpeta nueva en Drive: %s", nombre)
    return ident


def testigo(clip: Path) -> Path:
    return clip.with_suffix(clip.suffix + ".drive")


def estable(clip: Path) -> bool:
    """Verdadero si el archivo dejó de crecer."""
    try:
        antes = clip.stat()
    except FileNotFoundError:
        return False
    if time.time() - antes.st_mtime < ESPERA_ESTABLE:
        return False
    return antes.st_size > 0


# Cuando el destino está mal, reintentar cada pocos segundos solo gasta datos:
# se para un rato y se avisa una vez, no en cada vuelta.
ESPERA_TRAS_FALLO_DE_CONFIGURACION = 300
_pausa_hasta = 0.0
_ya_avisado = False


def subir(creds, clip: Path, destino: str | None = None) -> str | None:
    """Sube el archivo entero de una vez y devuelve su identificador en Drive."""
    creds.refresh(google.auth.transport.requests.Request())
    datos = {"name": clip.name, "parents": [destino or CARPETA]}
    with clip.open("rb") as f:
        r = requests.post(
            "https://www.googleapis.com/upload/drive/v3/files",
            params={"uploadType": "multipart", "supportsAllDrives": "true"},
            headers={"Authorization": f"Bearer {creds.token}"},
            files={
                "metadata": ("metadata", json.dumps(datos), "application/json"),
                "file": (clip.name, f, "video/mp4"),
            },
            timeout=1800,
        )
    if r.status_code >= 300:
        global _pausa_hasta, _ya_avisado
        # El fallo más común con diferencia: la carpeta no está compartida.
        if r.status_code in (403, 404):
            log.error("No se pudo subir %s: Drive dice %s (%s).",
                      clip.name, r.status_code, motivo_de_google(r))
            if not _ya_avisado:
                razon = motivo_de_google(r)
                if "storageQuota" in razon or "quota" in razon.lower():
                    # Lo más habitual: una cuenta de servicio no tiene disco propio.
                    log.error("Una cuenta de servicio no tiene espacio propio en Drive, así que")
                    log.error("puede crear carpetas pero no guardar archivos. Hace falta una")
                    log.error("unidad compartida. Está explicado en docs/clips-a-drive.md")
                elif r.status_code == 404:
                    log.error("Esa carpeta no existe para la cuenta de servicio.")
                    log.error("Revisa que GOOGLE_DRIVE_FOLDER_ID sea solo el id de la carpeta.")
                else:
                    log.error("La carpeta tiene que estar compartida como Editor con:")
                    log.error("     %s", correo_de_la_cuenta())
                log.error("Reviso otra vez en %d minutos.", ESPERA_TRAS_FALLO_DE_CONFIGURACION // 60)
                _ya_avisado = True
            _pausa_hasta = time.time() + ESPERA_TRAS_FALLO_DE_CONFIGURACION
        else:
            log.error("Drive respondió %s: %s", r.status_code, r.text[:200])
        return None
    _ya_avisado = False
    return (r.json() or {}).get("id")


def motivo_de_google(r) -> str:
    """El porqué exacto que manda Google, que es lo que distingue un caso de otro."""
    try:
        error = (r.json() or {}).get("error") or {}
        listado = error.get("errors") or []
        razon = listado[0].get("reason") if listado else ""
        return f"{razon}: {error.get('message', '')}".strip(": ") or r.text[:120]
    except Exception:
        return r.text[:120]


def correo_de_la_cuenta() -> str:
    """El correo que hay que invitar a la carpeta, sacado del propio json."""
    try:
        return json.loads(Path(SA_JSON).read_text()).get("client_email", "(no se pudo leer)")
    except Exception:
        return "(no se pudo leer el json)"


def vuelta(creds) -> None:
    if not CLIPS.is_dir():
        return
    if time.time() < _pausa_hasta:
        return
    for clip in sorted(CLIPS.rglob("*")):
        if not clip.is_file() or clip.suffix.lower() not in EXTENSIONES:
            continue
        if testigo(clip).exists() or not estable(clip):
            continue
        destino = CARPETA
        etiqueta = ""
        if ORGANIZAR:
            datos = origen(clip.name)
            if datos:
                trabajo, nombre = datos
                destino = carpeta_para(creds, trabajo, nombre)
                etiqueta = f" → {nombre}"
        log.info("Subiendo %s (%.1f MB)%s", clip.name, clip.stat().st_size / 1e6, etiqueta)
        ident = subir(creds, clip, destino)
        if not ident:
            # Si el destino está mal, el resto de la tanda va a fallar igual:
            # mejor parar que mandar cien megas para recibir el mismo no.
            if time.time() < _pausa_hasta:
                log.info("Dejo el resto para cuando esté arreglado.")
                return
            continue
        testigo(clip).write_text(ident)
        log.info("Subido: %s", ident)
        if BORRAR:
            try:
                clip.unlink()
                log.info("Borrado del disco: %s", clip.name)
            except OSError as e:
                log.warning("No se pudo borrar %s: %s", clip.name, e)


def main() -> int:
    creds = credenciales()
    if creds is None:
        log.info("Sin configurar: no voy a subir nada. Esto no rompe el motor.")
        while True:
            time.sleep(3600)
    log.info("Vigilando %s cada %ss. Carpeta de Drive: %s", CLIPS, INTERVALO, CARPETA)
    if BORRAR:
        log.warning("DRIVE_BORRAR_LOCAL está puesto: los clips se borran del disco tras subirlos.")
    while True:
        try:
            vuelta(creds)
        except Exception as e:  # una vuelta mala no debe tumbar el servicio
            log.error("Fallo en esta vuelta: %s", e)
        time.sleep(INTERVALO)


if __name__ == "__main__":
    sys.exit(main())
