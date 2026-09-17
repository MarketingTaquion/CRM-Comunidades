# CRM de Comunidades

Panel interno de Taquión para el producto "Comunidades" — un sistema de registro único de comunidades, contactos y su nivel de identificación, reemplazando el patrón actual de planillas sueltas + ManyChat.

Este repo es el proyecto real (código deployable), hermano de [`pulso-ignite`](https://github.com/MarketingTaquion/Dashboard-Consumos-Ignite) e [`ignite-brief`](https://github.com/MarketingTaquion/Brief-Campana-Ignite). La spec y todo el research que originó este producto vive en `SDD-TAQUION/specs/006-crm-comunidades.md`, en el workspace local de planificación (no es un repo de GitHub) — ese documento es donde se decide qué construir; este repo es donde se construye.

## Estado actual (2026-09-18)

- **Frontend:** `index.html` — panel admin interactivo (HTML/CSS/JS estático, sin build, sin framework — mismo enfoque que `ignite-brief`). Conectado a Supabase de verdad (ver sección más abajo), no a datos de ejemplo hardcodeados.
- **Base de datos:** esquema de Postgres ya aplicado y verificado en un proyecto real de Supabase (`crm-comunidades`, org `Marketing-Taquion-IGNITE`) — ver [`db/001_init_crm_comunidades.sql`](db/001_init_crm_comunidades.sql). Documentación completa del modelo en el README original dentro de `SDD-TAQUION`.
- **Rol implementado:** solo `admin_taquion`. Los roles `am_estratega` y `cliente` están modelados en la base (RLS listo) pero sin login real — ver spec 006 para el detalle de qué queda en backlog.

## Documentación

Guías de uso, referencia técnica y el porqué de las decisiones de arquitectura y seguridad viven en [`docs/`](docs/index.md), organizadas con [Diátaxis](https://diataxis.fr/). Puntos de entrada típicos:

- Nunca usaste este repo → [Primer arranque en local](docs/tutorials/primer-arranque-local.md)
- Necesitás hacer algo puntual (deployar, agregar una comunidad, dar de alta un admin) → [`docs/how-to/`](docs/how-to/)
- Necesitás un dato exacto del esquema o la config → [`docs/reference/`](docs/reference/)
- Alguien no puede loguearse o ves "permission denied for schema" → [Diagnosticar problemas de acceso](docs/how-to/diagnosticar-problemas-de-acceso.md)

## Qué falta (backlog activo)

1. El webhook de ManyChat → esta base (hoy ManyChat solo escribe a Google Sheets).
2. El job que recalcula `nivel_activacion` y `semanas_consecutivas_activo` semanalmente.
3. Los endpoints que arman los exports de Nivel 2/3 (Nivel 1 ya funciona), escribiendo en `exportacion_log`.
4. Login real y RLS activo para los roles `am_estratega`/`cliente` (hoy solo `admin_taquion` tiene login).

## Deploy

**Live: https://crm-comunidades-taquion.netlify.app** — proyecto `crm-comunidades-taquion` en Netlify, team `Marketing-Taquion-IGNITE`, deploy automático desde `master` de este repo. Build step mínimo (`npm run build` → `node scripts/generate-config.js`) que genera `config.js` desde las env vars `SUPABASE_URL` / `SUPABASE_ANON_KEY` ya cargadas en el sitio — mismo patrón que `ignite-brief`.

## Conectado a Supabase de verdad (2026-09-18)

- **Login real:** Supabase Auth, email/password. Un solo usuario admin creado por invitación (`marketing@taquion.com.ar`) y vinculado a `admin_taquion` en `usuario_comunidad`. Sin esto, las consultas hubieran vuelto vacías siempre — RLS ya exige `auth.uid()` real.
- **Requisitos de Supabase que no son obvios y hay que recordar si se resetea el proyecto:** exponer el schema en Data API y aplicar los GRANTs de schema/tabla — ninguno de los dos pasos es automático para un schema propio. Detalle completo en [Seguridad: RLS, GRANTs y visibilidad de Netlify](docs/explanation/seguridad-rls-grants-y-netlify.md).
- **Conectado con datos reales:** comunidades (`comunidad` + `comunidad_activo`), funnel de Crecimiento (agregado real de `contacto.estado_identificacion`), tabla de Relación (`contacto` + join a `arquetipo`), Mapa de Voces (vista `mapa_de_voces`), export Nivel 1 (CSV real desde `export_nivel1_agregado`).
- **Deliberadamente sin conectar:** Conocimiento y Voz (sentiment, piezas publicadas, brecha semántica) — no hay tabla que los respalde todavía, así que la UI lo dice explícitamente en vez de simular esos números. CPME/CPMR/TRG/K-Factor en Crecimiento — requieren datos de inversión en pauta que tampoco están cargados. Export Nivel 2/3 — botones deshabilitados, sin endpoint construido.
- Datos semilla cargados: las 3 comunidades piloto/demo con sus activos habilitados según etapa, arquetipos de Un Metro Cuadrado y Cortado en Jarrito (con la exclusión C2/C3 explícita), y un puñado de contactos de ejemplo por comunidad para que Crecimiento/Relación/Mapa de Voces no arranquen en cero.

## Overview y métricas de performance (2026-09-17)

Pestaña nueva `Overview` (landing por default al loguearse): desglose real por barrio/corredor y por arquetipo, más 3 métricas de performance por comunidad — engagement (real, sobre `nivel_activacion`), tasa de abandono y tasa de referidos (mecanismos nuevos, arrancan en 0% hasta que se carguen `contacto.fecha_baja` / `contacto.referido_por_contacto_id`, nunca se infieren). Esquema en [`db/002_overview_metricas.sql`](db/002_overview_metricas.sql). Detalle en [Modelo de identificación y gobernanza de exportación](docs/explanation/modelo-de-identificacion-y-gobernanza-de-exportacion.md#overview-y-métricas-de-performance) y en [Esquema de base de datos](docs/reference/esquema-de-base-de-datos.md).

Próximos frentes acordados (en este orden): API pública (exponiendo la REST API de Supabase con API keys propias) y sección de Reportes (manuales + programación de automáticos, disponibles en el panel).
