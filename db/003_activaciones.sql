-- ============================================================================
-- CRM de Comunidades — Activaciones (activo 5) como tabla propia
-- Ref: specs/2026-09-18-activaciones-tabla.md (aprobado 2026-09-18)
--
-- Reemplaza el contenido de ejemplo hardcodeado de renderActivaciones() en
-- index.html. Deliberadamente SIN ninguna FK hacia contacto/evento_journey:
-- una activación es un proyecto de negocio (sponsor/marca) sobre la
-- comunidad ya existente, no un evento de adquisición orgánica — no debe
-- mezclarse con comunidad_metricas/overview_por_barrio/overview_por_arquetipo
-- (db/002_overview_metricas.sql), que siguen sin tocarse acá.
--
-- Aplicar después de 002_overview_metricas.sql. Idempotente.
-- ============================================================================
set search_path = crm_comunidades, public;

-- ----------------------------------------------------------------------------
-- TABLA: activacion
-- ----------------------------------------------------------------------------
create table if not exists crm_comunidades.activacion (
  id                     uuid primary key default gen_random_uuid(),
  comunidad_id           uuid not null references crm_comunidades.comunidad(id) on delete cascade,
  nombre                 text not null,
  tipo                   text not null check (tipo in ('sponsor_anunciante','marca_contratante')),
  objetivo_negocio       text,
  brief                  text,
  fecha_inicio           date,
  fecha_fin              date,
  kpi_objetivo           jsonb,   -- ej. {"leads_calificados": 500, "engagement_rate": 0.2}
  kpi_resultado          jsonb,   -- mismo shape que kpi_objetivo, se completa al cierre
  estado                 text not null default 'planificada'
                           check (estado in ('planificada','en_curso','cerrada','cancelada')),
  responsable            text,    -- nombre del AM a cargo (texto libre — no hay login am_estratega todavía)
  responsable_usuario_id uuid references auth.users(id),  -- nullable, para cuando am_estratega tenga login real
  created_at             timestamptz not null default now(),
  updated_at             timestamptz not null default now(),
  constraint chk_activacion_fechas check (fecha_fin is null or fecha_inicio is null or fecha_fin >= fecha_inicio)
);

drop trigger if exists trg_activacion_updated_at on crm_comunidades.activacion;
create trigger trg_activacion_updated_at
  before update on crm_comunidades.activacion
  for each row execute function crm_comunidades.set_updated_at();

create index if not exists idx_activacion_comunidad_estado on crm_comunidades.activacion (comunidad_id, estado);

comment on table crm_comunidades.activacion is
  'Registro propio del activo 5 (Activaciones) — deliberadamente separado de contacto/evento_journey de adquisición orgánica (Crecimiento). kpi_objetivo/kpi_resultado en jsonb porque cada activación puede medir cosas distintas (mismo criterio que contacto.score_compuesto).';
comment on column crm_comunidades.activacion.responsable is
  'Nombre del AM a cargo, texto libre. responsable_usuario_id queda listo para cuando el rol am_estratega tenga login real (backlog, specs/006).';

-- ----------------------------------------------------------------------------
-- RLS — mismo patrón que 001: policy real para admin_taquion, plantilla
-- comentada para am_estratega/cliente.
-- ----------------------------------------------------------------------------
alter table crm_comunidades.activacion enable row level security;

drop policy if exists admin_full_access on crm_comunidades.activacion;
create policy admin_full_access on crm_comunidades.activacion for all
  using (crm_comunidades.es_admin(auth.uid())) with check (crm_comunidades.es_admin(auth.uid()));

-- Plantilla para cuando am_estratega salga de backlog (NO ejecutar todavía):
--
-- create policy am_estratega_su_comunidad on crm_comunidades.activacion for select
--   using (exists (
--     select 1 from crm_comunidades.usuario_comunidad uc
--     where uc.usuario_id = auth.uid() and uc.rol = 'am_estratega'
--       and uc.comunidad_id = activacion.comunidad_id
--   ));
--
-- Plantilla para cuando cliente salga de backlog (NO ejecutar todavía).
-- A diferencia de contacto/mapa_de_voces, esta tabla no tiene datos nominales
-- de miembros — no hay razón de gobernanza para ocultarle Activaciones al
-- cliente cuando el rol exista, más allá de acotarlo a su propia comunidad:
--
-- create policy cliente_su_comunidad on crm_comunidades.activacion for select
--   using (exists (
--     select 1 from crm_comunidades.usuario_comunidad uc
--     where uc.usuario_id = auth.uid() and uc.rol = 'cliente'
--       and uc.comunidad_id = activacion.comunidad_id
--   ));

-- ----------------------------------------------------------------------------
-- GRANTs — los ALTER DEFAULT PRIVILEGES de 001 ya cubrirían esto si se migra
-- con el mismo rol, pero se declara explícito para que este archivo sea
-- autocontenido si se corre en un proyecto nuevo (mismo criterio que 002).
-- ----------------------------------------------------------------------------
grant select, insert, update, delete on crm_comunidades.activacion to authenticated, service_role;
grant select on crm_comunidades.activacion to anon;
