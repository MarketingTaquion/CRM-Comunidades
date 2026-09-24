# Roadmap — CRM de Comunidades sobre el playbook oficial

Estado: vivo, se actualiza a medida que se define orden y alcance. No es un spec de una tarea puntual (ver el resto de `specs/` para eso) — es el mapa de dónde encaja el CRM en la metodología de Comunidades y hacia dónde va.

Fuentes: `SDD-TAQUION/specs/006-crm-comunidades.md`, `SDD-TAQUION/docs/contexto-madre.md`, Playbook de Producto "Comunidad" (capturas 2026-09-16), y el estado real de este repo (`db/001`–`004`, `README.md`, `docs/`).

## Aporte por etapa del playbook

| Etapa | Qué recibo | Mis accionables | Qué entrego a otros equipos | Estado en el CRM hoy |
|---|---|---|---|---|
| **Detectar** | Research inicial de Insights (segmentación, encuesta, clustering) y datos crudos de captura (ManyChat/planillas) | Alta de la comunidad (`comunidad`) y su roster de arquetipos (`arquetipo`, exclusión siempre explícita); diseño de `estado_identificacion` para clasificar cada contacto desde el primer punto de contacto | El registro único de la comunidad —reemplaza la planilla suelta— con el roster de arquetipos listo para que Insights/AM lo validen y para que el resto de los activos trabajen sobre la misma base | `comunidad` + `arquetipo` + `estado_identificacion` construidos y aplicados (db/001); alta de comunidad ya documentada (how-to) |
| **Entender + Diseñar** ("Estrategia de Destino", tope 2 meses) | Research cuali/cuanti y social listening de Insights; narrativa/naming de Inspire; North Star y límites del Blueprint definidos por AM+Estratega | *(fuera del alcance de este CRM desde 2026-09-23 — ver nota abajo)* | Nada: Conocimiento y Voz pasan a construirse fuera de este CRM | Conocimiento y Voz sacados del panel (pivot 2026-09-23, `specs/2026-09-23-pivot-leads-whatsapp.md`) — el enum `activo_tipo` los conserva a nivel de base, pendiente de auditoría futura |
| **Activar** | Brief y objetivo de negocio de cada campaña (sponsor o marca contratante) de AM + Ignite | Tabla `activacion` propia (nombre, tipo, objetivo, brief, fechas, KPI objetivo/resultado, estado, responsable), separada de Crecimiento; spec de disparo de segmentos hacia ManyChat vía tag; landing pages con IA + CRO vía PostHog para cada campaña; activación de captación de audios de VOC vía email/push notification | A AM/Ignite un registro único por campaña con su propia medición, sin mezclar con el funnel de adquisición; landing pages de campaña con conversión optimizada; la activación que solicita los audios de VOC a los miembros por email o push | Tabla `activacion` aplicada y con RLS (db/003), panel ya lee de ahí (vacío hasta la primera carga real); landing pages con IA/CRO y canal de email/push — todavía no integrados al repo del CRM |
| **Crecer** | Journey/adquisición vía ManyChat (hoy sin integrar, ver auditoría UTM) y nivel de activación cargado manualmente | Overview (barrio/arquetipo + engagement/abandono/referidos reales por comunidad), funnel de Crecimiento por `estado_identificacion`, Mapa de Voces (vista gobernada, nunca al cliente); auditoría del circuito UTM/ManyChat con evidencia real; sistema de VOC con captación de audios y embeddings para transcripción y búsqueda semántica | A AM/dirección un panel de performance por comunidad (nunca promediado entre comunidades) y el diagnóstico honesto de qué falta para la atribución de canal; a Insights un repositorio de voz de la comunidad transcripto y buscable | Overview + Crecimiento + Relación + Mapa de Voces reales y funcionando (db/002); circuito UTM auditado, documentado como pendiente (0% de contactos con UTM cargado); VOC — no construido todavía |
| **Cierre de temporada** (transversal, Informe de Decisión Ejecutiva) | Lo cuantitativo ya instrumentado en Crecimiento/Relación al momento del cierre | Vista automática `informe_decision_insumo` (foto acumulada al cierre + actividad de la temporada) y tabla `informe_decision` para que Insights/liderazgo escriban semáforo, aprendizajes y plan de acción a mano | A liderazgo/Insights el insumo numérico listo para el informe, sin fabricar el análisis cualitativo que les corresponde escribir a ellos | `temporada` + `informe_decision` + `informe_decision_insumo` aplicados (db/004); arranca vacío hasta cargar la primera fecha real de temporada |

## Prioridad actual (actualizada 2026-09-24, reunión Jazleidis/Juan 2026-09-23)

Esa reunión reencuadró el orden: *"priorizar el desarrollo del CRM enfocado en el tratamiento de leads y el flujo de métricas, en lugar de una plataforma tipo pipeline comercial"*, con cohortes de ingreso/retención semanales por corredor como entregable concreto. Detalle completo en [`specs/2026-09-24-medicion-y-cohortes.md`](2026-09-24-medicion-y-cohortes.md).

