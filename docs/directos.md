# Clipear un directo mientras sigue en vivo

El motor rechaza los enlaces de directos, y con razón: para elegir los mejores
momentos necesita el video entero transcrito, y un directo no ha terminado.

Esto lo resuelve partiéndolo. El Mac graba el directo sin parar y, cada vez que
se cierra un trozo, lo manda a clipear. Mientras el streamer sigue hablando, tú
ya tienes los clips de hace unos minutos.

## Usarlo

```bash
cd clipper-web
./scripts/directo.sh https://www.youtube.com/watch?v=...
```

Funciona con YouTube, Twitch y Kick. **Ctrl+C** para parar: lo grabado se queda
y el último trozo también se manda a clipear.

Los clips van saliendo en `http://localhost:3200` y en el iPhone, trozo a trozo.
El primero tarda lo que dure un trozo, diez minutos por defecto.

## Cada cuánto quieres clips

```bash
MINUTOS_POR_TROZO=5 ./scripts/directo.sh <enlace>
```

Más corto, clips antes; pero la IA ve menos contexto para elegir, y un momento
bueno que caiga justo en el corte se parte en dos. Entre cinco y diez minutos
es el punto razonable. Por debajo de dos no deja.

## Cuánto ocupa

Graba a 720p sin recodificar, así que va ligero de procesador pero sí gasta
disco: calcula alrededor de un giga por hora. Los trozos se quedan en la carpeta
de subidas del motor; bórralos cuando acabes si vas justo de espacio.

```bash
ALTURA_MAXIMA=480 ./scripts/directo.sh <enlace>   # la mitad de disco
```

## Cómo quieres los clips

Los ajustes van en json, los mismos nombres que usa la app:

```bash
OPCIONES_JSON='{"processing_mode":"fast","clip_length":"short"}' \
  ./scripts/directo.sh <enlace>
```

## Esto y lo del chat

Son dos formas de atacar lo mismo y se complementan:

- **Esto** corta solo, por lo que dice la IA del contenido.
- **Clipper → YouTube en vivo**, en la app, vigila el chat y te marca los
  momentos en que explota. El chat suele ser mejor detector de un momento
  viral que cualquier IA, porque la gente reacciona cuando pasa algo bueno.

Lo ideal es tener los dos abiertos: el Mac cortando por su cuenta y tú mirando
dónde se alborota el chat.

## Si algo falla

| Qué pasa | Qué mirar |
|---|---|
| «No pude sacar la clave» | Hazla a mano y añádela al .env como `CLIP_API_KEY=sk_…` |
| No aparece ningún trozo | El directo puede estar restringido. Pruébalo con `yt-dlp <enlace>` |
| Los clips salen vacíos | El trozo no tenía voz clara (música, pantalla en negro) |
| Se llena el disco | Baja `ALTURA_MAXIMA` o borra los trozos antiguos |
