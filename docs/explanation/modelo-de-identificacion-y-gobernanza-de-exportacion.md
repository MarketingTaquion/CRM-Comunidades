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

## Conocimiento, Voz y los KPIs de Crecimiento (CPME/CPMR/TRG/K-Factor): contenido de ejemplo, no datos reales

El esquema de `crm_comunidades` hoy no modela sentiment, piezas publicadas, brecha semántica ni datos de inversión en pauta — construir esas tablas es una fase posterior, fuera del alcance actual. Por decisión explícita de producto (2026-09-17, "quiero el CRM completo"), `renderConocimiento()`, `renderVoz()` y el bloque de KPIs de `renderCrecimiento()` muestran **contenido de ejemplo hardcodeado** en vez del panel honesto de "no conectado" que tenían antes — pensado para que el panel se pueda mostrar/compartir completo mientras se define y construye la fuente real de cada uno.

La regla de no fabricar datos sigue vigente, pero aplicada distinto acá: cada uno de estos bloques está **marcado explícitamente como "Contenido de ejemplo"** en su propio texto (`sub`), nunca se presenta como si fuera un número real. La diferencia con, por ejemplo, `Overview` (donde `tasa_referidos`/`tasa_abandono` son reales aunque arranquen en `0%`) es justamente esa: ahí el `0%` es un dato real todavía sin cargar; acá el número que se ve **no sale de ninguna tabla**, es contenido de relleno para revisar el diseño de la vista. Cuando se conecte cada fuente real (sentiment, piezas publicadas, spend), estos bloques se reemplazan por datos reales — no se acumulan ambas cosas.

## Overview y métricas de performance

La pestaña Overview (`db/002_overview_metricas.sql`) aplica el mismo principio de no fabricar datos, pero de una forma más matizada que Conocimiento/Voz: en vez de mostrar un panel bloqueado, cada métrica se calcula de verdad y se muestra tal cual, incluso cuando ese valor real es `0%` por falta de carga.

- **Engagement** es un número real desde el día uno: se calcula sobre `nivel_activacion`, un campo que ya está poblado para los contactos existentes. No requirió ningún cambio de esquema.
- **Tasa de abandono** y **tasa de referidos** sí requirieron agregar columnas nuevas (`contacto.fecha_baja` y `contacto.referido_por_contacto_id`) porque el esquema no tenía ningún lugar donde registrar esa información. Ambas arrancan en `0%` para toda la base existente — deliberadamente no se marcó a nadie como "dado de baja" ni se infirió ningún referido a partir de, por ejemplo, patrones de `fuente_utm_source`. Son señales que requieren una decisión humana explícita (mismo criterio que `anonimizar_contacto()`: nunca automáticas), así que el `0%` de hoy es honesto — significa "nadie lo cargó todavía", no "no hay abandono ni referidos".
- La UI (`renderOverview()` en `index.html`) muestra una nota aclaratoria cuando estas dos tasas dan `0`, para que no se lean como un logro ("cero abandono") cuando en realidad es "sin instrumentar todavía".

La alternativa que se descartó fue inferir abandono automáticamente (por ejemplo, de `semanas_consecutivas_activo = 0` o de ausencia de eventos recientes en `evento_journey`). No se hizo porque el job semanal que mantiene `semanas_consecutivas_activo` actualizado todavía no existe (ver "Qué falta" en el README) — construir una métrica sobre un campo que hoy puede estar desactualizado sería, en los hechos, fabricar un número que parece confiable sin serlo.

## Activaciones (activo 5): por qué no toca Crecimiento

`crm_comunidades.activacion` (`db/003_activaciones.sql`) modela una activación — un proyecto de negocio con un sponsor o una marca contratante — como una entidad completamente aparte de `contacto`/`evento_journey`. Ninguna columna de `activacion` referencia esas tablas.

La razón es de fondo, no solo de estilo: Crecimiento mide adquisición y retención orgánica de la comunidad (`comunidad_metricas`, `overview_por_barrio/arquetipo`); una activación es un proyecto puntual con su propio objetivo de negocio, brief y KPI, que puede o no tener relación con adquisición (un evento de fidelización para socios ya existentes no suma "contactos nuevos" y sin embargo es una activación completamente válida). Si `activacion` tuviera una FK a `contacto`, cada vez que se quisiera responder "¿cuántos contactos trajo esta activación?" habría que decidir un criterio de atribución (¿por fecha? ¿por tag manual?) que hoy no existe — mezclar ambos dominios en el modelo obligaría a inventar ese criterio antes de tener el dato real para sostenerlo. Se prefiere mantenerlos separados y, si en el futuro se necesita cruzar los dos, construir una vista aparte que joinee por `comunidad_id` + rango de fechas — explícita sobre qué supuesto de atribución usa, en vez de una FK que lo esconde.

`kpi_objetivo`/`kpi_resultado` son `jsonb` (no columnas fijas) por el mismo motivo que `contacto.score_compuesto`: cada activación puede medir algo distinto (leads, alcance, asistencia, revenue) y fijar columnas de antemano obligaría a elegir un set de KPIs "universal" que no existe todavía en la práctica del producto.

## Informe de Decisión Ejecutiva: insumo automático vs. informe escrito a mano

Por playbook de producto (`specs/006`): *"Decisiones es la única vista que no se completa con datos en vivo: se escribe manualmente al cierre de cada temporada — semáforo contra el plan, aprendizajes, plan de acción"*. `db/004_informe_decision_insumo.sql` respeta esa regla construyendo **dos objetos separados a propósito**, no uno solo:

- **`informe_decision_insumo`** (vista): 100% automática, solo números — la foto acumulada de la comunidad al cierre de la temporada (o a hoy, si sigue abierta) más la actividad que ocurrió estrictamente dentro de esa temporada (altas, referidos, bajas nuevas). `engagement_rate` solo tiene versión de foto, nunca de período, porque `nivel_activacion` no tiene tabla de historial — no hay de dónde reconstruir "el engagement de marzo" una vez que es mayo.
- **`informe_decision`** (tabla): el semáforo, los aprendizajes y el plan de acción — se carga a mano, siempre. Ningún job, función ni trigger de este esquema escribe en esta tabla. Si en el futuro alguien le agrega un default automático al `semaforo` (por ejemplo, "verde si `engagement_rate` > 0.5"), está rompiendo esta regla de producto — el número puede sugerir un semáforo, pero decidirlo sigue siendo una lectura humana del contexto que ningún cálculo captura completo.

`temporada` es una tabla nueva que no pedía explícitamente ninguna spec anterior — se agregó porque, sin un registro de las fechas de cada temporada pasada, "insumo al cierre de temporada" no es construible con el esquema que existía (`comunidad.temporada_numero`/`fecha_inicio_temporada` solo guardan la temporada *actual*). Arranca vacía para las comunidades existentes porque no hay una fecha de inicio real que migrar — `informe_decision_insumo` devuelve honestamente 0 filas para una comunidad hasta que alguien cargue su primera fila de `temporada` con una fecha real, en vez de fabricar una.
