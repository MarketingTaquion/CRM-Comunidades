# CRM de Comunidades

Panel interno de Taquión para el producto "Comunidades" — un sistema de registro único de comunidades, contactos y su nivel de identificación, reemplazando el patrón actual de planillas sueltas + ManyChat.

Este repo es el proyecto real (código deployable), hermano de [`pulso-ignite`](https://github.com/MarketingTaquion/Dashboard-Consumos-Ignite) e [`ignite-brief`](https://github.com/MarketingTaquion/Brief-Campana-Ignite). La spec y todo el research que originó este producto vive en `SDD-TAQUION/specs/006-crm-comunidades.md`, en el workspace local de planificación (no es un repo de GitHub) — ese documento es donde se decide qué construir; este repo es donde se construye.

## Estado actual (2026-09-18)

- **Frontend:** `index.html` — mockup interactivo del panel admin (HTML/CSS/JS estático, sin build, sin framework — mismo enfoque que `ignite-brief`). Todavía usa **datos de ejemplo hardcodeados**, no está conectado a Supabase.
- **Base de datos:** esquema de Postgres ya aplicado y verificado en un proyecto real de Supabase (`crm-comunidades`, org `Marketing-Taquion-IGNITE`) — ver [`db/001_init_crm_comunidades.sql`](db/001_init_crm_comunidades.sql). Documentación completa del modelo en el README original dentro de `SDD-TAQUION`.
- **Rol implementado:** solo `admin_taquion`. Los roles `am_estratega` y `cliente` están modelados en la base (RLS listo) pero sin login real — ver spec 006 para el detalle de qué queda en backlog.

## Estructura

```
index.html              → el panel (3 comunidades × 6 activos, selector de rol en vivo)
db/001_init_crm_comunidades.sql  → esquema completo de Postgres (schema crm_comunidades)
mockups/panel-admin-6-versiones.html → exploración visual previa (6 direcciones), superada por index.html, se conserva como referencia
```

## Qué falta para que esto sea una app real (no solo un mockup)

1. Conectar `index.html` a Supabase de verdad (cliente JS vía CDN, como hace `ignite-brief`) en vez de los objetos `COMUNIDADES`/`CONTENT` hardcodeados.
2. Cargar datos reales de las 3 comunidades (Todo un País, Cortado en Jarrito, Un Metro Cuadrado) en vez de datos de ejemplo.
3. El webhook de ManyChat → esta base (hoy ManyChat solo escribe a Google Sheets).
4. El job que recalcula `nivel_activacion` y `semanas_consecutivas_activo` semanalmente.
5. Las funciones/endpoints que arman los exports de Nivel 1/2 y el push de Nivel 3, escribiendo en `exportacion_log`.

## Deploy

**Live: https://crm-comunidades-taquion.netlify.app** — proyecto `crm-comunidades-taquion` en Netlify, team `Marketing-Taquion-IGNITE`, deploy automático desde `master` de este repo. Sitio estático, sin build step (`netlify.toml` con `publish = "."`), sin variables de entorno todavía porque no hay conexión real a Supabase. Cuando se conecte Supabase (paso 1 de arriba), sumar `SUPABASE_URL` / `SUPABASE_ANON_KEY` como variables de entorno del sitio, igual que en `ignite-brief`.
