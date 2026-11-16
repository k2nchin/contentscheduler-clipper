# Llegar al iMac desde la calle (túnel de Cloudflare)

El motor de clipping escucha solo en `127.0.0.1:8000`, o sea, solo dentro del propio iMac.
Esto lo saca a internet con HTTPS, **sin abrir ni un puerto del router** y sin que tu IP de
casa quede expuesta. Es gratis.

El túnel sale *desde* el iMac hacia Cloudflare, así que no hace falta IP fija ni tocar nada
en el router, y funciona igual aunque tu operador te ponga detrás de CGNAT.

## Lo que necesitas

Un dominio con el DNS en Cloudflare. Si no tienes, uno `.com` barato sirve; el plan gratis
de Cloudflare basta.

## Paso 1 — Crear el túnel

1. Entra en **[one.dash.cloudflare.com](https://one.dash.cloudflare.com)** → **Networks** →
   **Tunnels** → **Create a tunnel**.
2. Elige **Cloudflared**, ponle un nombre (por ejemplo `imac-clipper`) y dale a **Save**.
3. Te enseña un comando de instalación. **No lo ejecutes**: lo único que necesitas es el
   token largo que sale dentro, el que empieza por `eyJ…`. Cópialo.

## Paso 2 — Decirle a dónde va

Todavía en la pantalla del túnel, pestaña **Public Hostname** → **Add a public hostname**:

| Campo | Qué poner |
|---|---|
| Subdomain | `clip` |
| Domain | tu dominio |
| Service → Type | `HTTP` |
| Service → URL | depende de dónde corra el túnel, mira abajo |

**La URL cambia según cómo levantes el túnel:**

| Si el túnel corre… | La URL es | Por qué |
|---|---|---|
| en Docker (perfil `tunnel`) | `backend:8000` | el nombre del contenedor, que solo ve la red interna de Docker |
| con `brew` en el Mac | `http://localhost:8000` | desde fuera de Docker, `backend` no existe |

Si te equivocas aquí, el túnel conecta pero Cloudflare te devuelve un **502**.

Guarda. Ya tienes `https://clip.tudominio.com`.

## Paso 3 — Encenderlo en el iMac

### Lo rápido

```bash
cd clipper-web && ./scripts/tunel.sh
```

Te pide el token (sin que se vea, para que no quede en el historial), lo guarda en el
`.env`, enciende el perfil `tunnel`, levanta todo, espera a que el túnel se registre y
comprueba la dirección pública. Si algo falla te dice qué.

### O con brew, sin Docker para el túnel

Si prefieres que el túnel sea un servicio del Mac en vez de un contenedor:

```bash
brew install cloudflared
sudo cloudflared service install <token>
```

`service install` ya lo deja corriendo y arrancando solo con el Mac. **No lances además
`cloudflared tunnel run`**: tendrías dos conectores del mismo túnel a la vez.

Comprobar que vive:

```bash
sudo launchctl list | grep cloudflared
cloudflared tunnel info <nombre-del-tunel>
```

Por este camino el Public Hostname apunta a `http://localhost:8000`, y el motor lo levantas
aparte con `docker-compose up -d` (sin el perfil `tunnel`).

Para quitarlo: `sudo cloudflared service uninstall`.

### O a mano, con el túnel en Docker

En el `.env` de `clipper-web`:

```bash
CLOUDFLARE_TUNNEL_TOKEN=eyJ…        # el token del paso 1
COMPOSE_PROFILES=tunnel             # si ya tenías otros perfiles, sepáralos con comas
```

Y levanta:

```bash
docker-compose up -d
docker-compose logs -f cloudflared   # tiene que decir "Registered tunnel connection"
```

Compruébalo desde el móvil con los datos móviles, no con la wifi de casa:

```
https://clip.tudominio.com/docs
```

Si ves la documentación de la API, está hecho.

## Paso 4 — En el iPhone

**Ajustes → Motor de clipping**:

- Dirección: `https://clip.tudominio.com`
- Clave: la de la web del motor, en **Ajustes → Claves de API** (`sk_…`)
- **Probar conexión**

Desde ahí el Clipper te enseña **«Clipear por link en tu iMac»** y ya puedes mandarle videos
desde donde estés.

## Seguridad

La dirección es pública: cualquiera que la adivine llega a la puerta. Lo que la protege es la
clave de API, que el motor exige en cada llamada. Así que:

- **Una clave por aparato.** Si pierdes el iPhone, la revocas desde la web y el iMac deja de
  obedecerle sin tocar nada más.
- **No pegues la clave en ningún chat ni la subas al repositorio.** En la app vive en el
  llavero del iPhone.
- Si quieres una cerradura más, en el panel del túnel puedes añadir **Access** con una política
  de correo, pero entonces la app necesitaría pasar ese inicio de sesión: déjalo como está a
  menos que lo necesites de verdad.

## Si algo falla

| Qué ves | Qué pasa |
|---|---|
| `Error 1033` en el navegador | El túnel no está conectado: mira `docker-compose logs cloudflared`. |
| `502` desde Cloudflare | El túnel vive pero el motor no: `docker-compose ps backend`. |
| La app dice que rechazó la clave | La clave está mal o la revocaste. Genera otra en la web. |
| Funciona en casa y fuera no | Estás usando la dirección local en vez de la del túnel. |

## Si apagas el iMac

El túnel se cae con él y la app te lo dirá tal cual. Un trabajo que estaba cortando se queda
a medias; al encenderlo otra vez, el motor lo retoma o lo marca como fallido, y lo relanzas
desde la app.
