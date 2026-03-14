# voice-conscience

Escucha una conversación en tiempo real, detecta oraciones y genera respuestas ultraconcisas con un LLM. Pensado para reuniones de negocios y tecnología: actúa como la "voz de la conciencia" del equipo.

```
micrófono → VAD (cliente) → WebM blob → Whisper STT → asyncio.Queue → LLM → tarjeta con respuesta
```

Cada oración detectada aparece como una tarjeta independiente. El estado de cada tarjeta evoluciona de forma asincrónica: **en cola → procesando → respuesta**.

---

## Arquitectura

```
voice-conscience/
├── docker-compose.yml          # backend + Ollama con un comando
├── .env.example                # variables de entorno
├── services/
│   └── backend/                # FastAPI + faster-whisper + Ollama/OpenAI
│       ├── main.py
│       ├── requirements.txt
│       └── Dockerfile
└── apps/
    └── mobile/                 # Expo React Native (web / iOS / Android)
        ├── app/index.tsx       # UI principal
        ├── hooks/
        │   ├── useAudioRecorder.ts   # captura de audio + VAD cliente
        │   └── useVoiceSocket.ts     # WebSocket con reconexión automática
        └── config.ts           # HOST y PORT del backend
```

### Pipeline de audio

1. **VAD cliente** — `AudioContext` + `AnalyserNode` detecta voz en el navegador (umbral configurable, escala 0–255).
2. **Grabación** — `MediaRecorder` sin timeslice graba toda la oración en memoria. Al detectar silencio (~1.2 s) para la grabación y ensambla un `Blob` WebM completo y válido.
3. **Envío** — el blob se envía como frame binario WebSocket; luego se envía el texto `"flush"` para señalizar al servidor que procese.
4. **Transcripción** — el backend recibe el blob, lo transcribe con Whisper (`vad_filter=True`).
5. **Cola LLM** — si el texto tiene ≥ 2 palabras, se encola. Un worker asíncrono lo envía al LLM y devuelve la respuesta.
6. **UI** — cada oración aparece como tarjeta; el estado se actualiza en tiempo real sin bloquear nuevas oraciones.

### Mensajes WebSocket

| Dirección | Tipo | Campos | Descripción |
|-----------|------|--------|-------------|
| cliente → servidor | binario | — | Blob de audio WebM |
| cliente → servidor | texto | `"flush"` | Señal de fin de oración |
| servidor → cliente | `transcription` | `text` | Texto transcripto |
| servidor → cliente | `queued` | `text`, `position` | Oración encolada |
| servidor → cliente | `processing` | `text` | LLM procesando |
| servidor → cliente | `response` | `input`, `output` | Respuesta del LLM |
| servidor → cliente | `status` | `queue_size` | Profundidad de cola |
| servidor → cliente | `error` | `msg` | Error de transcripción o LLM |

---

## Inicio rápido con Docker

### Requisitos

