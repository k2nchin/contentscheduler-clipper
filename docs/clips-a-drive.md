# Que los clips suban solos a tu Google Drive

El Mac sube cada clip a tu Drive en cuanto lo termina, sin que el iPhone tenga que
estar encendido ni abierto. Son unos minutos de preparación, una sola vez.

Hace falta una **cuenta de servicio**: un usuario de Google que no es una persona,
pensado para que un programa trabaje solo. Es lo correcto aquí, porque un inicio de
sesión normal caduca y habría que volver a entrar cada dos por tres.

## Paso 1 — Crear la cuenta de servicio

1. Entra en **[console.cloud.google.com](https://console.cloud.google.com)** con tu cuenta.
2. Arriba, crea un proyecto nuevo (o usa uno que ya tengas). Llámalo `content-scheduler`.
3. Busca **"Google Drive API"** y dale a **Habilitar**.
4. Ve a **IAM y administración → Cuentas de servicio → Crear cuenta de servicio**.
   Nombre: `subidor`. Dale a **Crear y continuar** y luego a **Listo** (los permisos
   que pide ahí no hacen falta).
5. Entra en la cuenta recién creada → pestaña **Claves** → **Agregar clave → Crear
   clave nueva → JSON**. Se te descarga un archivo.

Ese archivo **es una llave de tu Drive**. No lo subas a ningún sitio ni lo pegues en
un chat.

## Paso 2 — Darle la llave al Mac

```bash
cd ~/Content-Scheduler/clipper-web
mkdir -p drive/credenciales
mv ~/Downloads/EL-ARCHIVO-QUE-BAJASTE.json drive/credenciales/cuenta-de-servicio.json
chmod 600 drive/credenciales/cuenta-de-servicio.json
```

Esa carpeta está fuera del repositorio, así que no se sube a GitHub.

## Paso 3 — La carpeta de Drive

1. En tu Drive, crea una carpeta, por ejemplo **Clips**.
2. Ábrela y mira la barra de direcciones. El trozo final es el identificador:
   `https://drive.google.com/drive/folders/`**`1a2B3c4D5e6F7g8H9i`**
3. Comparte esa carpeta con el **correo de la cuenta de servicio** (sale en el panel
   de Google y también dentro del JSON, en `client_email`; acaba en
   `.iam.gserviceaccount.com`), con permiso de **Editor**.

Sin ese paso, Google responde 403 y no sube nada. Es el fallo más común.

## Paso 4 — Encenderlo

En el `.env`:

```bash
GOOGLE_DRIVE_FOLDER_ID=1a2B3c4D5e6F7g8H9i
COMPOSE_PROFILES=drive          # si ya tenías otros, sepáralos con comas
```

Y:

```bash
docker-compose up -d --build drive
docker-compose logs -f drive
```

Tiene que decir **"Vigilando /app/uploads/clips"**. A partir de ahí, cada clip nuevo
aparece en tu carpeta de Drive a los pocos segundos de salir del horno.

## Cómo quedan ordenados

Cada video tiene su propia carpeta dentro de la que elegiste, nombrada con la
fecha y el título:

```
Clips/
├── 2026-11-16 · La Mansión VIP - Gala 3/
│   ├── clip_1_0458-0538.mp4
│   ├── clip_2_0701-0745.mp4
│   └── clip_3_1019-1107.mp4
└── 2026-11-16 · Alofoke - El debate/
    └── clip_1_0912-0947.mp4
```

El nombre sale del propio motor, que guarda de qué video vino cada clip. Si por
lo que sea no lo sabe, el clip cae suelto en la carpeta principal en vez de
perderse.

Si prefieres todo junto, sin carpetas:

```bash
DRIVE_ORGANIZAR=false
```

## Si quieres que no ocupen el disco del Mac

```bash
DRIVE_BORRAR_LOCAL=true
```

Con eso, el clip se borra del Mac en cuanto está a salvo en Drive. **Ojo**: entonces
la app del iPhone ya no puede bajárselo del motor ni lo verás en el estudio, porque
el archivo ya no está. Déjalo apagado salvo que vayas justo de espacio.

## Qué hace por dentro

Mira la carpeta de clips cada quince segundos. Cuando ve uno nuevo espera a que deje
de crecer (para no subir un archivo a medio escribir), lo sube, y deja a su lado un
archivo `.drive` con el identificador. Ese testigo es como sabe lo que ya subió, así
que puedes reiniciar el Mac sin que se duplique nada.

Si no hay credenciales, el servicio se queda dormido y no molesta: el motor sigue
funcionando igual.

## Si algo falla

| Qué dice el registro | Qué pasa |
|---|---|
| `Drive dice 403` | La carpeta no está compartida con la cuenta de servicio, o no como Editor. |
| `Drive dice 404` | El identificador de la carpeta está mal. |
| `No encuentro el json` | El archivo no está en `drive/credenciales/cuenta-de-servicio.json`. |
| `Falta GOOGLE_DRIVE_FOLDER_ID` | Te falta esa línea en el `.env`. |
| No dice nada nunca | Todavía no has cortado ningún clip. |

## Esto y lo del iPhone

Son dos caminos distintos y pueden convivir:

- **Este**: el Mac sube todos los clips a tu Drive, siempre, sin tocar nada.
- **El del iPhone** (Ajustes → Google Drive): sube solo los que tú mandas a la cola.

Si enciendes este, puedes dejar el del iPhone apagado y el teléfono no gasta datos
ni espacio subiendo nada.
