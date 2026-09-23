# Spec — Pivot: tratamiento de leads + activaciones nativas de WhatsApp

Estado: aprobado, en implementación (PR `pivot/leads-whatsapp`). Registra un giro de producto, no una tarea puntual — se referencia desde `specs/2026-09-18-roadmap-crm-comunidades.md`.

## Qué cambia y por qué

El CRM venía construyéndose como una plataforma completa de "loyalty"/comunidad (6 activos: Conocimiento, Voz, Crecimiento, Relación, Activaciones, Decisiones). Decisión de producto (2026-09-23): **Conocimiento y Voz pertenecen a otro sector de Taquión** (Insights/Inspire, ver `docs/contexto-madre.md`) — este CRM deja de construir esa superficie. El foco pasa a **tratamiento de leads a nivel operacional**, con dos secciones centrales:

- **Overview** — el embudo de identificación (`estado_identificacion`) como pipeline de leads, no solo un desglose demográfico.
- **Activaciones** — generación de acciones nativas de WhatsApp dentro de las comunidades del servicio "Comunidades" de Taquión: entrevistas indagatorias, promociones, anuncios de lanzamiento.

## Decisiones tomadas (AskUserQuestion, 2026-09-23)

1. **Alcance de sacar Conocimiento/Voz — solo UI.** El enum `activo_tipo` y las filas de `comunidad_activo` para esos dos valores quedan intactos en la base. No se toca el schema en este PR.
   - **Pendiente explícito para una futura auditoría interna del proyecto:** evaluar si corresponde eliminar `conocimiento`/`voz` de `activo_tipo` (`db/001_init_crm_comunidades.sql`) y limpiar las filas de `comunidad_activo` asociadas. No se hace ahora porque dropear valores de un enum de Postgres exige recrear el tipo y tocar cada columna dependiente — una migración real, no una tarea de este PR. Queda anotado acá para que no se pierda la decisión.
2. **"Embudo" = `estado_identificacion` existente, con visual nueva tipo pipeline/kanban** (columnas por estado, tarjetas de contacto — símil Pipedrive), no una tabla de embudos nueva. Un embudo nombrado y configurable por campaña queda fuera de alcance — se revisita si hace falta después de ver cómo se usa este primero.
3. **Nueva clasificación de activaciones — campo nuevo, no reemplaza `tipo`.** `activacion.tipo` (`sponsor_anunciante`/`marca_contratante`) sigue siendo el eje comercial (quién la pide). Se suma `formato_operativo` (`entrevista_indagatoria`/`promocion`/`anuncio_lanzamiento`) para clasificar qué tipo de acción es.
4. **Este PR avanza trabajo real de disparo hacia WhatsApp/ManyChat** (antes Fase 4 del roadmap, "planeada") — no solo el reencuadre conceptual.

## Alcance técnico

### Frontend (`index.html`)
- `ACTIVOS` pierde `conocimiento`/`voz`; se borran `renderConocimiento()`/`renderVoz()` y sus referencias en `renderAll()`.
- Fallback de activo deshabilitado (antes caía a `'conocimiento'`) pasa a `'__overview'`.
- Overview suma una vista de pipeline por `estado_identificacion` (reusa `loadContactos()`, `contactName()`, `ESTADO_ORDEN` ya existentes).
- Activaciones suma un botón de disparo hacia WhatsApp por activación en curso.

### Base de datos (`db/006_activaciones_whatsapp.sql`)
- `activacion.formato_operativo` — columna nueva, nullable, `check` con los 3 valores de arriba.
- `contacto.manychat_subscriber_id` — columna nueva, nullable. **Gap real detectado:** hoy no existe ninguna forma de vincular un `contacto` con su suscriptor de ManyChat — sin esto no se puede direccionar un tag real. Poblarla depende de la Fase 3 del roadmap (webhook ManyChat → CRM, todavía sin construir) o de carga manual para pruebas.
- `activacion_disparo` — tabla de audit log (ya diseñada conceptualmente en `specs/2026-09-18-utm-manychat-y-disparo-campanas.md`): `activacion_id, filtro_usado jsonb, cantidad_contactos, tag_manychat, estado, respuesta_api jsonb, disparado_por, creado_en`. RLS admin-only, mismo patrón que el resto del schema.

### Backend (`supabase/functions/activacion-manychat/`)
- Edge Function nueva, mismo patrón que `supabase/functions/api-publica/index.ts` (Fase 1): recibe `{activacion_id, filtro}`, resuelve el segmento de `contacto` con `manychat_subscriber_id` no nulo, llama a la API de ManyChat (`POST /fb/subscriber/addTagByName`) por cada uno, graba el resultado en `activacion_disparo`.
- **Dependencia externa que no se resuelve en este PR:** requiere una API key de ManyChat cargada como secret de Supabase, y al menos un contacto real con `manychat_subscriber_id`. El código queda escrito y lista para probarse en cuanto esas dos piezas existan — no es bloqueante para mergear, pero sí para un disparo real end-to-end.

## Documentación

- `README.md`: reencuadre hacia tratamiento de leads/WhatsApp; nota de auditoría pendiente sobre `activo_tipo`.
- `specs/2026-09-18-roadmap-crm-comunidades.md`: fila "Entender + Diseñar" reescrita (ya no es responsabilidad de este CRM); Fase 4 pasa a "En progreso".
- `docs/reference/esquema-de-base-de-datos.md`: nuevas columnas y tabla documentadas.

## Criterios de aceptación

- [ ] El panel ya no muestra Conocimiento ni Voz en la navegación, y cambiar de comunidad no rompe (fallback corregido).
- [ ] Overview muestra el pipeline de `estado_identificacion` con los contactos demo ya cargados.
- [ ] `db/006` aplicado: `activacion.formato_operativo`, `contacto.manychat_subscriber_id` y `activacion_disparo` existen con RLS.
- [ ] La Edge Function `activacion-manychat` está escrita y documentada, con su dependencia externa (API key de ManyChat + subscriber IDs reales) explícita como pendiente post-PR.
- [ ] `activo_tipo` y `comunidad_activo` NO se tocan en este PR — la decisión de eliminarlos queda registrada acá para la auditoría futura.
