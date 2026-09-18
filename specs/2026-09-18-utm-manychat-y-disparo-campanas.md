# Spec — Auditoría de circuito UTM + evaluación de disparo de campañas hacia ManyChat

Estado: propuesta, pendiente de revisión. No implica migraciones (Tarea 1a es un hallazgo documental; Tarea 1b es una propuesta de capacidad, no su construcción).

## 1a — Auditoría del circuito UTM (ManyChat → CRM)

**Qué es:** confirmar de punta a punta si `contacto.fuente_utm_source/medium/campaign` se puebla de verdad, y documentar el hallazgo con evidencia real.

**Hallazgo (verificado 2026-09-18, SQL Editor, rol `postgres`):**

```sql
select comunidad_id, count(*) as total, count(fuente_utm_source) as con_source,
       count(fuente_utm_medium) as con_medium, count(fuente_utm_campaign) as con_campaign
from crm_comunidades.contacto group by 1;
```
→ Todo un País: 6 filas, 0/0/0. Cortado en Jarrito: 3 filas, 0/0/0.

```sql
select 'contacto', count(*) from crm_comunidades.contacto
union all select 'evento_journey', count(*) from crm_comunidades.evento_journey
union all select 'importacion_log', count(*) from crm_comunidades.importacion_log;
```
→ `contacto`=9, `evento_journey`=0, `importacion_log`=0.

Grep completo de `crm-comunidades/` (código, no docs): cero webhook, cero función serverless, cero config de n8n/Zapier, cero script de importación. La única mención de ManyChat en código es el `check` de `importacion_log.origen` que acepta el valor `'export_manychat'` como categoría — ningún proceso lo usa todavía.

**Conclusión:** no es "no funciona" (bug) — **es "no existe integración todavía"**. Los 9 contactos de la base son datos de ejemplo cargados a mano por este mismo proyecto de trabajo, no datos que hayan pasado por ManyChat ni por una importación real de la planilla `TODO_UN_PAÍS_COMUNIDADES_.xlsx`.

**Qué NO hace esta tarea:** no construye el webhook ni el importador — eso sigue siendo backlog explícito (README punto 1; specs/006 "Todavía abiertas": *"¿la convivencia ManyChat→Sheets + ManyChat→CRM se resuelve con importación periódica o hace falta un webhook desde el día 1?"* — sigue sin resolver, y no se resuelve acá).

**Entregable (a escribir tras aprobar este spec):** `docs/explanation/ingesta-de-datos-y-circuito-utm.md` — el hallazgo de arriba con la evidencia exacta, enlazado al README (backlog #1) y a specs/006, sin duplicar contenido.

**Criterios de aceptación 1a:**
- [ ] La nota cita conteos de filas reales, no una inferencia del schema.
- [ ] Deja explícito "no existe todavía" (no "funciona"/"no funciona").
- [ ] No propone ni implica una fecha de resolución — solo dejar constancia del estado actual.

## 1b — Capacidad de disparo de campañas hacia ManyChat (propuesta, no construir)

**Qué es:** investigar qué necesita el CRM para poder **enviar** algo hacia ManyChat (no solo recibir), pensado para el activo Activaciones (5) — "el negocio entra a la comunidad".

**Investigación (API pública de ManyChat):**
- `POST /fb/subscriber/addTagByName` (y `createTag`) — aplicar un tag a un suscriptor o lote de suscriptores. Es el mecanismo más seguro de "disparo" porque no envía contenido, solo marca.
- `POST /fb/sending/sendContent` — envía un flow/mensaje a un `subscriber_id` puntual. Enviar contenido libre a un segmento masivo por API choca con las **ventanas de mensajería de WhatsApp Business** (24 hs desde el último mensaje del usuario; fuera de eso, exige plantillas pre-aprobadas por Meta) — restricción de WhatsApp, no de ManyChat, ya anticipada en specs/006 (4 funciones operativas de ManyChat).
- Auth: API key por cuenta/página de ManyChat (Bearer token), sin OAuth, sin scoping fino — la key da acceso a toda la cuenta.

**Implicancia de diseño:** la forma segura de "disparar campaña" no es mandar contenido libre por API, sino **aplicar un tag propio de la activación a un segmento de contactos, y que un flow de ManyChat ya configurado reaccione a ese tag**. Esto mantiene la regla dura de specs/006 ("Taquión es el administrador técnico único de los flujos de captura y de bot") — el CRM decide *a quién* taggear, nunca el contenido del mensaje.

**Spec de la capacidad propuesta — "Disparo de Activaciones vía tag ManyChat" (para construir en una Tarea futura, no ahora):**
- Un botón en Activaciones que, dado un filtro de contactos (por arquetipo/corredor/`estado_identificacion`, siempre dentro de **una** comunidad — nunca cruzando comunidades) y un `activacion_id` (Tarea 2), llama a la API de ManyChat para aplicar el tag de esa activación al segmento filtrado.
- **Qué número/dato mueve:** ninguno en `contacto`/`evento_journey` — esa dirección (ManyChat → CRM) sigue siendo la de la Tarea 1a. Esta capacidad solo llama a la API externa.
- **Qué se loguea:** tabla nueva `activacion_disparo` (activacion_id, filtro_usado jsonb, cantidad_contactos, tag_manychat, estado `'ok'|'error'`, respuesta_api jsonb, disparado_por, creado_en) — mismo nivel de trazabilidad que `exportacion_log`, porque es una acción con efecto en un sistema externo.
- **Credenciales:** API key de ManyChat por comunidad (cada una tiene su propia cuenta). **No puede vivir en `index.html`** (schema estático, cliente puro) — expondría la key a cualquiera con acceso al panel. Requiere una función serverless (Vercel Function o Supabase Edge Function) que reciba la orden del panel y llame a ManyChat con la key guardada del lado del servidor. **Esto rompe el patrón 100% frontend-estático actual del repo** — es una decisión de arquitectura nueva que hay que aprobar aparte, no asumirla incluida en este spec.
- **Fuera de alcance:** enviar contenido de mensaje libre, editar flows de ManyChat, disparo que cruce comunidades.

**Criterios de aceptación 1b (de este spec, no de código):**
- [ ] Queda explícito que el mecanismo es "aplicar tag", no "enviar mensaje libre".
- [ ] Queda explícito que hace falta backend/serverless nuevo, marcado como decisión a aprobar aparte.
- [ ] Define `activacion_disparo` con el mismo nivel de audit log que `exportacion_log`.
- [ ] No se escribe código ni se crea ninguna tabla todavía.
