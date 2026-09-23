# CRM de Comunidades

Panel interno de Taquión para el producto "Comunidades" — un sistema de registro único de comunidades, contactos y su nivel de identificación, reemplazando el patrón actual de planillas sueltas + ManyChat.

**Pivot de producto (2026-09-23):** el foco pasa a **tratamiento de leads a nivel operacional** (no "loyalty"/comunidad completa) — Overview (el embudo de identificación) y Activaciones (acciones nativas de WhatsApp: entrevistas indagatorias, promociones, anuncios de lanzamiento) son las dos secciones centrales. Conocimiento y Voz salen del panel — esa superficie la construye otro sector de Taquión (Insights/Inspire). Detalle completo en [`specs/2026-09-23-pivot-leads-whatsapp.md`](specs/2026-09-23-pivot-leads-whatsapp.md).

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

0. **Deployar el gateway de la API pública** (`supabase functions deploy api-publica`) y correr `db/005_api_publica.sql` contra el proyecto real — el código ya está escrito (2026-09-19, ver sección abajo) pero todavía no se aplicó ni se probó contra Supabase de verdad.
1. El webhook de ManyChat → esta base (hoy ManyChat solo escribe a Google Sheets) — auditado 2026-09-18, confirmado que no existe todavía (ni webhook ni importación real), ver [Ingesta de datos: por qué el circuito UTM/ManyChat todavía no existe](docs/explanation/ingesta-de-datos-y-circuito-utm.md).
2. El job que recalcula `nivel_activacion` y `semanas_consecutivas_activo` semanalmente.
3. Los endpoints que arman los exports de Nivel 2/3 (Nivel 1 ya funciona), escribiendo en `exportacion_log`.
4. Login real y RLS activo para los roles `am_estratega`/`cliente` (hoy solo `admin_taquion` tiene login).
5. Disparo de campañas del CRM hacia ManyChat (aplicar tag a un segmento para el activo Activaciones) — código escrito en el pivot 2026-09-23 (`db/006_activaciones_whatsapp.sql` + `supabase/functions/activacion-manychat/`), rompe el patrón 100% estático a propósito. Falta: deployar la función, cargar la API key de ManyChat como secret, y poblar `contacto.manychat_subscriber_id` de al menos un contacto real para poder probarlo de punta a punta.
6. Cargar la primera fila de `temporada` (fecha real de inicio) por comunidad — sin eso, `informe_decision_insumo` devuelve 0 filas (ver Esquema de base de datos).

## Deploy

**Live: https://crm-comunidades-taquion.netlify.app** — proyecto `crm-comunidades-taquion` en Netlify, team `Marketing-Taquion-IGNITE`, deploy automático desde `master` de este repo. Build step mínimo (`npm run build` → `node scripts/generate-config.js`) que genera `config.js` desde las env vars `SUPABASE_URL` / `SUPABASE_ANON_KEY` ya cargadas en el sitio — mismo patrón que `ignite-brief`.

## Conectado a Supabase de verdad (2026-09-18)

