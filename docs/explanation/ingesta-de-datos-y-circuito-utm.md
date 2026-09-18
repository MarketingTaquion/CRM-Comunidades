# Ingesta de datos: por qué el circuito UTM/ManyChat todavía no existe

Auditoría 2026-09-18 (Tarea 1a, [spec](../../specs/2026-09-18-utm-manychat-y-disparo-campanas.md)): se verificó de punta a punta si `contacto.fuente_utm_source/medium/campaign` se está poblando de verdad. La respuesta es que **no existe integración todavía** — no es un bug ("no funciona"), es que nunca se construyó.

## Evidencia (no inferencia)

Consulta contra la base real, 2026-09-18:

```sql
select comunidad_id, count(*) as total, count(fuente_utm_source) as con_source,
       count(fuente_utm_medium) as con_medium, count(fuente_utm_campaign) as con_campaign
from crm_comunidades.contacto group by 1;
```

| comunidad | total | con_source | con_medium | con_campaign |
|---|---|---|---|---|
| Todo un País | 6 | 0 | 0 | 0 |
| Cortado en Jarrito | 3 | 0 | 0 | 0 |

```sql
select 'contacto', count(*) from crm_comunidades.contacto
union all select 'evento_journey', count(*) from crm_comunidades.evento_journey
union all select 'importacion_log', count(*) from crm_comunidades.importacion_log;
```

`contacto` = 9, `evento_journey` = 0, `importacion_log` = 0.

Sumado a un grep completo de este repositorio (código, no documentación): no hay webhook, función serverless, configuración de n8n/Zapier ni script de importación en ninguna parte. La única referencia a ManyChat en código es el `check` de `importacion_log.origen`, que acepta `'export_manychat'` como categoría válida — ningún proceso la usa todavía.

## Qué significa esto en la práctica

Los 9 contactos que hoy tiene la base son datos de ejemplo cargados a mano por SQL Editor durante el trabajo de este mismo proyecto (septiembre 2026) — ninguno pasó por el bot de ManyChat ni por una importación real de `TODO_UN_PAÍS_COMUNIDADES_.xlsx`. `evento_journey` en cero significa que tampoco se registró un solo evento de journey todavía, ni manualmente.

Esto no bloquea el resto del CRM (Overview, Crecimiento, Relación, Mapa de Voces ya operan sobre los contactos de ejemplo cargados), pero sí significa que **ninguna métrica de fuente/canal (UTM) es confiable hoy** — cualquier reporte que intente segmentar por `fuente_utm_source` va a devolver vacío para el 100% de la base, no porque el canal no haya traído gente, sino porque el dato nunca se cargó.

## Qué falta para cerrarlo (sigue en backlog, no se resuelve acá)

Dos caminos, ya planteados como pregunta abierta en `specs/006`:
1. **Webhook directo** ManyChat → función serverless/n8n → `crm_comunidades.contacto`, disparado en tiempo real por cada alta.
2. **Importación periódica** desde un export manual de ManyChat o de la planilla `TODO_UN_PAÍS_COMUNIDADES_.xlsx`, usando el importador que pide `specs/006` (sección "Importación de datos") — todavía no construido tampoco.

Cuál de los dos (o si conviven, como plantea la spec, mientras dure la migración) sigue sin decidirse — ver README, backlog punto 1.
