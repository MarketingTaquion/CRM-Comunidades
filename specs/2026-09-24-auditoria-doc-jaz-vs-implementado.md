# Auditoría — "Documento completo de especificaciones técnicas y diseño" (Jaz) vs. lo construido

Estado: **auditoría, no implementación**. Este documento no propone cambios de código — mapea qué de lo que pide el documento de Jaz ya existe en este repo, qué existe parcialmente, y qué no existe, para poder decidir con criterio qué se construye y en qué orden.

Fuente: `DOCUMENTO COMPLETO DE ESPECIFICACIONES TÉCNICAS Y DISEÑO` (Jaz, recibido 2026-09-24), dirigido a "Desarrollador de Software / Frontend & Backend Architect". Comparado contra: `index.html`, `db/001`–`008`, `README.md`, `docs/reference/esquema-de-base-de-datos.md` y los specs previos de este repo.

## Resumen ejecutivo

El documento de Jaz no es una lista de features sueltas — describe una **arquitectura de producto distinta** en varios ejes de diseño que este CRM ya resolvió de otra manera, algunas veces a propósito. Antes de mapear "tab por tab", conviene resolver estos 4 conflictos, porque determinan si lo que se construye es una evolución de este repo o un producto paralelo:

| # | Eje | Documento de Jaz | Este repo (hoy) |
|---|---|---|---|
| 1 | Identidad entre comunidades | **Atribución "First-Contact"**: el teléfono es la llave primaria global — si el mismo número pasa por dos comunidades, el 100% del origen publicitario se le asigna a la *primera* | `(comunidad_id, telefono_hash)` es la clave única — **el mismo teléfono en otra comunidad es una persona distinta a los fines de este CRM**, comunidades aisladas entre sí a propósito (`docs/reference/esquema-de-base-de-datos.md`) |
| 2 | Niveles de persistencia | 3 niveles explícitos y consultables: **Crudo** (todos los eventos, con duplicados) → **Deduplicado** (1 fila por teléfono) → **Curado/Limpio** (enriquecido con perfil de ManyChat) | Un solo nivel "curado" (`contacto`) + `evento_journey` genérico (tipos: awareness/clic/lead/whatsapp/activacion/encuesta/encuentro) — no hay un nivel "deduplicado" intermedio ni una vista de crudo con reintentos/duplicados |
| 3 | Gobernanza de identidad | Nombre, teléfono y email de cada usuario visibles directo en la tabla ("Base_Limpia") para el "usuario final" | Visibilidad **progresiva y por rol**: `contactName()` solo muestra el nombre si `estado_identificacion` llegó a `enriquecido`/`confirmado`, y nunca al rol `cliente` — es una regla central del producto (ver `docs/explanation/modelo-de-identificacion-y-gobernanza-de-exportacion.md`), no un detalle de UI |
| 4 | Plataforma de deploy | CRM pensado para renderizarse **dentro de un Claude Artifact / MCP**, consumiendo un endpoint JSON | App real deployada en Vercel + Supabase (Postgres + Auth + Edge Functions), decisión de arquitectura ya tomada y funcionando en producción |

Ninguno de los 4 es un "bug" del lado de este repo — son decisiones ya tomadas con el usuario en sesiones anteriores (aislación entre comunidades, gobernanza de identidad, arquitectura de deploy). Pero si el objetivo es unificar con lo que pide Jaz, alguien tiene que decidir explícitamente cuál gana en cada eje antes de tocar código — no se pueden construir los dos modelos de datos a la vez sin generar inconsistencias.

## Tab por tab: qué pide Jaz vs. qué existe

