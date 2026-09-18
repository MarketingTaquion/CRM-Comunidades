# Spec — Tabla propia `activacion` (activo 5)

Estado: propuesta, pendiente de revisión. Migración prevista: `db/003_activaciones.sql` (no escrita todavía).

## Qué es

Hoy Activaciones (5) se renderiza en `index.html` con contenido de ejemplo hardcodeado (`renderActivaciones()`), marcado explícitamente como tal. Esta tarea reemplaza ese hardcodeo por una tabla real `crm_comunidades.activacion`, con **su propio registro de medición, deliberadamente separado** de `contacto`/`evento_journey` (que son de adquisición orgánica, Crecimiento) — una activación no es un contacto nuevo ni un evento de journey, es un proyecto de negocio (sponsor/marca) que corre sobre la comunidad ya existente.

## Tabla `crm_comunidades.activacion`

```sql
create table if not exists crm_comunidades.activacion (
  id                uuid primary key default gen_random_uuid(),
  comunidad_id      uuid not null references crm_comunidades.comunidad(id) on delete cascade,
  nombre            text not null,
  tipo              text not null check (tipo in ('sponsor_anunciante','marca_contratante')),
  objetivo_negocio  text,
  brief             text,
  fecha_inicio      date,
  fecha_fin         date,
  kpi_objetivo      jsonb,   -- ej. {"leads_calificados": 500, "engagement_rate": 0.2}
  kpi_resultado     jsonb,   -- mismo shape que kpi_objetivo, se completa al cierre
  estado            text not null default 'planificada'
                      check (estado in ('planificada','en_curso','cerrada','cancelada')),
  responsable       text,    -- nombre del AM a cargo (texto libre — no hay login am_estratega todavía)
  responsable_usuario_id uuid references auth.users(id),  -- nullable, para cuando am_estratega tenga login real
  created_at        timestamptz not null default now(),
  updated_at        timestamptz not null default now(),
  check (fecha_fin is null or fecha_inicio is null or fecha_fin >= fecha_inicio)
);
```

**Por qué `kpi_objetivo`/`kpi_resultado` en `jsonb` y no columnas fijas:** cada activación puede medir cosas distintas (leads, alcance, revenue, asistencia a un encuentro) — mismo criterio ya usado en `contacto.score_compuesto` (jsonb hasta que el dato madure lo suficiente como para fijar columnas). Si en la práctica todas las activaciones terminan midiendo 1-2 KPIs fijos, es fácil migrar a columnas después; lo inverso (columnas fijas → jsonb) es más costoso.

**Por qué NO se agrega todavía una tabla de medición histórica (`activacion_medicion` con una fila por corte de fecha):** el pedido mínimo fue `kpi_objetivo`/`kpi_resultado` (una foto, no una serie temporal). Si en la revisión se confirma que se necesita trackear la evolución del KPI en el tiempo (no solo objetivo vs. resultado final), se suma en una migración aparte (`004_...`) sin tocar esta tabla — decisión que dejo abierta para que la confirmes antes de sobre-construir.

**Índice:** `create index on crm_comunidades.activacion (comunidad_id, estado);` — para el filtro más común (activaciones en curso de una comunidad).

## Separación de Crecimiento — explícita

- Ninguna columna de `activacion` referencia `contacto.id` ni `evento_journey.id` directamente.
- `comunidad_metricas`, `overview_por_barrio`, `overview_por_arquetipo` (`db/002`) no cambian ni se tocan.
- Si más adelante se necesita cruzar "¿esta activación generó nuevos contactos?", eso es una vista aparte que joinee por `comunidad_id` + rango de fechas — no una FK directa — para que `activacion` siga siendo válida incluso para comunidades/activaciones que no buscan adquisición (ej. un evento de fidelización).

## RLS y permisos (mismo patrón que el resto del schema)

```sql
alter table crm_comunidades.activacion enable row level security;

drop policy if exists admin_full_access on crm_comunidades.activacion;
create policy admin_full_access on crm_comunidades.activacion for all
  using (crm_comunidades.es_admin(auth.uid())) with check (crm_comunidades.es_admin(auth.uid()));

grant select, insert, update, delete on crm_comunidades.activacion to authenticated, service_role;
grant select on crm_comunidades.activacion to anon;
```

(Los `alter default privileges` de `001` ya cubrirían esto automáticamente si migro con el mismo rol, pero lo declaro explícito para que el archivo `003` sea autocontenido — mismo criterio que `002`.)

Plantilla comentada (no ejecutar todavía), siguiendo el mismo patrón que `contacto`:

```sql
-- am_estratega ve las activaciones de su(s) comunidad(es) asignada(s):
-- create policy am_estratega_su_comunidad on crm_comunidades.activacion for select
--   using (exists (select 1 from crm_comunidades.usuario_comunidad uc
--     where uc.usuario_id = auth.uid() and uc.rol = 'am_estratega'
--       and uc.comunidad_id = activacion.comunidad_id));
--
-- cliente ve las activaciones de SU comunidad únicamente (es contenido de negocio,
-- no dato nominal de contacto — a diferencia de mapa_de_voces, no hay razón de
-- gobernanza para ocultárselo al cliente cuando el rol exista):
-- create policy cliente_su_comunidad on crm_comunidades.activacion for select
--   using (exists (select 1 from crm_comunidades.usuario_comunidad uc
--     where uc.usuario_id = auth.uid() and uc.rol = 'cliente'
--       and uc.comunidad_id = activacion.comunidad_id));
```

No expone `telefono_plano`/`nombre_declarado`/nada de `contacto` — no aplica la restricción de exportación por niveles (esa tabla no tiene datos de identidad de miembros).

## Qué se loguea

No aplica audit log tipo `exportacion_log` acá — crear/editar una activación no exporta datos personales. `created_at`/`updated_at` (trigger `set_updated_at`, mismo patrón que `comunidad`/`contacto`) alcanza para trazabilidad de cambios.

## Documentación (Diátaxis)

- `docs/reference/esquema-de-base-de-datos.md`: sección nueva para `activacion`.
- `docs/how-to/`: nuevo `registrar-una-activacion.md` (cómo cargar una activación desde el panel, una vez construida la UI).
- `docs/explanation/`: nota corta en `arquitectura-y-aislamiento-de-datos.md` o `modelo-de-identificacion-y-gobernanza-de-exportacion.md` explicando por qué Activaciones no toca `contacto`/`evento_journey`.

## Criterios de aceptación

- [ ] `db/003_activaciones.sql` crea la tabla, RLS, policy `admin_full_access`, grants — idempotente (`create if not exists` / `drop policy if exists`), igual que 001/002.
- [ ] Ninguna columna ni FK de `activacion` referencia `contacto` o `evento_journey`.
- [ ] `comunidad_metricas`/`overview_por_*` no cambian.
- [ ] El frontend (`renderActivaciones`) pasa a leer de la tabla real y deja de mostrar "Contenido de ejemplo" — o, si todavía no hay UI de carga, muestra un estado vacío real ("Sin activaciones cargadas todavía") en vez de datos de ejemplo.
- [ ] Lectura de KPIs siempre por comunidad — ninguna vista/consulta promedia `kpi_resultado` entre comunidades distintas.
- [ ] Documentación Diátaxis actualizada (reference + explanation, how-to si ya hay UI).
