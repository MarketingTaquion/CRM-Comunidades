# Spec — Insumo cuantitativo para el Informe de Decisión Ejecutiva (cierre de temporada)

Estado: propuesta, pendiente de revisión. Migración prevista: `db/004_informe_decision_insumo.sql` (después de `003`, no escrita todavía). **Contiene una decisión de diseño que necesito que confirmes antes de migrar** (ver "Decisión a confirmar" abajo) — el resto del spec asume la opción A por default.

## Qué es (y qué NO es)

Por playbook de producto (specs/006, "Decisiones es la única vista que no se completa con datos en vivo: se escribe manualmente al cierre de cada temporada — semáforo contra el plan, aprendizajes, plan de acción"). Esta tarea construye **dos objetos separados a propósito**:

1. Una **vista de solo lectura** (`informe_decision_insumo`) que agrega lo cuantitativo ya instrumentado (Crecimiento/Relación) por comunidad y por temporada — números, cero texto.
2. Una **tabla escribible** (`informe_decision`) donde una persona (Insights/liderazgo) escribe el semáforo, los aprendizajes y el plan de acción — **nunca se autocompleta desde la vista**, ninguna función ni trigger escribe en esta tabla.

El job/vista dejan los números listos al lado; la lectura y la escritura del análisis siguen siendo 100% humanas. Esto se documenta explícito en el código (comentarios SQL) y en `docs/explanation/`, para que nadie en el futuro "optimice" agregando un default automático al semáforo.

## Decisión a confirmar: cómo se define el "cierre de temporada"

`comunidad` hoy solo guarda `temporada_numero` (la actual) y `fecha_inicio_temporada` (de la actual) — **no existe ningún registro de las fechas de temporadas anteriores**. Sin eso, no se puede construir un insumo agregado "por temporada" de verdad (solo "a la fecha de hoy").

Propongo agregar una tabla mínima, en el mismo espíritu que `comunidad_activo` (nunca se borra, se actualiza):

```sql
create table if not exists crm_comunidades.temporada (
  comunidad_id  uuid not null references crm_comunidades.comunidad(id) on delete cascade,
  numero        int not null,
  fecha_inicio  date not null,
  fecha_fin     date,   -- null mientras la temporada sigue abierta
  primary key (comunidad_id, numero)
);
```

Se inserta una fila cuando arranca una temporada (`fecha_inicio` = `comunidad.fecha_inicio_temporada` de ese momento) y se completa `fecha_fin` cuando cierra. **Esto es una tabla nueva, no pedida explícitamente por vos** — la propongo porque sin ella "insumo al cierre de temporada" no es construible con el esquema actual. Alternativa si preferís no sumar tabla: el insumo se calcula solo "a la fecha de hoy" para la temporada actual (`comunidad.temporada_numero`/`fecha_inicio_temporada`), sin poder reconstruir el cierre de temporadas pasadas. Decime cuál preferís.

Además, **¿el insumo es una foto acumulada al momento del cierre, o solo la actividad ocurrida dentro de esa temporada?** Ej.: `engagement_rate` de `comunidad_metricas` es acumulado desde siempre, no por ventana de fechas. Propongo por default la **foto acumulada al cierre** (`where fecha_alta <= fecha_fin`) porque el Informe de Decisión Ejecutiva típicamente responde "¿dónde estamos parados al cierre de la Temporada N?", no "¿qué pasó solo en estos 90 días aislado del resto?" — pero es una interpretación mía del playbook, no algo que specs/006 defina en detalle. Confirmame si es la lectura correcta.

## Vista `informe_decision_insumo` (asumiendo la opción A de arriba)

