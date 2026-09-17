# Referencia: variables de entorno y config

## Variables de entorno (build time)

Leídas por [`scripts/generate-config.js`](../../scripts/generate-config.js), solo en el momento del build (`npm run build`) — nunca en runtime del navegador.

| Variable | Requerida | Descripción |
|---|---|---|
| `SUPABASE_URL` | Sí | URL del proyecto Supabase (formato `https://<ref>.supabase.co`) |
| `SUPABASE_ANON_KEY` | Sí | Clave pública `anon`/`publishable` del proyecto — **nunca** la `service_role` |

Si falta alguna, el build no falla: `generate-config.js` escribe `config.js` igual, con string vacío en el campo faltante, y loguea una advertencia. El efecto visible es que el sitio deployado muestra "Config no disponible" en la pantalla de login en vez de intentar conectarse con credenciales incompletas.

En Netlify, se cargan en Site settings → Environment variables. En local, se exportan en la shell antes de correr `npm run build` (ver [Primer arranque en local](../tutorials/primer-arranque-local.md)).

## `config.js` (generado, no commiteado)

Archivo que `generate-config.js` escribe en la raíz del repo, cargado por `index.html` antes que el resto del script:

```js
// Generado automáticamente en build time por scripts/generate-config.js — no editar a mano.
window.CRM_COMUNIDADES_CONFIG = {
  SUPABASE_URL: "...",
  SUPABASE_ANON_KEY: "...",
};
```

Está en `.gitignore` — nunca debería aparecer en un commit. `index.html` lee `window.CRM_COMUNIDADES_CONFIG` para instanciar el cliente de Supabase con `db: { schema: 'crm_comunidades' }` (todas las queries del cliente apuntan a ese schema por default, nunca a `public`).

## Otros archivos de config

| Archivo | Propósito |
|---|---|
| [`netlify.toml`](../../netlify.toml) | `publish = "."`, `command = "npm run build"` |
| [`package.json`](../../package.json) | Un solo script (`build`), sin dependencias declaradas |
| `.gitignore` | Excluye `config.js`, `node_modules/`, `.env*`, `.netlify/` |
