-- ============================================================================
-- Medición y cohortes — foto semanal por comunidad/corredor
-- Ref: reunión Jazleidis/Juan (2026-09-23) + spec
-- specs/2026-09-24-medicion-y-cohortes.md.
--
-- Una "foto" es un evento guardado en el tiempo, no un cálculo al vuelo: se
-- necesita poder mirar cómo se veía una comunidad/corredor en una semana
-- puntual aunque los datos de `contacto` hayan cambiado después. Los campos
-- automáticos se recalculan en el momento de guardar la foto (mismo criterio
-- que `comunidad_metricas`, acotado a esa semana/corredor); los manuales
-- (inversión, CPL, conversaciones, clics) se cargan aparte — no se integran
-- con Pulso Ignite en esta fase (decisión 2026-09-24).
--
-- Aplicar después de 007_tratos.sql. Idempotente.
-- ============================================================================
set search_path = crm_comunidades, public;

create table if not exists crm_comunidades.metrica_semanal (
  id                      uuid primary key default gen_random_uuid(),
  comunidad_id            uuid not null references crm_comunidades.comunidad(id) on delete cascade,
  corredor_localidad      text,   -- null = foto de toda la comunidad; con valor = foto de ese corredor puntual
  semana_inicio           date not null,   -- lunes de la semana que representa esta foto

  -- auto-calculables al momento de guardar la foto
  contactos_nuevos        int not null default 0,
  contactos_activos       int not null default 0,
  contactos_dados_de_baja int not null default 0,
  engagement_rate         numeric(6,4),
  tasa_abandono           numeric(6,4),
  tasa_referidos          numeric(6,4),

  -- carga manual, aparte (decisión 2026-09-24) — nullable porque no todas las
  -- semanas van a tener el dato cargado a tiempo
  inversion_pauta         numeric(12,2),
  cpl                     numeric(12,2),
  conversaciones_meta     int,
  clics                   int,

  cargado_por             text,
  creado_en               timestamptz not null default now()
);

-- Dos índices únicos parciales en vez de un unique con NULL (Postgres trata
-- cada NULL como distinto, así que un unique normal no evitaría duplicar la
-- foto "toda la comunidad" de una misma semana). Mismo patrón que
-- uq_contacto_telefono_por_comunidad (db/001).
create unique index if not exists uq_metrica_semanal_comunidad
  on crm_comunidades.metrica_semanal (comunidad_id, semana_inicio)
  where corredor_localidad is null;

create unique index if not exists uq_metrica_semanal_corredor
  on crm_comunidades.metrica_semanal (comunidad_id, corredor_localidad, semana_inicio)
  where corredor_localidad is not null;

create index if not exists idx_metrica_semanal_comunidad_semana
  on crm_comunidades.metrica_semanal (comunidad_id, semana_inicio);

comment on table crm_comunidades.metrica_semanal is
  'Foto semanal guardada por comunidad/corredor — base de las cohortes de ingreso/retención. corredor_localidad NULL = total de la comunidad. Los campos automáticos se recalculan al guardar la foto; los manuales (inversión/CPL/conversaciones/clics) se cargan aparte, ver specs/2026-09-24-medicion-y-cohortes.md.';

alter table crm_comunidades.metrica_semanal enable row level security;

drop policy if exists admin_full_access on crm_comunidades.metrica_semanal;
create policy admin_full_access on crm_comunidades.metrica_semanal for all
  using (crm_comunidades.es_admin(auth.uid())) with check (crm_comunidades.es_admin(auth.uid()));

-- Plantilla para cuando am_estratega/cliente salgan de backlog (NO ejecutar
-- todavía), mismo patrón que el resto del esquema:
--
-- create policy am_estratega_su_comunidad on crm_comunidades.metrica_semanal for select
--   using (exists (
--     select 1 from crm_comunidades.usuario_comunidad uc
--     where uc.usuario_id = auth.uid() and uc.rol = 'am_estratega'
--       and uc.comunidad_id = metrica_semanal.comunidad_id
--   ));

grant select, insert, update, delete on crm_comunidades.metrica_semanal to authenticated, service_role;
grant select on crm_comunidades.metrica_semanal to anon;
