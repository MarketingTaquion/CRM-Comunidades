# Modelo de identificación y gobernanza de exportación

## La escalera de 6 pasos, y por qué es un solo contacto

`estado_identificacion` modela seis niveles progresivos: `anonimo → pseudo_anonimo → semi_identificado → identificado → enriquecido → confirmado`. La decisión de diseño central es que **es un solo registro de contacto avanzando por estos estados**, nunca dos bases separadas (una de "anónimos" y otra de "identificados") que después haya que reconciliar. El enum se declara en ese orden ascendente a propósito, para que comparaciones de rango (`estado_identificacion >= 'enriquecido'`) funcionen directo en SQL sin mapear a un entero aparte.

Esto es lo que hace posible que **Mapa de Voces no sea una tabla aparte** sino la vista `mapa_de_voces`, filtrando sobre la misma tabla `contacto` (`estado_identificacion in ('enriquecido','confirmado') and nivel_activacion >= 4 and semanas_consecutivas_activo >= 3`). Si hubiera dos bases, ese filtro tendría que vivir como un proceso de sincronización aparte, con todo el riesgo de desincronización que eso implica.

## Por qué `anonimizar_contacto()` existe como función explícita

El único camino soportado para "retroceder" el estado de identificación de un contacto (por ejemplo, si alguien ejerce su derecho a ser olvidado) es llamar a `anonimizar_contacto(p_contacto_id, p_motivo)`, que borra `telefono_plano`/`nombre_declarado`/`username` y fuerza `estado_identificacion = 'pseudo_anonimo'`. Nunca es un efecto automático de ningún trigger ni de ningún job — siempre una acción explícita, con motivo, porque revertir identificación es una decisión con consecuencias legales/de negocio que no debería poder pasar por accidente.

## Por qué la exportación tiene 3 niveles con gobernanza distinta

| Nivel | Qué expone | Quién puede | Estado |
|---|---|---|---|
| 1 — Operativo/cliente | Agregado (arquetipo × corredor × nivel de activación), nunca datos individuales | Cualquier rol | Construido — ver [Exportar datos (Nivel 1)](../how-to/exportar-datos-nivel-1.md) |
| 2 — Interno Taquión | Dataset nominal completo, incluye Mapa de Voces | `admin_taquion` / `am_estratega`, con motivo obligatorio | No construido (endpoint pendiente) |
| 3 — Plataformas externas | Push a Meta Custom Audience / sync a Sheets-Airtable | `admin_taquion` | No construido |

La razón de separar estos niveles en vez de un único export configurable es que cada uno tiene un radio de exposición de datos personales completamente distinto, y la vista `export_nivel1_agregado` que respalda el Nivel 1 está construida para que sea **estructuralmente imposible** exportar de más desde ahí — no depende de que quien exporta recuerde no tildar una columna, la vista directamente no tiene esas columnas. Los niveles 2 y 3 sí las exponen, y por eso exigen motivo registrado en `exportacion_log` sin excepción, incluso para `admin_taquion` — nadie está exento del audit log cuando el dato es nominal.

## Por qué Conocimiento y Voz no muestran datos, aunque estén "habilitados"

`renderConocimiento()` y `renderVoz()` devuelven un panel honesto ("todavía no tiene fuente de datos conectada") en vez de números. El esquema de `crm_comunidades` hoy no modela sentiment, piezas publicadas ni brecha semántica — construir esas tablas es una fase posterior, fuera del alcance actual. La alternativa de simular esos números con datos de ejemplo se descartó a propósito: es una regla cultural de Taquión no fabricar datos que parezcan reales sin serlo, y la señal de "esto no está conectado todavía" es más valiosa que un gráfico que parece funcionar pero no significa nada. Lo mismo aplica a CPME/CPMR/TRG/K-Factor en Crecimiento, que requieren una fuente de datos de inversión en pauta que todavía no existe en la base.

## Overview y métricas de performance

La pestaña Overview (`db/002_overview_metricas.sql`) aplica el mismo principio de no fabricar datos, pero de una forma más matizada que Conocimiento/Voz: en vez de mostrar un panel bloqueado, cada métrica se calcula de verdad y se muestra tal cual, incluso cuando ese valor real es `0%` por falta de carga.

- **Engagement** es un número real desde el día uno: se calcula sobre `nivel_activacion`, un campo que ya está poblado para los contactos existentes. No requirió ningún cambio de esquema.
- **Tasa de abandono** y **tasa de referidos** sí requirieron agregar columnas nuevas (`contacto.fecha_baja` y `contacto.referido_por_contacto_id`) porque el esquema no tenía ningún lugar donde registrar esa información. Ambas arrancan en `0%` para toda la base existente — deliberadamente no se marcó a nadie como "dado de baja" ni se infirió ningún referido a partir de, por ejemplo, patrones de `fuente_utm_source`. Son señales que requieren una decisión humana explícita (mismo criterio que `anonimizar_contacto()`: nunca automáticas), así que el `0%` de hoy es honesto — significa "nadie lo cargó todavía", no "no hay abandono ni referidos".
- La UI (`renderOverview()` en `index.html`) muestra una nota aclaratoria cuando estas dos tasas dan `0`, para que no se lean como un logro ("cero abandono") cuando en realidad es "sin instrumentar todavía".

La alternativa que se descartó fue inferir abandono automáticamente (por ejemplo, de `semanas_consecutivas_activo = 0` o de ausencia de eventos recientes en `evento_journey`). No se hizo porque el job semanal que mantiene `semanas_consecutivas_activo` actualizado todavía no existe (ver "Qué falta" en el README) — construir una métrica sobre un campo que hoy puede estar desactualizado sería, en los hechos, fabricar un número que parece confiable sin serlo.
