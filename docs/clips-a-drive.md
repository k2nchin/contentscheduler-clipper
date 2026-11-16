# Que los clips suban solos a tu Google Drive

El Mac sube cada clip a tu Drive en cuanto lo termina, sin que el iPhone tenga
que estar encendido ni abierto. Son unos minutos de preparación, una sola vez.

## Por qué con tu cuenta y no con una «cuenta de servicio»

Es la trampa de Google en la que cae todo el mundo: una cuenta de servicio
parece lo correcto para un programa que trabaja solo, pero **no tiene espacio
de almacenamiento propio**. Puede crear carpetas, porque no ocupan nada, y
falla al guardar el primer archivo:

> Service Accounts do not have storage quota.

Así que el subidor usa **tu** cuenta: los clips son tuyos, ocupan tu espacio y
los ves donde esperas. Autorizas una vez y el permiso dura.

## Paso 1 — Un cliente de OAuth

1. Entra en **[console.cloud.google.com](https://console.cloud.google.com)** y elige
   un proyecto (o crea uno).
2. Busca **"Google Drive API"** y dale a **Habilitar**.
3. **APIs y servicios → Credenciales → Crear credenciales →
   ID de cliente de OAuth → Aplicación de escritorio** → Crear.
4. Descarga el json y guárdalo aquí:

```bash
cd ~/Content-Scheduler/clipper-web
mkdir -p drive/credenciales
mv "$(ls -t ~/Downloads/client_secret*.json | head -1)" drive/credenciales/cliente-oauth.json
chmod 600 drive/credenciales/cliente-oauth.json
```

Si el proyecto está **en pruebas**, añádete como usuario de prueba en
**Pantalla de consentimiento de OAuth → Usuarios de prueba**, o Google te
denegará el acceso.

## Paso 2 — Autorizar

```bash
python3 drive/autorizar.py
```

Se abre el navegador. Entras con la cuenta donde quieres los clips y das a
**Permitir**. Si avisa de que la app no está verificada:
**Configuración avanzada → Ir a … (no seguro)**. Sale porque la app es tuya y
no ha pasado la revisión de Google, que solo hace falta para publicarla.

Al terminar deja `drive/credenciales/usuario.json`. Ese archivo **es una llave
de tu Drive**: no lo subas a ningún sitio ni lo pegues en un chat.

## Paso 3 — La carpeta: no hay que hacer nada

El subidor crea en tu Drive una carpeta llamada **Content Scheduler** y trabaja
ahí dentro. No tienes que crearla ni compartirla.

Es a propósito. El permiso que le diste es el más estrecho que ofrece Google,
`drive.file`: la app **solo ve lo que ella misma crea**, y no puede leer ni
tocar el resto de tu Drive. El precio es que tampoco puede escribir dentro de
una carpeta que hiciste tú a mano — si le indicas una, Google responde
`insufficientParentPermissions`.

Si quieres otro nombre: `DRIVE_CARPETA=Mis clips` en el `.env`.

Y si de verdad necesitas que vaya a una carpeta concreta que ya existe, mueve
la que crea la app a donde quieras desde el propio Drive: seguirá siendo suya y
funcionando.

## Paso 4 — Encenderlo

En el `.env`:

```bash
COMPOSE_PROFILES=drive          # si ya tenías otros, sepáralos con comas
```

Y:

```bash
docker-compose up -d --build drive
docker-compose logs -f drive
```

Tiene que decir **"Subiendo con tu cuenta de Google"** y **"Vigilando
/app/uploads/clips"**. A partir de ahí, cada clip nuevo aparece en tu carpeta a
los pocos segundos de salir del horno.

## Cómo quedan ordenados

Cada video tiene su propia carpeta dentro de la que elegiste, con la fecha y el
título:

```
Clips/
├── 2026-11-16 · La Mansión VIP - Gala 3/
│   ├── clip_1_0458-0538.mp4
│   ├── clip_2_0701-0745.mp4
│   └── clip_3_1019-1107.mp4
└── 2026-11-16 · Alofoke - El debate/
    └── clip_1_0912-0947.mp4
```

El nombre sale del propio motor, que guarda de qué video vino cada clip. Si no
lo sabe, el clip cae suelto en la carpeta principal en vez de perderse.

Si prefieres todo junto, sin carpetas: `DRIVE_ORGANIZAR=false`.

## Si quieres que no ocupen el disco del Mac

```bash
DRIVE_BORRAR_LOCAL=true
```

El clip se borra del Mac en cuanto está a salvo en Drive. **Ojo**: entonces la
app del iPhone ya no puede bajárselo del motor ni lo verás en el estudio,
porque el archivo deja de existir ahí. Déjalo apagado salvo que vayas justo de
espacio.

## Qué hace por dentro

Mira la carpeta de clips cada quince segundos. Cuando ve uno nuevo espera a que
deje de crecer (para no subir un archivo a medio escribir), lo sube, y deja a su
lado un archivo `.drive` con el identificador. Ese testigo es como sabe lo que
ya subió, así que puedes reiniciar el Mac sin que se duplique nada.

Sin credenciales, el servicio se queda dormido: el motor sigue funcionando igual.

## Si algo falla

| Qué dice el registro | Qué pasa |
|---|---|
| `storageQuotaExceeded` | Estás usando una cuenta de servicio. Autoriza la tuya: `python3 drive/autorizar.py` |
| `insufficientParentPermissions` | Le indicaste una carpeta que no creó la app. Quita `GOOGLE_DRIVE_FOLDER_ID` del .env |
| `Drive dice 404` | El identificador de la carpeta está mal, o es de otra cuenta |
| `El permiso de tu cuenta no sirve` | Caducó o lo revocaste. Vuelve a autorizar |
| No dice nada nunca | Todavía no has cortado ningún clip |

## Esto y lo del iPhone

Son dos caminos distintos y pueden convivir:

- **Este**: el Mac sube todos los clips, siempre, sin tocar nada.
- **El del iPhone** (Ajustes → Google Drive): sube solo los que mandas a la cola.

Si enciendes este, puedes dejar el del iPhone apagado y el teléfono no gasta
datos ni espacio subiendo nada.
