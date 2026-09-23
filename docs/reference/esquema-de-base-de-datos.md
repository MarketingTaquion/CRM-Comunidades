# Referencia: esquema de base de datos

Todo vive en el schema Postgres `crm_comunidades` (nunca en `public`, donde vive `pulso-ignite`). Fuente completa: [`db/001_init_crm_comunidades.sql`](../../db/001_init_crm_comunidades.sql).

## Enums

| Enum | Valores (orden de declaración) |
|---|---|
| `etapa_comunidad` | `detectar`, `entender`, `disenar`, `activar`, `crecer` |
| `activo_tipo` | `conocimiento`, `voz`, `crecimiento`, `relacion`, `activaciones`, `decisiones` |
| `estado_identificacion` | `anonimo`, `pseudo_anonimo`, `semi_identificado`, `identificado`, `enriquecido`, `confirmado` |
| `rol_crm` | `admin_taquion`, `am_estratega`, `cliente` |
| `nivel_exportacion` | `1`, `2`, `3` |

`etapa_comunidad` y `estado_identificacion` se declaran en orden ascendente a propósito: Postgres compara enums por orden de declaración, así que un filtro como `estado_identificacion >= 'enriquecido'` funciona sin mapear a un entero aparte.

## Tablas

### `comunidad`
Un cliente de Taquión.

| Columna | Tipo | Notas |
|---|---|---|
| `id` | uuid, PK | |
| `nombre_interno` | text, not null | |
| `cliente` | text | ej. "GCBA", "San Luis" |
| `etapa` | `etapa_comunidad`, default `detectar` | Gobierna qué activos deberían habilitarse |
| `temporada_numero` | int, default 1 | |
| `fecha_inicio_temporada` | date | |
| `activo` | boolean, default true | Para archivar sin borrar |
| `created_at` / `updated_at` | timestamptz | `updated_at` automático vía trigger `set_updated_at()` |

### `comunidad_activo`
Habilitación de los 6 activos por comunidad (normalizado, no un array de booleanos).

| Columna | Tipo | Notas |
|---|---|---|
| `comunidad_id` | uuid, FK → `comunidad.id` on delete cascade | PK compuesta con `activo` |
| `activo` | `activo_tipo` | |
| `habilitado` | boolean, default false | |
| `habilitado_en` / `deshabilitado_en` | timestamptz | |
| `nota` | text | ej. motivo de habilitación puntual |

Se auto-pobla: un trigger (`trg_seed_activos` → `seed_activos_comunidad()`) crea las 6 filas en `false` al insertar una `comunidad`.

### `arquetipo`
Roster de arquetipos, reutilizable pero con inclusión/exclusión por comunidad.

| Columna | Tipo | Notas |
|---|---|---|
| `id` | uuid, PK | |
| `comunidad_id` | uuid, FK → `comunidad.id` | |
| `codigo` | text | ej. `'C4'`, único por comunidad |
| `nombre` | text | |
| `prioridad` | int | 1 = máxima prioridad |
| `corredor_principal` | text | |
| `incluido` | boolean, default true | |
| `motivo_exclusion` | text | Obligatorio si `incluido = false` (`check` a nivel de tabla) |

### `contacto`
Entidad central: un solo registro por persona, que avanza por `estado_identificacion` (nunca dos bases separadas).

