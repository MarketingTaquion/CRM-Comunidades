-- ============================================================================
-- CRM de Comunidades — Overview y métricas de performance
-- Ref: pedido de producto 2026-09-17 ("división por barrio y arquetipos en
-- pestaña nueva de overview" + "métricas de performance: abandono,
-- engagement, tasa de referidos").
--
-- "Barrio" = crm_comunidades.contacto.corredor_localidad (campo ya existente,
-- confirmado con el usuario — no se agrega columna nueva para esto).
--
-- Aplicar después de 001_init_crm_comunidades.sql. Idempotente.
-- ============================================================================
set search_path = crm_comunidades, public;

-- ----------------------------------------------------------------------------
-- Referidos y abandono: campos nuevos en contacto.
-- Ambos arrancan vacíos para TODA la base existente — no se infieren
-- retroactivamente. Mismo criterio que anonimizar_contacto(): una acción
-- explícita, nunca automática, mientras no exista el job de detección
-- (README "Qué falta").
-- ----------------------------------------------------------------------------
alter table crm_comunidades.contacto
  add column if not exists referido_por_contacto_id uuid references crm_comunidades.contacto(id);

alter table crm_comunidades.contacto
  add column if not exists fecha_baja timestamptz;

create index if not exists idx_contacto_referido_por
  on crm_comunidades.contacto (referido_por_contacto_id) where referido_por_contacto_id is not null;

comment on column crm_comunidades.contacto.referido_por_contacto_id is
  'Contacto que trajo a este. NULL = no se cargó un referido (no implica que no exista, solo que nadie lo registró todavía).';
comment on column crm_comunidades.contacto.fecha_baja is
  'Marca explícita de abandono de la comunidad. NULL = activo. Se carga a mano hasta que exista un job de detección automática de inactividad (backlog).';

-- ----------------------------------------------------------------------------
-- VISTA: overview_por_barrio
-- Base de la sección "Por barrio / corredor" de la pestaña Overview.
-- ----------------------------------------------------------------------------
create or replace view crm_comunidades.overview_por_barrio as
select
  comunidad_id,
  coalesce(corredor_localidad, 'sin asignar') as corredor_localidad,
  count(*) as cantidad_contactos,
  round(avg(nivel_activacion), 2) as nivel_activacion_promedio
from crm_comunidades.contacto
where fecha_baja is null
group by 1, 2;

alter view crm_comunidades.overview_por_barrio set (security_invoker = true);
comment on view crm_comunidades.overview_por_barrio is
  'Desglose de contactos activos por corredor_localidad ("barrio"), para la pestaña Overview.';

-- ----------------------------------------------------------------------------
-- VISTA: overview_por_arquetipo
-- ----------------------------------------------------------------------------
create or replace view crm_comunidades.overview_por_arquetipo as
select
  c.comunidad_id,
  coalesce(a.nombre, c.interes_declarado, 'sin arquetipo') as arquetipo,
  count(*) as cantidad_contactos,
  round(avg(c.nivel_activacion), 2) as nivel_activacion_promedio
from crm_comunidades.contacto c
left join crm_comunidades.arquetipo a on a.id = c.arquetipo_id
where c.fecha_baja is null
group by 1, 2;

alter view crm_comunidades.overview_por_arquetipo set (security_invoker = true);
comment on view crm_comunidades.overview_por_arquetipo is
  'Desglose de contactos activos por arquetipo (o interés declarado si la comunidad no usa arquetipos), para la pestaña Overview.';

-- ----------------------------------------------------------------------------
-- VISTA: comunidad_metricas
-- engagement_rate es real (se apoya en nivel_activacion, ya poblado hoy).
-- tasa_referidos / tasa_abandono son honestas pero arrancan en 0 para
-- cualquier comunidad sin carga manual todavía — no se fabrican ni se
-- infieren (mismo principio que Conocimiento/Voz en el resto del panel).
-- ----------------------------------------------------------------------------
create or replace view crm_comunidades.comunidad_metricas as
select
  comunidad_id,
  count(*) as total_contactos,
  count(*) filter (where fecha_baja is null) as contactos_activos,
  count(*) filter (where fecha_baja is not null) as contactos_dados_de_baja,
  count(*) filter (where nivel_activacion >= 3 and fecha_baja is null) as contactos_engaged,
  round(
    count(*) filter (where nivel_activacion >= 3 and fecha_baja is null)::numeric
    / nullif(count(*) filter (where fecha_baja is null), 0), 4
  ) as engagement_rate,
  round(
    count(*) filter (where referido_por_contacto_id is not null)::numeric
    / nullif(count(*), 0), 4
  ) as tasa_referidos,
  round(
    count(*) filter (where fecha_baja is not null)::numeric
    / nullif(count(*), 0), 4
  ) as tasa_abandono
from crm_comunidades.contacto
group by 1;

alter view crm_comunidades.comunidad_metricas set (security_invoker = true);
comment on view crm_comunidades.comunidad_metricas is
  'Métricas de performance por comunidad. engagement_rate se calcula sobre nivel_activacion (real hoy). tasa_referidos y tasa_abandono dependen de referido_por_contacto_id / fecha_baja — arrancan en 0 hasta que el equipo las cargue, nunca se infieren.';

-- ----------------------------------------------------------------------------
-- GRANTs — mismo patrón que 001_init_crm_comunidades.sql. Los defaults ya
-- aplicados ahí (ALTER DEFAULT PRIVILEGES ... ON TABLES) cubren vistas
-- nuevas creadas por el mismo rol, pero se declaran explícitos acá también
-- para que este archivo sea autocontenido si se corre en un proyecto nuevo.
-- ----------------------------------------------------------------------------
grant select on crm_comunidades.overview_por_barrio to anon, authenticated, service_role;
grant select on crm_comunidades.overview_por_arquetipo to anon, authenticated, service_role;
grant select on crm_comunidades.comunidad_metricas to anon, authenticated, service_role;
