# Ponerle tu marca de agua a los clips

El motor no marca nada: eso es una decisión del proyecto original, que presume
de no dejar su logo en el trabajo de nadie. Así que la marca la pone un paso
aparte, con tu PNG, después de cortar y antes de subir a Drive.

## Usarlo

1. Deja tu PNG (con fondo transparente) en `clipper-web/marca/marcas/`.
   Ya vienen dos: `puro-clip.png` y `content-scheduler.png`.
2. En el `.env`:

```bash
MARCA_ARCHIVO=puro-clip.png
COMPOSE_PROFILES=drive,marca      # si ya tenías otros, sepáralos con comas
```

3. Y:

```bash
docker-compose up -d --build marca
docker-compose logs -f marca
```

Tiene que decir qué marca usa y dónde la pone. A partir de ahí, cada clip nuevo
sale marcado.

## Cambiar de marca

Cambia `MARCA_ARCHIVO` por otro nombre de la carpeta y reinicia:

```bash
docker-compose up -d --force-recreate marca
```

Los clips ya marcados se quedan como están; los nuevos llevan la nueva.

## Ajustes

| Variable | Qué hace | Por defecto |
|---|---|---|
| `MARCA_ARCHIVO` | Qué PNG usar, de los de `marca/marcas/` | vacío (no marca) |
| `MARCA_POSICION` | `abajo-derecha`, `abajo-izquierda`, `arriba-derecha`, `arriba-izquierda`, `abajo-centro`, `arriba-centro` | abajo-derecha |
| `MARCA_ANCHO` | Qué parte del ancho ocupa, en % | 22 |
| `MARCA_OPACIDAD` | De 0 a 1 | 0.75 |
| `MARCA_MARGEN` | Separación del borde, en % del ancho | 4 |

Para un clip vertical, entre 18 y 25 de ancho suele quedar bien: se ve sin
comerse la imagen.

## Cómo se lleva con lo demás

- **Con Drive**: el subidor espera a que el clip lleve la marca antes de
  subirlo. Sin eso, Drive se quedaría con la versión sin marcar.
- **Con el estudio**: si retocas un clip en el iPhone, el motor lo vuelve a
  renderizar y este paso le pone la marca otra vez.
- **Con la app**: el Clipper del teléfono tiene su propia marca de agua, aparte.
  Esto es solo para los clips que salen del Mac.

## Lo que cuesta

Marcar un clip obliga a recodificar el video, así que tarda unos segundos por
clip y consume procesador. Con un M1 no se nota; en un Mac viejo, sí.

## Si algo falla

| Qué dice | Qué pasa |
|---|---|
| `No encuentro la marca` | El nombre del `.env` no coincide con ningún archivo de `marca/marcas/` |
| `ffmpeg falló` | El PNG está corrupto, o no es PNG |
| No marca nada | Falta `marca` en `COMPOSE_PROFILES` |
| Se ve enorme o diminuta | Ajusta `MARCA_ANCHO` |