| Columna | Tipo | Notas |
|---|---|---|
| `id` | uuid, PK | |
| `comunidad_id` | uuid, FK | |
| `telefono_hash` | text | sha256, para CAPI y dedupe |
| `telefono_plano` | text | Solo si se capturó — nunca en export Nivel 1 |
| `nombre_declarado`, `username` | text | |
| `pixel_id` | text | Vincula eventos previos a la identificación |
| `estado_identificacion` | enum, default `anonimo` | |
| `corredor_localidad` | text | |
| `interes_declarado` | text | Para comunidades sin sistema de arquetipos |
| `arquetipo_id` | uuid, FK → `arquetipo.id` | |
| `arquetipo_confianza` | numeric(3,2) | 0–1 |
| `arquetipo_estado` | text | `preliminar` \| `confirmado` |
| `nivel_activacion` | smallint | 1–5 |
| `nivel_activacion_actualizado_en` | timestamptz | |
| `semanas_consecutivas_activo` | smallint, default 0 | Insumo del criterio de Mapa de Voces |
| `fuente_utm_source/medium/campaign` | text | |
| `score_compuesto` | jsonb | Null hasta tener datos maduros |
| `consentimiento_registrado` | boolean, default false | Ley 25.326 |
| `referido_por_contacto_id` | uuid, FK → `contacto.id` | Quién trajo a este contacto. Null = no se cargó (no implica que no exista un referido) |
| `fecha_baja` | timestamptz | Marca explícita de abandono. Null = activo. Se carga a mano, nunca se infiere (`db/002_overview_metricas.sql`) |
| `manychat_subscriber_id` | text | Subscriber ID de ManyChat vinculado. Null = todavía no vinculado. Único por comunidad (no globalmente — cada comunidad puede tener su propia cuenta de ManyChat). Sin esto, `activacion-manychat` no puede direccionarle un tag (`db/006_activaciones_whatsapp.sql`) |
| `fecha_alta`, `created_at`, `updated_at` | timestamptz | |

Constraint: `(comunidad_id, telefono_hash)` único — el mismo teléfono en otra comunidad es una persona distinta a los fines de este CRM (comunidades aisladas entre sí).

### `contacto_afinidad_eje`
Afinidad narrativa de un contacto por eje temático (un contacto puede tener varios ejes con distinto score).

| Columna | Tipo |
|---|---|
| `contacto_id` | uuid, FK, parte de la PK |
| `eje` | text, parte de la PK — ej. `'Seguridad'` |
| `score` | numeric(3,2), 0–1 |
| `actualizado_en` | timestamptz |

### `evento_journey`

| Columna | Tipo | Notas |
|---|---|---|
| `id` | uuid, PK | |
| `contacto_id` | uuid, FK → `contacto.id` | |
| `comunidad_id` | uuid, FK → `comunidad.id` | Denormalizado a propósito (acelera RLS/queries por comunidad) |
| `tipo` | text | `awareness`\|`clic`\|`lead`\|`whatsapp`\|`activacion`\|`encuesta`\|`encuentro` |
| `fecha` | timestamptz | |
| `metadata` | jsonb | ej. `{"ad_id": "..."}` |

### `usuario_comunidad`
Puente `auth.users` ↔ comunidad ↔ rol. `comunidad_id = null` modela acceso global (así se define hoy `admin_taquion`).

| Columna | Tipo |
|---|---|
| `id` | uuid, PK |
| `usuario_id` | uuid, FK → `auth.users.id` |
| `comunidad_id` | uuid, FK → `comunidad.id`, nullable |
| `rol` | `rol_crm` |
| `creado_en` | timestamptz |

### `exportacion_log`
Audit log obligatorio de toda exportación Nivel 2/3 (Nivel 1 no lo requiere).

| Columna | Tipo | Notas |
|---|---|---|
| `nivel` | `nivel_exportacion` | |
| `usuario_id` | uuid, FK → `auth.users.id`, nullable | |
| `usuario_label` | text | Fallback legible |
| `motivo` | text | Obligatorio si `nivel = '2'` (`check`) |
| `formato` | text | `csv`\|`xlsx` — solo niveles 1/2 |
| `destino` | text | `meta_custom_audience`\|`google_sheets`\|`airtable` — solo nivel 3 |

### `importacion_log`

| Columna | Tipo |
|---|---|
| `origen` | `planilla_todo_un_pais`\|`export_manychat`\|`otro` |
| `archivo_nombre` | text |
| `filas_totales`, `filas_nuevas`, `filas_duplicadas` | int |
| `importado_por` | text |

### `activacion`
Registro propio del activo 5 (Activaciones). Definida en [`db/003_activaciones.sql`](../../db/003_activaciones.sql).

