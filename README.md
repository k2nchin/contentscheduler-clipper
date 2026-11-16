# Content Scheduler — Clipper web

El motor de clipping de Content Scheduler: pegas un video largo (YouTube, Twitch, Kick o un
archivo tuyo), la IA busca los momentos que valen, y salen clips verticales 9:16 con encuadre
a la cara, subtítulos sincronizados palabra por palabra y título de gancho.

Esto es la **versión web/servidor**. La app de iPhone vive en `../ios`.

## De dónde viene (importante)

Es un fork de **[SupoClip](https://github.com/FujiwaraChoki/supoclip)**, de Sami Hindi
(FujiwaraChoki), bajo licencia **AGPL-3.0**. Aquí se cambió la marca, la paleta y la
tipografía por las de Content Scheduler; el motor de clipping es el suyo.

La AGPL-3.0 sigue aplicando a todo este directorio: el archivo `LICENSE` se conserva tal cual
y, **si pones esto en un servidor para que lo use otra gente, tienes que ofrecerles el código
fuente** de tu versión. El resto del repositorio (la app de iOS) no es obra derivada y mantiene
su propia licencia.

## El estilo de Content Scheduler

- **Paleta** en `frontend/src/app/globals.css`, tokens `--cs-*`:
  fondo `#070708`, superficies `#101012` / `#1C1B20`, texto `#F5F3EF`,
  acento rosa `#FF0A8A`, violeta `#7A2CFF`, línea `#222126`,
  verde `#5EE6A8`, ámbar `#FFC65C`, rojo `#FF6B6B`, radio 14px.
- **Siempre oscuro**, como en el iPhone: no hay tema claro (`theme-provider.tsx`).
- **Títulos en Nunito** (la redonda más parecida a SF Rounded, que es la de la app).
- **Logo** de Content Scheduler en `frontend/public/logo.png` y `frontend/src/app/icon.*`.

## Qué tienes que rellenar antes de publicarla

| Dónde | Qué |
|---|---|
| `frontend/src/lib/site.ts` | datos de empresa, dirección y número de registro (están vacíos) |
| `frontend/src/app/terms/page.tsx`, `privacy/page.tsx` | correos de contacto (`tudominio.com`) |
| `.env` | claves: AssemblyAI (transcripción), el LLM, base de datos, Redis |

## Levantarlo

En un Mac, de una vez y sin claves de pago:

```bash
cd clipper-web && ./scripts/arrancar-mac.sh
```

Instala lo que falte, transcribe con Whisper y elige los momentos con un modelo
local. Los detalles, y cómo pasarse a AssemblyAI o Gemini si lo quieres más
rápido, en **[`docs/arrancar-en-el-mac.md`](docs/arrancar-en-el-mac.md)**.

A mano:

```bash
docker-compose up -d        # web :3001, API :8000, worker, Postgres, Redis
```

En local sin Docker, y el resto de la arquitectura, está en `CLAUDE.md` y en `docs/`.

## Usarlo desde el iPhone

La app de iOS le manda el link y se trae los clips ya cortados
(Ajustes → Motor de clipping). En la misma wifi no hace falta nada más que la
dirección del ordenador; para usarlo desde la calle, el túnel de Cloudflare está
explicado paso a paso en **[`docs/tunel-cloudflare.md`](docs/tunel-cloudflare.md)**:
sale a internet con HTTPS sin abrir puertos del router.
