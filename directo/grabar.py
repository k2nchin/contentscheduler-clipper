"""Graba un directo y va clipeando por trozos mientras sigue en vivo.

El problema de un directo es que no ha terminado: el motor necesita el video
entero para elegir los mejores momentos. Esto lo resuelve partiéndolo: graba
sin parar y, cada vez que se cierra un trozo, lo manda a clipear. Mientras el
streamer sigue hablando, tú ya tienes los clips de hace unos minutos.

  docker compose run --rm directo https://youtube.com/watch?v=...

Variables:
  CLIP_API_URL       dónde está el motor (por defecto http://backend:8000)
  CLIP_API_KEY       la clave sk_… (obligatoria)
  MINUTOS_POR_TROZO  cada cuánto cierra un trozo y lo manda (por defecto 10)
  ALTURA_MAXIMA      calidad que baja del directo (por defecto 720)
  OPCIONES_JSON      ajustes del clipeo, en json, como los manda la app
"""

from __future__ import annotations

import json
import logging
import os
import subprocess
import sys
import time
from pathlib import Path

import requests

logging.basicConfig(level=logging.INFO, format="%(asctime)s  %(levelname)s  %(message)s", datefmt="%H:%M:%S")
log = logging.getLogger("directo")

API = os.getenv("CLIP_API_URL", "http://backend:8000").rstrip("/")
CLAVE = os.getenv("CLIP_API_KEY", "").strip()
MINUTOS = max(2, int(os.getenv("MINUTOS_POR_TROZO", "10")))
ALTURA = int(os.getenv("ALTURA_MAXIMA", "720"))
CARPETA = Path(os.getenv("CARPETA_DIRECTO", "/app/uploads/directos"))

# Lo que se le pide al motor por cada trozo. Se puede cambiar con OPCIONES_JSON.
OPCIONES = {
    "add_subtitles": True,
    "output_format": "vertical",
    "processing_mode": "fast",
    "clip_length": "auto",
    "caption_template": "default",
    "include_broll": False,
}
try:
    OPCIONES.update(json.loads(os.getenv("OPCIONES_JSON", "") or "{}"))
except json.JSONDecodeError:
    log.warning("OPCIONES_JSON no es json válido; se usan los ajustes de siempre.")


def cabeceras() -> dict:
    return {"Authorization": f"Bearer {CLAVE}"}


def subir_y_clipear(trozo: Path) -> None:
    """Sube el trozo al motor y le pide los clips."""
    log.info("Subiendo %s (%.1f MB)", trozo.name, trozo.stat().st_size / 1e6)
    with trozo.open("rb") as f:
        r = requests.post(f"{API}/upload", headers=cabeceras(),
                          files={"video": (trozo.name, f, "video/mp4")}, timeout=3600)
    if r.status_code >= 300:
        log.error("No se pudo subir: %s %s", r.status_code, r.text[:200])
        return
    referencia = (r.json() or {}).get("video_path")
    if not referencia:
        log.error("El motor no devolvió dónde quedó el archivo.")
        return

    cuerpo = {"source": {"url": referencia}, **OPCIONES}
    r = requests.post(f"{API}/tasks/", headers={**cabeceras(), "Content-Type": "application/json"},
                      json=cuerpo, timeout=120)
    if r.status_code >= 300:
        log.error("No se pudo encargar el clipeo: %s %s", r.status_code, r.text[:200])
        return
    log.info("Clipeando el trozo: trabajo %s", (r.json() or {}).get("task_id", "?"))


def main() -> int:
    if len(sys.argv) < 2:
        log.error("Dime qué directo grabar:  docker compose run --rm directo <enlace>")
        return 1
    enlace = sys.argv[1].strip()
    if not CLAVE:
        log.error("Falta CLIP_API_KEY. Sácala con ./scripts/clave-para-el-iphone.sh")
        return 1

    CARPETA.mkdir(parents=True, exist_ok=True)
    marca = time.strftime("%Y%m%d-%H%M%S")
    patron = str(CARPETA / f"{marca}_%03d.mp4")

    log.info("Grabando %s", enlace)
    log.info("Trozos de %d minutos. Cada uno se manda a clipear al cerrarse.", MINUTOS)
    log.info("Ctrl+C para parar. Lo grabado se queda.")

    # yt-dlp saca el directo por la salida estándar y ffmpeg lo va cortando en
    # trozos sin recodificar, que es instantáneo y no gasta procesador.
    bajada = subprocess.Popen(
        ["yt-dlp", "--quiet", "--no-part", "--no-warnings",
         "-f", f"b[height<={ALTURA}]/bv*[height<={ALTURA}]+ba/b", "-o", "-", enlace],
        stdout=subprocess.PIPE,
    )
    corte = subprocess.Popen(
        ["ffmpeg", "-hide_banner", "-loglevel", "error", "-i", "pipe:0",
         "-c", "copy", "-f", "segment", "-segment_time", str(MINUTOS * 60),
         "-reset_timestamps", "1", patron],
        stdin=bajada.stdout,
    )
    if bajada.stdout:
        bajada.stdout.close()

    enviados: set[str] = set()
    try:
        while True:
            trozos = sorted(CARPETA.glob(f"{marca}_*.mp4"))
            # El último sigue creciendo: solo se manda cuando ya existe el siguiente.
            for trozo in trozos[:-1]:
                if trozo.name not in enviados and trozo.stat().st_size > 1_000_000:
                    enviados.add(trozo.name)
                    subir_y_clipear(trozo)
            if corte.poll() is not None:
                break
            time.sleep(10)
    except KeyboardInterrupt:
        log.info("Parando la grabación…")
    finally:
        for p in (bajada, corte):
            if p.poll() is None:
                p.terminate()
                try:
                    p.wait(timeout=20)
                except subprocess.TimeoutExpired:
                    p.kill()

    # El directo acabó o lo paraste: queda el último trozo por mandar.
    for trozo in sorted(CARPETA.glob(f"{marca}_*.mp4")):
        if trozo.name not in enviados and trozo.stat().st_size > 1_000_000:
            subir_y_clipear(trozo)

    log.info("Listo. Los clips salen en la app y en la web, trozo por trozo.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
