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


def subir(creds, clip: Path) -> str | None:
    """Sube el archivo entero de una vez y devuelve su identificador en Drive."""
    creds.refresh(google.auth.transport.requests.Request())
    datos = {"name": clip.name, "parents": [CARPETA]}
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
        # El fallo más común con diferencia: la carpeta no está compartida.
        if r.status_code in (403, 404):
            log.error(
                "Drive dice %s. Comparte la carpeta con el correo de la cuenta de "
                "servicio, como Editor, y comprueba el id de la carpeta.",
                r.status_code,
            )
        else:
            log.error("Drive respondió %s: %s", r.status_code, r.text[:200])
        return None
    return (r.json() or {}).get("id")


def vuelta(creds) -> None:
    if not CLIPS.is_dir():
        return
    for clip in sorted(CLIPS.rglob("*")):
        if not clip.is_file() or clip.suffix.lower() not in EXTENSIONES:
            continue
        if testigo(clip).exists() or not estable(clip):
            continue
        log.info("Subiendo %s (%.1f MB)", clip.name, clip.stat().st_size / 1e6)
        ident = subir(creds, clip)
        if not ident:
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
