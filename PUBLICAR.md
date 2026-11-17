# Publicar el Clipper para el público

El botón «✂️ Abrir Clipper» de contentscheduler.vercel.app apunta a
`https://contentscheduler-clipper.vercel.app`. Si usas otro nombre, cámbialo en `docs/index.html`.

## 1. Base de datos y Redis
- **Postgres**: Neon o Supabase (gratis). Ejecuta `init.sql` y luego, en `frontend/`,
  `DATABASE_URL=... npx prisma migrate deploy`.
- **Redis**: Upstash (gratis) o el Redis de Railway.

## 2. Backend (Python + procesamiento de video) — Railway o Render
1. Nuevo proyecto → desde GitHub → `k2nchin/contentscheduler-clipper`, **Root Directory** `backend`
   (usa su Dockerfile).
2. Crea dos servicios con la misma imagen: la **API** y el **worker** (en Render ya hay ejemplo en
   `deploy/render-worker/`).
3. Variables: copia las de `clipper-web/.env.example` (DATABASE_URL, REDIS_*, claves de IA,
   `BACKEND_CPU_ONLY=true`, etc.).
4. Anota la URL pública de la API.

## 3. Frontend — Vercel
1. Vercel → **Add New → Project** → `k2nchin/contentscheduler-clipper`.
2. **Project Name** `contentscheduler-clipper`, **Root Directory** `frontend`.
3. Variables: `DATABASE_URL`, la URL del backend, `BETTER_AUTH_SECRET`/auth y las `NEXT_PUBLIC_*`
   que uses (ver `.env.example`).
4. Deploy. Tu sitio actual no se toca: es otro proyecto.

## Obligación de la AGPL (no la quites)
- Mantén `clipper-web/LICENSE`.
- El pie de la web enlaza al código fuente (`frontend/src/lib/site.ts → GITHUB_URL`).
  El repo público https://github.com/k2nchin/contentscheduler-clipper debe estar y actualizado con lo que corre en producción.