- [Docker](https://docs.docker.com/get-docker/) ≥ 24 con Compose v2
- `ffmpeg` disponible en el contenedor (incluido en el Dockerfile)

### 1. Variables de entorno

```bash
cp .env.example .env
# editar .env si querés cambiar modelo, puerto, idioma, etc.
```

### 2. Levantar backend + Ollama

```bash
docker compose up --build
```

| Servicio | Puerto | Descripción |
|----------|--------|-------------|
| `ollama` | 11434 (interno) | LLM local |
| `ollama-init` | — | descarga el modelo al primer arranque |
| `backend` | **8000** (o `BACKEND_PORT`) | FastAPI + Whisper |

El primer arranque descarga los pesos de Whisper (~150 MB para `base`) y el modelo de Ollama (~2 GB para `llama3.2:3b`). Los arranques siguientes son instantáneos gracias a los volúmenes Docker.

Verificar que el backend esté listo:

```bash
curl http://localhost:8000/config
```

### 3. Configurar la app móvil

Editá `apps/mobile/config.ts` y poné la IP de tu máquina en la red local:

```ts
const HOST = '192.168.0.x'   // ip de la máquina donde corre Docker
const PORT = 8000             // debe coincidir con BACKEND_PORT en .env
```

Para obtener la IP:

```bash
ip route get 1.1.1.1 | awk '{print $7}'
```

### 4. Levantar la app

```bash
cd apps/mobile
npm install
npx expo start --web   # abre en navegador
# o escaneá el QR con Expo Go para iOS/Android
```

### 5. Parar

```bash
docker compose down
```

---

## Ejecución sin Docker (desarrollo)

### Backend

```bash
sudo apt install ffmpeg

cd services/backend
python -m venv .venv && source .venv/bin/activate
pip install -r requirements.txt

LLM_PROVIDER=ollama \
OLLAMA_URL=http://localhost:11434 \
OLLAMA_MODEL=llama3.2:3b \
WHISPER_MODEL=base \
LANGUAGE=es \
uvicorn main:app --host 0.0.0.0 --port 8000 --reload
```

### Ollama local

```bash
curl -fsSL https://ollama.com/install.sh | sh
ollama pull llama3.2:3b
ollama serve
```

---

## Variables de entorno

| Variable | Default | Descripción |
|----------|---------|-------------|
| `BACKEND_PORT` | `8000` | Puerto expuesto del backend |
| `LLM_PROVIDER` | `ollama` | `ollama` o `openai` |
| `OLLAMA_URL` | `http://ollama:11434` | URL de Ollama (dentro de Docker usa el nombre del servicio) |
| `OLLAMA_MODEL` | `llama3.2:3b` | Cualquier modelo disponible en Ollama |
| `OPENAI_API_KEY` | — | Requerido si `LLM_PROVIDER=openai` |
| `OPENAI_MODEL` | `gpt-4o-mini` | Modelo de OpenAI |
| `WHISPER_MODEL` | `base` | `tiny` \| `base` \| `small` \| `medium` |
| `LANGUAGE` | `es` | `es` \| `en` \| `auto` |
| `SILENCE_TIMEOUT` | `2.5` | Segundos de silencio antes de forzar flush (fallback servidor) |
| `SILENCE_DB` | `-35` | Umbral de volumen para VAD servidor (dB, no usado en flujo web) |

---

## Parámetros de ajuste (cliente)

En `apps/mobile/hooks/useAudioRecorder.ts`:

| Constante | Default | Efecto |
|-----------|---------|--------|
| `VOICE_THRESHOLD` | `14` | Sensibilidad del VAD (escala 0–255). Subir si capta ruido ambiente. |
| `SILENCE_MS` | `1200` | ms de silencio tras la voz antes de cerrar la oración. Subir si corta frases largas. |

---

## GPU NVIDIA (opcional)

Descomenta las líneas `deploy:` en el servicio `ollama` dentro de `docker-compose.yml`:

```yaml
deploy:
  resources:
    reservations:
      devices:
        - driver: nvidia
          count: all
          capabilities: [gpu]
```

---

## Cambiar al LLM de OpenAI

```bash
# en .env
LLM_PROVIDER=openai
OPENAI_API_KEY=sk-...
OPENAI_MODEL=gpt-4o-mini
```

Con OpenAI no se necesita el servicio `ollama`. Se puede levantar solo el backend:

```bash
docker compose up --build backend
```

---

## Stack

| Capa | Tecnología |
|------|-----------|
| App | Expo / React Native (web + iOS + Android) |
| Audio | Web Audio API, MediaRecorder |
| WebSocket | nativo del navegador / React Native |
| Backend | FastAPI + Uvicorn |
| STT | faster-whisper (CPU int8) |
| LLM | Ollama (`llama3.2:3b`) o OpenAI |
| VAD audio | ffmpeg `volumedetect` (servidor), AudioContext (cliente) |
| Infraestructura | Docker Compose |