| Columna | Tipo | Notas |
|---|---|---|
| `id` | uuid, PK | |
| `comunidad_id` | uuid, FK → `comunidad.id` on delete cascade | |
| `nombre` | text, not null | |
| `tipo` | text | `sponsor_anunciante` \| `marca_contratante` |
| `objetivo_negocio` | text | |
| `brief` | text | |
| `fecha_inicio` / `fecha_fin` | date | |
| `kpi_objetivo` / `kpi_resultado` | jsonb | Shape libre (ej. `{"leads_calificados": 500}`) — cada activación puede medir cosas distintas, mismo criterio que `contacto.score_compuesto` |
| `estado` | text | `planificada` \| `en_curso` \| `cerrada` \| `cancelada` |
| `formato_operativo` | text, nullable | `entrevista_indagatoria` \| `promocion` \| `anuncio_lanzamiento` — qué tipo de acción es, eje independiente de `tipo` (`db/006_activaciones_whatsapp.sql`) |
| `responsable` | text | Nombre del AM a cargo, texto libre |
| `responsable_usuario_id` | uuid, FK → `auth.users.id`, nullable | Para cuando `am_estratega` tenga login real |
| `created_at` / `updated_at` | timestamptz | |

### `activacion_disparo`
Audit log de cada intento de disparo hacia ManyChat/WhatsApp para una activación. Definida en [`db/006_activaciones_whatsapp.sql`](../../db/006_activaciones_whatsapp.sql).

| Columna | Tipo | Notas |
|---|---|---|
| `id` | uuid, PK | |
| `activacion_id` | uuid, FK → `activacion.id` on delete cascade | |
| `filtro_usado` | jsonb | Filtro de segmento aplicado (`arquetipo_id`/`corredor_localidad`/`estado_identificacion`) |
| `cantidad_contactos` | int | Contactos incluidos en el disparo |
| `tag_manychat` | text | Tag aplicado (`activacion_<id>`) |
| `estado` | text | `ok` \| `parcial` \| `error` |
| `respuesta_api` | jsonb | Resultado crudo de la llamada a ManyChat, o el motivo del error |
| `disparado_por` | text | Email del admin que disparó |
| `creado_en` | timestamptz | |

