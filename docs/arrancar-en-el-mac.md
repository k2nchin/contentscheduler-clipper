# Arrancar el motor en el Mac

## Lo rápido

```bash
cd clipper-web && ./scripts/arrancar-mac.sh
```

Instala Docker si falta, instala y enciende Ollama, baja el modelo, deja el `.env`
configurado **sin ninguna clave de pago** y levanta todo. Si Docker no estaba, te pide
abrirlo una vez y repetir el comando (macOS exige ese permiso a mano).

Al terminar tienes la web en `http://localhost:3001` y la API en `http://localhost:8000/docs`.
Créate la cuenta en la web y saca una clave en **Ajustes → Claves de API**: esa `sk_…` es la
que va en el iPhone.

## Instalar Docker a mano

```bash
brew install --cask docker
open -a Docker          # la primera vez pide permiso de administrador
```

Si no tienes Homebrew:

```bash
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
```

## Las dos piezas que el motor necesita

Para clipear hacen falta dos cosas: **transcribir** el audio y **elegir** los momentos.
Cada una se puede hacer gratis en tu Mac o pagando en la nube.

| | Gratis, en tu Mac | De pago, en la nube |
|---|---|---|
| Transcribir | Whisper (`TRANSCRIPTION_PROVIDER=whisper`) | AssemblyAI (`ASSEMBLY_AI_API_KEY`) |
| Elegir momentos | Ollama (`LLM=ollama:gpt-oss:20b`) | Gemini, OpenAI o Claude |

El script deja puesta la columna gratis.

### Lo que cuesta ir gratis

**Es más lento, y bastante.** Whisper dentro de Docker corre en el procesador, porque un
contenedor no puede usar la GPU del Mac. Transcribir un stream largo puede llevar un buen
rato; para videos de diez o veinte minutos se nota poco, para uno de cuatro horas se nota
mucho. El modelo local también acierta algo menos que Gemini eligiendo qué momento vale.

Si el Mac es un Apple Silicon con memoria de sobra, va bien. Si es un Intel viejo, mejor
las claves de pago.

### Pasarse a las de pago

Las dos tienen capa gratis de entrada, así que probar no cuesta nada:

**AssemblyAI** — [assemblyai.com](https://www.assemblyai.com) → crear cuenta → la clave está
en el panel nada más entrar. En el `.env`:

```bash
TRANSCRIPTION_PROVIDER=assemblyai
ASSEMBLY_AI_API_KEY=la_clave
```

**Gemini** (el más barato de los tres) — [aistudio.google.com/apikey](https://aistudio.google.com/apikey)
→ *Create API key*. En el `.env`:

```bash
LLM=google-gla:gemini-3-flash-preview
GOOGLE_API_KEY=la_clave
```

Si prefieres OpenAI o Claude: `LLM=openai:gpt-5.2` con `OPENAI_API_KEY`, o
`LLM=anthropic:claude-sonnet-5-5` con `ANTHROPIC_API_KEY`.

Después de tocar el `.env`:

```bash
docker-compose up -d --force-recreate backend worker
```

Las claves viven solo en ese `.env`, que no se sube al repositorio. No las pegues en ningún
chat.

## Mezclar

Se puede. Lo más equilibrado suele ser **AssemblyAI para transcribir** (es lo lento) y
**Ollama para elegir** (es lo barato de hacer en local). Cada fila de la tabla es
independiente.

## Si algo falla

| Qué pasa | Qué mirar |
|---|---|
| La API no levanta | `docker-compose logs --tail 40 backend` |
| Un video falla siempre | `docker-compose logs -f worker`, que es quien lo procesa |
| «Ollama no responde» | `brew services start ollama`, y prueba `curl localhost:11434/api/version` |
| Todo va lentísimo | Es Whisper en el procesador: pásate a AssemblyAI |
| Se llenó el disco | `docker system prune -a` y revisa `TEMP_DIR` |

Para usarlo desde fuera de casa: [`tunel-cloudflare.md`](tunel-cloudflare.md).