1. **Fase 3 — Cerrar el circuito de datos.** Pasa a ser la prioridad número uno (antes que Fase 1/2).
2. **Fase 7 — Medición y cohortes (nueva).** El entregable concreto que pidió la reunión — ver spec dedicado.
3. Fase 1 (API pública) y Fase 2 (Reportes) siguen, en ese orden, pero detrás de las dos de arriba.
4. **Fase 4 (Activaciones avanzadas) queda diferida** — incluye el pipeline de tratos (deals) agregado el 2026-09-23, que resultó ser justo lo que esa misma reunión decidió posponer. El código ya está escrito y deployado; no se retira, pero deja de ser foco de desarrollo activo.
5. Fases 5 y 6 no cambian de lugar — siguen detrás de todo lo anterior.

## Roadmap de construcción

### Fase 0 — Base del CRM · **Hecho**
- Comunidad + roster de arquetipos + `estado_identificacion` (db/001)
- Overview, funnel de Crecimiento, Relación y Mapa de Voces reales, nunca promediados entre comunidades (db/002)
- Activaciones como tabla propia, separada de Crecimiento (db/003)
- Insumo automático + informe escrito a mano para el cierre de temporada (db/004)
- Auditoría del circuito UTM/ManyChat, documentada con evidencia real

### Fase 1 — API pública · **En progreso (2026-09-19)**
- Exponer la REST API de Supabase con API keys propias
- Definir qué tablas/vistas salen hacia afuera y qué puede entrar desde otras herramientas
- Spec de alcance y decisión de arquitectura escritas (`specs/2026-09-19-api-publica.md`); `db/005_api_publica.sql` (tabla `api_key` + funciones) y el gateway (`supabase/functions/api-publica/`) ya escritos — deploy contra Supabase real pendiente (ver README, "Qué falta")

### Fase 2 — Reportes · **Próximo**
- Reportes manuales cargados por evento
- Programación de reportes automáticos con variables configurables, dentro del panel

### Fase 3 — Cerrar el circuito de datos · Planeado
- Webhook o importación real ManyChat → CRM (hoy 0% de contactos con UTM cargado)
- Job semanal de recálculo de `nivel_activacion` / `semanas_consecutivas_activo`

### Fase 4 — Activaciones avanzadas · **Diferida (2026-09-24, ver reunión 2026-09-23)**
- Disparo de segmentos hacia ManyChat vía tag — código escrito el 2026-09-23 (`db/006_activaciones_whatsapp.sql` + `supabase/functions/activacion-manychat/`), deployado, pero sin API key real de ManyChat ni contactos con `manychat_subscriber_id` poblado — queda tal cual, sin seguir avanzando por ahora
- `activacion.formato_operativo` (entrevista indagatoria / promoción / anuncio de lanzamiento) — construido, en pausa
- Pipeline de tratos (deals, `db/007_tratos.sql`) — construido y deployado el 2026-09-23, **el mismo día que la reunión decidió diferir justo esto** ("interfaz tipo pipeline" → especificación futura). Queda como está, no se retira, pero no se sigue desarrollando
- Landing pages con IA + CRO vía PostHog y activación de captación de audios de VOC por email/push — siguen planeadas, sin cambios

### Fase 5 — VOC (Voice of Customer) · Planeado
- Pipeline de audio → transcripción → embeddings → búsqueda semántica
- Insumo para Insights, complementa (no reemplaza) la escucha manual de Conocimiento

### Fase 6 — Roles y gobernanza · Planeado
- Login real + RLS para `am_estratega`/`cliente`
- Exports Nivel 2/3 con audit log

### Fase 7 — Medición y cohortes · **Nueva, prioridad #2 (2026-09-24)**
- Foto semanal por comunidad/corredor: contactos nuevos, activos, dados de baja, engagement, abandono, referidos (auto-calculables) + inversión en pauta, CPL, conversaciones (Meta) y clics (carga manual, aparte — ver spec)
- Cohortes de ingreso/retención semana a semana, por corredor (ej. San Luis, Boedo, Palermo, Villa Devoto)
- Detalle completo, diseño de tabla propuesto y preguntas resueltas en [`specs/2026-09-24-medicion-y-cohortes.md`](2026-09-24-medicion-y-cohortes.md)

## Notas de alcance

- El orden Fase 1 → Fase 2 (API pública antes que Reportes) fue confirmado explícitamente antes de este roadmap.
- Fases 3 a 6 están mapeadas pero sin orden relativo confirmado todavía — se prioriza cuando corresponda.
- Este documento no reemplaza los specs de tarea puntual (`2026-09-18-activaciones-tabla.md`, `2026-09-18-informe-decision-insumo.md`, `2026-09-18-utm-manychat-y-disparo-campanas.md`) — los referencia.
- **Pivot 2026-09-23:** Conocimiento y Voz salen del panel de este CRM (otro sector de Taquión los construye) — ver `specs/2026-09-23-pivot-leads-whatsapp.md` para el detalle completo y el pendiente de auditoría sobre `activo_tipo`.
- **Reencuadre 2026-09-24 (reunión Jazleidis/Juan, 2026-09-23):** medición/tracking/cohortes pasa a ser la prioridad, por delante de Activaciones avanzadas (Fase 4, diferida) — ver `specs/2026-09-24-medicion-y-cohortes.md`.