| Tab de Jaz | Qué pide | Equivalente actual | Estado |
|---|---|---|---|
| **1. Overview** | KPIs macro (inversión, conversaciones, CPL, clics, miembros efectivos, CPME, tasa de fuga global) + tabla de distribución por comunidad | Pestaña **Overview** ya existe: KPIs (contactos totales, engagement, tasa de abandono, tasa de referidos) + tabla por barrio/arquetipo + pipeline de leads + fotos semanales | **Parcial** — el layout (KPIs arriba + tabla abajo) ya está, pero los KPIs son de calidad/engagement de contacto, no de inversión/atribución publicitaria. `metrica_semanal` (Fase 7, 2026-09-24) ya tiene los campos manuales de inversión/CPL/conversaciones/clics por semana, pero **no se agregan todavía en un roll-up global** como pide este tab |
| **2. Control_Comunidades** | Matriz Meta Ads vs. ManyChat vs. WhatsApp por comunidad, con CPL/CTR/CPCU/CPMN/tasa de fuga | No existe una vista equivalente | **No existe** — depende de datos que hoy no se capturan (CTR de anuncio, triggers entregados de ManyChat, envíos de enlace) |
| **3. Base_Limpia** | Tabla de usuarios nominados (nombre/email reales) con buscador, filtro por comunidad y paginado | Tabla de **Contactos** (ex-Relación) — lista contactos reales de `contacto`, con estado/corredor/arquetipo/nivel | **Parcial** — la tabla existe pero sin buscador ni paginado, sin columna de email (no existe en el esquema), y los nombres se ocultan según gobernanza en vez de mostrarse siempre |
| **4. Data_Deduplicada** | Log técnico: primer evento por teléfono, para auditar qué comunidad "ganó" la atribución | No existe — no hay concepto de atribución cross-comunidad en el esquema actual | **No existe** |
| **5. Data_Cruda** | Feed de actividad en vivo: todos los eventos del webhook de ManyChat, incluidos duplicados y reintentos | `evento_journey` existe como tabla pero **no está poblada** — no hay webhook de ManyChat escribiendo ahí (backlog #1 del README, auditado 2026-09-18) | **No existe en la práctica** (la tabla está, el flujo que la llenaría no) |

## Integraciones: qué pide Jaz vs. qué existe

| Integración | Qué pide Jaz | Estado actual |
|---|---|---|
| **Windsor.ai MCP (Meta Ads)** | Consultar spend/impresiones/conversaciones por `adset_name` y mapearlo a la comunidad automáticamente | **No existe.** La decisión del 2026-09-24 fue explícita: la inversión/CPL/conversaciones se cargan **a mano** en `metrica_semanal`, sin integrar con Pulso Ignite (que sí usa Windsor.ai) en esta fase |
| **Webhook de ManyChat (inbound)** | Evento HTTP en vivo cuando el usuario clickea el link del grupo, con phone/community_id/timestamp | **No existe** — es exactamente la Fase 3 ("Cerrar el circuito de datos") del roadmap, hoy "Planeado", recién pasó a prioridad #1 el 2026-09-24 |
| **Módulo de Nominación (sync de perfil)** | Cruzar teléfonos contra el reporte de suscriptores de ManyChat para reemplazar nombres anonimizados por nombres/emails reales | **Parcial, y en la dirección opuesta**: `contacto.manychat_subscriber_id` existe (`db/006`) pero se usa para **enviar** tags hacia ManyChat (activaciones de WhatsApp), no para **traer** datos de perfil desde ManyChat hacia acá. No hay endpoint ni botón de sincronización, y `contacto` no tiene columna `email` |
| **Endpoint JSON para Claude Artifact** | Exponer un JSON consolidado (`kpis_macro` + `comunidades_performance` + `base_limpia_usuarios`) para que un Artifact lo consuma | No existe — iría en la línea de la API pública (Fase 1, `db/005` + `supabase/functions/api-publica/`), que hoy expone `comunidad`/`export_nivel1_agregado` de solo lectura, no este shape específico ni deployada todavía |

## Lo que sí está construido y cubre parte de lo pedido

- El **circuito de datos de Meta→ManyChat→WhatsApp** que describe Jaz en su diagrama de arquitectura es, en esencia, la misma Fase 3 que ya está en el roadmap como prioridad #1 desde el 2026-09-24 — el documento de Jaz es evidencia adicional de que hay que construirla, no una tarea nueva.
- `metrica_semanal` (Fase 7) ya tiene el lugar para cargar inversión/CPL/conversaciones/clics semana a semana — es la base sobre la que se podrían calcular CPME/tasa de fuga si se decide sumarlos.
- `contacto.corredor_localidad` + `fecha_alta`/`fecha_baja` ya permiten calcular "miembros iniciales/finales por corredor" sin conflictuar con el resto del esquema.
- El patrón de Edge Function (`api-publica`, `activacion-manychat`) ya es el lugar natural para un futuro endpoint JSON de solo lectura, si se decide exponerlo.

## Lo que no existe y requeriría diseño nuevo (no solo código)

- Un modelo de atribución cross-comunidad por teléfono (conflicto #1 de la tabla de arriba) — **decisión de producto**, no solo una migración.
- Los 3 niveles de persistencia crudo/deduplicado/curado como objetos consultables aparte.
- Captura de CTR de anuncio, triggers de ManyChat entregados y envíos de enlace — no hay fuente de datos para esto todavía (depende del webhook de Fase 3 y/o de Windsor.ai).
- Buscador + paginado en la tabla de Contactos.
- Columna `email` en `contacto`.

## Preguntas abiertas (para resolver antes de escribir cualquier migración)

1. **¿La atribución "First-Contact" cross-comunidad reemplaza el aislamiento actual entre comunidades, o conviven?** Son mutuamente excluyentes tal como está modelado hoy (`(comunidad_id, telefono_hash)` único) — si se quiere lo de Jaz, hay que decidir si un contacto puede "pertenecer" a una comunidad pero tener un registro de atribución global aparte.
2. **¿La gobernanza de visibilidad de identidad (nunca mostrar nombre antes de "enriquecido/confirmado", nunca al rol cliente) sigue siendo la regla, o el "Base_Limpia" de Jaz la reemplaza para ciertos roles?**
3. **¿Windsor.ai se integra en algún momento a este CRM, o el CPL/inversión se mantiene 100% manual como se decidió el 2026-09-24?** El documento de Jaz asume integración automática.
4. **¿Este CRM se sigue deployando como app Vercel+Supabase, o hay un pedido real de exponerlo también como Claude Artifact/MCP?** Son objetivos de arquitectura distintos, no incompatibles necesariamente (se podría exponer un JSON de solo lectura sin migrar todo el frontend), pero hay que acotar el alcance.

## Próximo paso sugerido

No tocar código todavía. Con las 4 preguntas de arriba respondidas, esto se convierte en un spec de implementación normal (a la Fase 3/7 ya existentes, o una Fase nueva) — hasta entonces, este documento sirve como mapa de gaps para la conversación con Jaz/el equipo.
