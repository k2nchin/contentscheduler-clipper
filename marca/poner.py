"""Pone tu marca de agua en cada clip que sale del motor.

El motor no marca nada, así que esto se encarga: vigila la carpeta de clips y,
en cuanto aparece uno nuevo y terminado, le superpone el PNG que elijas con
ffmpeg y reemplaza el archivo. Deja al lado un `.marca` para no repetirse.

Las marcas van en marca/marcas/. Para cambiar de marca, basta con cambiar
MARCA_ARCHIVO en el .env; no hace falta tocar nada más.

Variables:
  MARCA_ARCHIVO    nombre del png dentro de marcas/ (vacío = no marcar nada)
  MARCA_POSICION   abajo-derecha | abajo-izquierda | arriba-derecha |
                   arriba-izquierda | abajo-centro
  MARCA_ANCHO      qué parte del ancho ocupa, en tanto por ciento (por defecto 22)
  MARCA_OPACIDAD   de 0 a 1 (por defecto 0.75)
  MARCA_MARGEN     separación del borde, en tanto por ciento (por defecto 4)
"""

from __future__ import annotations

import logging
import os
import shutil
import subprocess
import time
from pathlib import Path

logging.basicConfig(level=logging.INFO, format="%(asctime)s  %(levelname)s  %(message)s", datefmt="%H:%M:%S")
log = logging.getLogger("marca")

CLIPS = Path(os.getenv("CLIPS_DIR", "/app/uploads/clips"))
MARCAS = Path(os.getenv("MARCAS_DIR", "/marcas"))
ARCHIVO = os.getenv("MARCA_ARCHIVO", "").strip()
POSICION = os.getenv("MARCA_POSICION", "abajo-derecha").strip()
ANCHO = max(3, min(60, int(os.getenv("MARCA_ANCHO", "22"))))
OPACIDAD = max(0.05, min(1.0, float(os.getenv("MARCA_OPACIDAD", "0.75"))))
MARGEN = max(0, min(20, int(os.getenv("MARCA_MARGEN", "4"))))
INTERVALO = max(5, int(os.getenv("MARCA_INTERVALO", "10")))
EXTENSIONES = {".mp4", ".mov", ".m4v"}
ESPERA_ESTABLE = 6

# Dónde va la marca, en coordenadas de ffmpeg.
ESQUINAS = {
    "abajo-derecha": ("W-w-{m}", "H-h-{m}"),
    "abajo-izquierda": ("{m}", "H-h-{m}"),
    "arriba-derecha": ("W-w-{m}", "{m}"),
    "arriba-izquierda": ("{m}", "{m}"),
    "abajo-centro": ("(W-w)/2", "H-h-{m}"),
    "arriba-centro": ("(W-w)/2", "{m}"),
}


def testigo(clip: Path) -> Path:
    return clip.with_suffix(clip.suffix + ".marca")


def estable(clip: Path) -> bool:
    try:
        st = clip.stat()
    except FileNotFoundError:
        return False
    return st.st_size > 0 and time.time() - st.st_mtime >= ESPERA_ESTABLE


def filtro() -> str:
    """El filtro de ffmpeg: escalar la marca al ancho del video, darle
    transparencia y pegarla en la esquina elegida.

    El escalado va con scale2ref porque dentro de `scale` no se puede mirar el
    tamaño del video; ffmpeg lo rechaza.
    """
    x, y = ESQUINAS.get(POSICION, ESQUINAS["abajo-derecha"])
    # El margen se mide contra el ancho, para que no baile entre formatos.
    margen = f"W*{MARGEN/100:.4f}"
    return (
        f"[1:v][0:v]scale2ref=w=iw*{ANCHO/100:.4f}:h=ow/mdar[escalada][video];"
        f"[escalada]format=rgba,colorchannelmixer=aa={OPACIDAD:.2f}[marca];"
        f"[video][marca]overlay={x.format(m=margen)}:{y.format(m=margen)}"
    )


def marcar(clip: Path, marca: Path) -> bool:
    salida = clip.with_suffix(".marcado.mp4")
    orden = [
        "ffmpeg", "-hide_banner", "-loglevel", "error", "-y",
        "-i", str(clip), "-i", str(marca),
        "-filter_complex", filtro(),
        "-c:a", "copy", "-c:v", "libx264", "-preset", "veryfast", "-crf", "20",
        "-movflags", "+faststart",
        str(salida),
    ]
    r = subprocess.run(orden, capture_output=True, text=True)
    if r.returncode != 0 or not salida.exists():
        log.error("ffmpeg falló con %s: %s", clip.name, (r.stderr or "")[:200])
        salida.unlink(missing_ok=True)
        return False
    # Reemplazo en un paso, para que nadie lea el archivo a medio escribir.
    shutil.move(str(salida), str(clip))
    return True


def vuelta(marca: Path) -> None:
    if not CLIPS.is_dir():
        return
    for clip in sorted(CLIPS.rglob("*")):
        if not clip.is_file() or clip.suffix.lower() not in EXTENSIONES:
            continue
        if testigo(clip).exists() or not estable(clip):
            continue
        log.info("Marcando %s", clip.name)
        if marcar(clip, marca):
            testigo(clip).write_text(ARCHIVO)
            log.info("Marcado: %s", clip.name)


def main() -> int:
    if not ARCHIVO:
        log.info("Sin marca de agua configurada (MARCA_ARCHIVO vacío). No toco nada.")
        while True:
            time.sleep(3600)
    marca = MARCAS / ARCHIVO
    if not marca.is_file():
        log.error("No encuentro la marca «%s» en %s", ARCHIVO, MARCAS)
        disponibles = [p.name for p in MARCAS.glob("*.png")] if MARCAS.is_dir() else []
        log.error("Las que tienes: %s", ", ".join(disponibles) or "ninguna")
        while True:
            time.sleep(3600)

    log.info("Marca: %s · %s · %d%% de ancho · opacidad %.2f", ARCHIVO, POSICION, ANCHO, OPACIDAD)
    log.info("Vigilando %s cada %ss.", CLIPS, INTERVALO)
    while True:
        try:
            vuelta(marca)
        except Exception as e:
            log.error("Fallo en esta vuelta: %s", e)
        time.sleep(INTERVALO)


if __name__ == "__main__":
    raise SystemExit(main())