- **Login real:** Supabase Auth, email/password. Un solo usuario admin creado por invitación (`marketing@taquion.com.ar`) y vinculado a `admin_taquion` en `usuario_comunidad`. Sin esto, las consultas hubieran vuelto vacías siempre — RLS ya exige `auth.uid()` real.
- **Requisitos de Supabase que no son obvios y hay que recordar si se resetea el proyecto:** exponer el schema en Data API y aplicar los GRANTs de schema/tabla — ninguno de los dos pasos es automático para un schema propio. Detalle completo en [Seguridad: RLS, GRANTs y visibilidad de Netlify](docs/explanation/seguridad-rls-grants-y-netlify.md).
- **Conectado con datos reales:** comunidades (`comunidad` + `comunidad_activo`), funnel de Crecimiento (agregado real de `contacto.estado_identificacion`), tabla de Relación (`contacto` + join a `arquetipo`), Mapa de Voces (vista `mapa_de_voces`), export Nivel 1 (CSV real desde `export_nivel1_agregado`), Activaciones (tabla real `activacion`, ver abajo).
- **Contenido de ejemplo (no conectado a una fuente real):** los KPIs CPME/CPMR/TRG/K-Factor de Crecimiento, y la bitácora de Decisiones — no hay tabla que los respalde todavía (Decisiones sí tiene ya `informe_decision`/`informe_decision_insumo` construidos, ver abajo, pero la UI todavía muestra la bitácora de ejemplo, no está cableada). Muestran contenido hardcodeado marcado explícitamente como "Contenido de ejemplo" en vez de fabricar un número real (ver [Modelo de identificación y gobernanza de exportación](docs/explanation/modelo-de-identificacion-y-gobernanza-de-exportacion.md)). Export Nivel 2/3 — botones deshabilitados, sin endpoint construido.
- **Fuera del panel desde el pivot 2026-09-23:** Conocimiento y Voz — el enum `activo_tipo` los conserva a nivel de base (otro sector puede seguir usándolos), pero ya no se navegan desde acá. Pendiente de auditoría futura evaluar si se eliminan del enum — ver [`specs/2026-09-23-pivot-leads-whatsapp.md`](specs/2026-09-23-pivot-leads-whatsapp.md).
- Datos semilla cargados: las 2 comunidades piloto/demo (Todo un País, Cortado en Jarrito) con sus activos habilitados según etapa, arquetipos de Cortado en Jarrito (con la exclusión C2/C3 explícita), y un puñado de contactos de ejemplo por comunidad para que Crecimiento/Relación/Mapa de Voces no arranquen en cero. ("Un Metro Cuadrado" era el nombre viejo de Cortado en Jarrito, cargado por error como comunidad aparte — se eliminó el 2026-09-17.)

## Overview y métricas de performance (2026-09-17)