Sin ninguna FK hacia `contacto` ni `evento_journey` — deliberado, ver [Modelo de identificación y gobernanza de exportación](../explanation/modelo-de-identificacion-y-gobernanza-de-exportacion.md#activaciones-activo-5-por-qué-no-toca-crecimiento).

### `temporada`
Fechas de cada temporada por comunidad — `comunidad.temporada_numero`/`fecha_inicio_temporada` solo guardan la actual, esta tabla guarda el historial. Definida en [`db/004_informe_decision_insumo.sql`](../../db/004_informe_decision_insumo.sql).

| Columna | Tipo | Notas |
|---|---|---|
| `comunidad_id` | uuid, FK → `comunidad.id`, parte de la PK | |
| `numero` | int, parte de la PK | |
| `fecha_inicio` | date, not null | |
| `fecha_fin` | date, nullable | Null = temporada abierta |

### `informe_decision`
El análisis cualitativo del cierre de temporada — se escribe a mano, ningún objeto del esquema le escribe automáticamente. Definida en [`db/004_informe_decision_insumo.sql`](../../db/004_informe_decision_insumo.sql).

| Columna | Tipo | Notas |
|---|---|---|
| `comunidad_id`, `temporada_numero` | PK compuesta, FK → `temporada` | |
| `semaforo` | text | `verde` \| `amarillo` \| `rojo` |
| `aprendizajes` | text | |
| `plan_accion` | jsonb | `[{accion, prioridad, responsable, fecha_limite}, ...]` |
| `escrito_por` | text | |
| `creado_en` / `actualizado_en` | timestamptz | |

## Vistas

### `mapa_de_voces`
**No es una tabla** — filtro sobre `contacto`. Criterio: `estado_identificacion in ('enriquecido','confirmado') and nivel_activacion >= 4 and semanas_consecutivas_activo >= 3`. `security_invoker = true` (respeta el RLS de `contacto` según quien consulta, no los permisos de quien la creó). Nunca otorgar `SELECT` sobre esta vista al rol `cliente`.

### `export_nivel1_agregado`
Base del export Nivel 1: agregado por `comunidad_id`, `corredor_localidad`, arquetipo/interés, `nivel_activacion` y `estado_identificacion`, con `cantidad_contactos`. Sin nombre/teléfono/username — estructuralmente no se puede "exportar de más" desde acá. `security_invoker = true`.

### `overview_por_barrio`
Definida en [`db/002_overview_metricas.sql`](../../db/002_overview_metricas.sql). Agregado por `comunidad_id` y `corredor_localidad` (coalescido a `'sin asignar'`), con `cantidad_contactos` y `nivel_activacion_promedio`. Excluye contactos con `fecha_baja` no nula. `security_invoker = true`. Base de la sección "Por barrio / corredor" de la pestaña Overview.

### `overview_por_arquetipo`
Mismo archivo. Agregado por `comunidad_id` y arquetipo (nombre, o `interes_declarado` si la comunidad no usa arquetipos, o `'sin arquetipo'`), con `cantidad_contactos` y `nivel_activacion_promedio`. Excluye contactos con `fecha_baja` no nula. `security_invoker = true`.

### `comunidad_metricas`
Una fila por comunidad con `total_contactos`, `contactos_activos`, `contactos_dados_de_baja`, `contactos_engaged`, `engagement_rate`, `tasa_referidos` y `tasa_abandono`. `engagement_rate` es real hoy (se apoya en `nivel_activacion`, ya poblado); `tasa_referidos` y `tasa_abandono` dependen de que se cargue `referido_por_contacto_id`/`fecha_baja` — devuelven `0` honestamente hasta que eso pase, nunca se infieren. Ver el porqué en [Modelo de identificación y gobernanza de exportación](../explanation/modelo-de-identificacion-y-gobernanza-de-exportacion.md#overview-y-métricas-de-performance). `security_invoker = true`.

### `informe_decision_insumo`
Definida en [`db/004_informe_decision_insumo.sql`](../../db/004_informe_decision_insumo.sql). Una fila por `comunidad_id` + `temporada_numero` (join con `temporada`), con dos lecturas por fila: **foto acumulada al cierre** (`total_contactos`, `contactos_activos`, `contactos_dados_de_baja`, `engagement_rate`, `tasa_referidos`, `tasa_abandono`, `cantidad_mapa_de_voces`, todas acotadas a `fecha_fin` o a hoy si la temporada sigue abierta) y **actividad ocurrida en la temporada** (`contactos_nuevos_temporada`, `referidos_temporada`, `bajas_temporada`, acotadas al rango `fecha_inicio`–`fecha_fin`). `engagement_rate` no tiene versión de período: `nivel_activacion` no tiene tabla de historial, así que solo puede leerse como foto. 100% automática — nunca escribe el análisis cualitativo, eso vive en `informe_decision`. Devuelve 0 filas para una comunidad sin fila en `temporada` todavía. `security_invoker = true`. Ver [Modelo de identificación y gobernanza de exportación](../explanation/modelo-de-identificacion-y-gobernanza-de-exportacion.md#informe-de-decisión-ejecutiva-insumo-automático-vs-informe-escrito-a-mano).

## Funciones

| Función | Qué hace |
|---|---|
| `set_updated_at()` | Trigger genérico: pone `updated_at = now()` en cada update |
| `seed_activos_comunidad()` | Trigger: crea las 6 filas de `comunidad_activo` al insertar una `comunidad` |
| `anonimizar_contacto(p_contacto_id, p_motivo)` | Única forma soportada de retroceder un contacto a `pseudo_anonimo`, borrando teléfono/nombre/username. Siempre explícita, nunca automática |
| `es_admin(p_uid)` | `security definer` — chequea si `p_uid` tiene una fila en `usuario_comunidad` con `rol = 'admin_taquion'` y `comunidad_id is null`, sin pasar por el RLS de esa misma tabla (evita el candado circular) |

## RLS y permisos

Las 9 tablas tienen RLS habilitado. Hoy solo existe la policy `admin_full_access` (usa `es_admin(auth.uid())`) en todas ellas — las de `am_estratega`/`cliente` están como plantilla comentada en el archivo SQL, para activar cuando esos roles salgan de backlog.

Además del RLS, el schema necesita sus propios `GRANT` (Supabase no los aplica automático fuera de `public`) — ver el bloque final de `001_init_crm_comunidades.sql` y la explicación en [Seguridad: RLS, GRANTs y visibilidad de Netlify](../explanation/seguridad-rls-grants-y-netlify.md).