```sql
create or replace view crm_comunidades.informe_decision_insumo as
select
  t.comunidad_id,
  t.numero as temporada_numero,
  t.fecha_inicio,
  t.fecha_fin,
  count(c.*) filter (where c.fecha_alta <= coalesce(t.fecha_fin, now())) as total_contactos,
  count(c.*) filter (where c.fecha_alta <= coalesce(t.fecha_fin, now()) and c.fecha_baja is null) as contactos_activos,
  count(c.*) filter (where c.fecha_baja is not null and c.fecha_baja <= coalesce(t.fecha_fin, now())) as contactos_dados_de_baja,
  round(
    count(c.*) filter (where c.nivel_activacion >= 3 and c.fecha_baja is null and c.fecha_alta <= coalesce(t.fecha_fin, now()))::numeric
    / nullif(count(c.*) filter (where c.fecha_baja is null and c.fecha_alta <= coalesce(t.fecha_fin, now())), 0), 4
  ) as engagement_rate,
  round(
    count(c.*) filter (where c.referido_por_contacto_id is not null and c.fecha_alta <= coalesce(t.fecha_fin, now()))::numeric
    / nullif(count(c.*) filter (where c.fecha_alta <= coalesce(t.fecha_fin, now())), 0), 4
  ) as tasa_referidos,
  round(
    count(c.*) filter (where c.fecha_baja is not null and c.fecha_baja <= coalesce(t.fecha_fin, now()))::numeric
    / nullif(count(c.*) filter (where c.fecha_alta <= coalesce(t.fecha_fin, now())), 0), 4
  ) as tasa_abandono,
  count(distinct c.id) filter (
    where c.estado_identificacion in ('enriquecido','confirmado')
      and c.nivel_activacion >= 4 and c.semanas_consecutivas_activo >= 3
      and c.fecha_alta <= coalesce(t.fecha_fin, now())
  ) as cantidad_mapa_de_voces
from crm_comunidades.temporada t
join crm_comunidades.contacto c on c.comunidad_id = t.comunidad_id
group by 1,2,3,4;

alter view crm_comunidades.informe_decision_insumo set (security_invoker = true);
```

**Por qué reusa la lógica de `comunidad_metricas`/`mapa_de_voces` en vez de importarlas tal cual:** esas vistas no están acotadas por fecha (son "hoy, todo el histórico"); esta necesita el mismo cálculo pero acotado a `fecha_fin` de la temporada. Duplicar la fórmula acotada es más simple y explícito que intentar parametrizar una vista existente (Postgres no soporta vistas parametrizadas sin volverlas función).

**Nunca promedia entre comunidades** — el `group by` siempre incluye `comunidad_id`; no hay ninguna fila "todas las comunidades".

**No expone `telefono_plano`/`nombre_declarado`/`username`** — mismas columnas de identidad ausentes que en `comunidad_metricas`/`export_nivel1_agregado`. `cantidad_mapa_de_voces` es un conteo, no la lista nominal (esa sigue viviendo solo en la vista `mapa_de_voces`, con su mismo candado de RLS).

## Tabla `informe_decision` (lo que se escribe, nunca se genera)

```sql
create table if not exists crm_comunidades.informe_decision (
  comunidad_id    uuid not null references crm_comunidades.comunidad(id) on delete cascade,
  temporada_numero int not null,
  semaforo        text check (semaforo in ('verde','amarillo','rojo')),
  aprendizajes    text,
  plan_accion     jsonb,   -- [{accion, prioridad, responsable, fecha_limite}, ...]
  escrito_por     text,
  creado_en       timestamptz not null default now(),
  actualizado_en  timestamptz not null default now(),
  primary key (comunidad_id, temporada_numero),
  foreign key (comunidad_id, temporada_numero) references crm_comunidades.temporada(comunidad_id, numero)
);
```

Comentario explícito en el SQL (y repetido en la doc): *"Esta tabla se llena a mano. Ningún job, función ni trigger de este esquema escribe acá — si en el futuro alguien agrega un default automático a `semaforo` o `aprendizajes`, está rompiendo la regla de producto de que Decisiones es la única vista que no se llena con datos."*

## RLS y permisos (mismo patrón)

Ambos objetos (`temporada`, `informe_decision`) con `admin_full_access` + plantilla comentada am_estratega/cliente, igual que `activacion` en la Tarea 2. `informe_decision_insumo` con `security_invoker = true` como el resto de las vistas del schema.

## Documentación (Diátaxis)

- `docs/reference/esquema-de-base-de-datos.md`: `temporada`, `informe_decision`, `informe_decision_insumo`.
- `docs/explanation/modelo-de-identificacion-y-gobernanza-de-exportacion.md`: sección nueva explicando la separación insumo (vista, automática) vs. informe (tabla, humana) — mismo estilo que la sección ya existente sobre Conocimiento/Voz (contenido de ejemplo vs. dato real).
- `docs/how-to/`: `cerrar-una-temporada.md` (cómo completar `temporada.fecha_fin` y cargar el `informe_decision` correspondiente).

## Criterios de aceptación

- [ ] La vista `informe_decision_insumo` no requiere ningún input humano para poblarse — es 100% derivada de datos ya instrumentados.
- [ ] La tabla `informe_decision` no tiene ningún trigger, función ni default que la escriba automáticamente — solo `insert`/`update` manuales desde el panel.
- [ ] Ninguna fila de la vista mezcla datos de más de una comunidad.
- [ ] `informe_decision_insumo` no expone columnas de identidad de contacto.
- [ ] Decisión de "foto acumulada vs. actividad del período" y la tabla `temporada` quedan confirmadas por vos antes de escribir la migración.