Pestaña nueva `Overview` (landing por default al loguearse): desglose real por barrio/corredor y por arquetipo, más 3 métricas de performance por comunidad — engagement (real, sobre `nivel_activacion`), tasa de abandono y tasa de referidos (mecanismos nuevos vía `contacto.fecha_baja` / `contacto.referido_por_contacto_id`, nunca se infieren). Esquema en [`db/002_overview_metricas.sql`](db/002_overview_metricas.sql). Detalle en [Modelo de identificación y gobernanza de exportación](docs/explanation/modelo-de-identificacion-y-gobernanza-de-exportacion.md#overview-y-métricas-de-performance) y en [Esquema de base de datos](docs/reference/esquema-de-base-de-datos.md). Se cargó un puñado de contactos de ejemplo con baja/referido para que las 2 comunidades muestren tasas reales (no 0%) en la demo (2026-09-17).

## Activaciones e Informe de Decisión Ejecutiva (2026-09-18)

- **Activaciones (activo 5)** pasó de contenido de ejemplo hardcodeado a la tabla real `crm_comunidades.activacion` — nombre, tipo (sponsor/anunciante vs. marca contratante), brief, fechas, `kpi_objetivo`/`kpi_resultado` (jsonb), estado, responsable. Deliberadamente sin ninguna FK a `contacto`/`evento_journey` (Crecimiento) — ver [Modelo de identificación y gobernanza de exportación](docs/explanation/modelo-de-identificacion-y-gobernanza-de-exportacion.md#activaciones-activo-5-por-qué-no-toca-crecimiento). El panel ya lee de la tabla real; como todavía no hay ninguna activación cargada, muestra un estado vacío real, no ejemplos.
- **Insumo del Informe de Decisión Ejecutiva** (activo 6): vista `informe_decision_insumo` — 100% automática, agrega lo cuantitativo ya instrumentado (foto acumulada al cierre de temporada + actividad ocurrida en la temporada) — separada de la tabla `informe_decision`, que es donde se escribe a mano el semáforo/aprendizajes/plan de acción, tal como exige el playbook de producto ("Decisiones es la única vista que no se completa con datos en vivo"). Requiere una tabla nueva, `temporada`, para poder acotar por fechas — arranca vacía para las comunidades existentes (no hay fecha de inicio real que migrar). Esquema en [`db/004_informe_decision_insumo.sql`](db/004_informe_decision_insumo.sql), detalle en [Modelo de identificación y gobernanza de exportación](docs/explanation/modelo-de-identificacion-y-gobernanza-de-exportacion.md#informe-de-decisión-ejecutiva-insumo-automático-vs-informe-escrito-a-mano).
- Specs cortas de ambas tareas (más la auditoría del circuito UTM/ManyChat) en [`specs/`](specs/).

Próximos frentes acordados (en este orden): API pública (exponiendo la REST API de Supabase con API keys propias) y sección de Reportes (manuales + programación de automáticos, disponibles en el panel).

## API pública — Fase 1 (2026-09-19, código escrito, deploy pendiente)

- **Alcance:** solo lectura, solo Nivel 1 — `comunidad(id, etapa)` y `export_nivel1_agregado`. Nunca `contacto` ni `mapa_de_voces`, sin importar la key usada. Detalle de la decisión de arquitectura (por qué Edge Function y no un rol Postgres directo) en [`specs/2026-09-19-api-publica.md`](specs/2026-09-19-api-publica.md).
- **Qué se escribió:** [`db/005_api_publica.sql`](db/005_api_publica.sql) — tabla `crm_comunidades.api_key` (solo hash, nunca texto plano) y las funciones `generar_api_key`/`revocar_api_key`/`validar_api_key`; [`supabase/functions/api-publica/index.ts`](supabase/functions/api-publica/index.ts) — el gateway que valida la key contra esas funciones y corre la query con `service_role` del lado del servidor.
- **Cómo usarla una vez deployada:** [Generar y revocar una key de la API pública](docs/how-to/generar-y-revocar-api-key.md).
- **Qué falta para que sea real:** correr `db/005` en el SQL Editor del proyecto (mismo patrón que `db/001`–`004`) y `supabase functions deploy api-publica` con la CLI logueada y el proyecto linkeado — ninguno de los dos pasos se ejecutó todavía contra Supabase real.

## Pivot a tratamiento de leads + WhatsApp (2026-09-23)

- **Qué cambió:** Conocimiento y Voz salen del panel — pasan a ser responsabilidad de otro sector de Taquión. El foco pasa a tratamiento de leads: Overview (embudo de `estado_identificacion` como pipeline, símil Pipedrive) y Activaciones (entrevistas indagatorias, promociones, anuncios de lanzamiento, disparadas nativamente por WhatsApp) son las dos secciones centrales. Detalle completo, incluidas las 4 decisiones de alcance, en [`specs/2026-09-23-pivot-leads-whatsapp.md`](specs/2026-09-23-pivot-leads-whatsapp.md).
- **`activo_tipo` no se tocó:** Conocimiento/Voz se sacaron solo de la navegación del panel — el enum de Postgres y las filas de `comunidad_activo` siguen intactos. Queda pendiente para una futura auditoría interna del proyecto decidir si se eliminan del esquema.
- **Disparo real hacia WhatsApp/ManyChat:** `db/006_activaciones_whatsapp.sql` (columna `activacion.formato_operativo`, `contacto.manychat_subscriber_id`, tabla `activacion_disparo`) + `supabase/functions/activacion-manychat/` — mismo patrón de Edge Function que `api-publica`. Sin deployar todavía; además depende de una API key real de ManyChat y de contactos con `manychat_subscriber_id` poblado, ninguna de las dos cosas existe aún.
- **Pipeline de tratos (2026-09-23):** `db/007_tratos.sql` — tabla `trato` (deals) en Overview, con su propio estado (`nuevo`/`contactado`/`en_proceso`/`ganado`/`perdido`), tarjetas arrastrables entre columnas. Deliberadamente separada de `contacto.estado_identificacion` — un trato es una decisión manual del equipo, la escalera de identificación nunca se fuerza a mano.
