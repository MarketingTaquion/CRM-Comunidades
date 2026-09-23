-- ============================================================================
-- Tratos (deals) — pipeline propio, separado de estado_identificacion
-- Ref: pedido de producto 2026-09-23 ("añadir tratos/deals al embudo,
-- tarjetas que se puedan arrastrar y mover").
--
-- Por qué es una tabla nueva y no una columna más en contacto: un trato es
-- una oportunidad/negociación puntual (puede no tener contacto todavía,
-- puede nacer de una activación) — arrastrarlo de columna es una decisión
-- manual del equipo, y eso es exactamente lo que se espera de un trato.
-- estado_identificacion, en cambio, avanza solo por criterios reales (ver
-- specs/006 y docs/explanation/modelo-de-identificacion...) — nunca se
-- fuerza a mano. Mezclar los dos en una sola escalera rompería esa regla.
--
-- Aplicar después de 006_activaciones_whatsapp.sql. Idempotente.
-- ============================================================================
set search_path = crm_comunidades, public;

create table if not exists crm_comunidades.trato (
  id             uuid primary key default gen_random_uuid(),
  comunidad_id   uuid not null references crm_comunidades.comunidad(id) on delete cascade,
  contacto_id    uuid references crm_comunidades.contacto(id) on delete set null,
  activacion_id  uuid references crm_comunidades.activacion(id) on delete set null,
  nombre         text not null,
  estado         text not null default 'nuevo'
                   check (estado in ('nuevo','contactado','en_proceso','ganado','perdido')),
  created_at     timestamptz not null default now(),
  updated_at     timestamptz not null default now()
);

drop trigger if exists trg_trato_updated_at on crm_comunidades.trato;
create trigger trg_trato_updated_at
  before update on crm_comunidades.trato
  for each row execute function crm_comunidades.set_updated_at();

create index if not exists idx_trato_comunidad_estado on crm_comunidades.trato (comunidad_id, estado);

comment on table crm_comunidades.trato is
  'Pipeline de oportunidades (deals), independiente de contacto.estado_identificacion. contacto_id y activacion_id son opcionales: un trato puede existir antes de tener un contacto puntual asociado, o nacer de una activación.';

alter table crm_comunidades.trato enable row level security;

drop policy if exists admin_full_access on crm_comunidades.trato;
create policy admin_full_access on crm_comunidades.trato for all
  using (crm_comunidades.es_admin(auth.uid())) with check (crm_comunidades.es_admin(auth.uid()));

-- Plantilla para cuando am_estratega/cliente salgan de backlog (NO ejecutar
-- todavía), mismo patrón que el resto del esquema:
--
-- create policy am_estratega_su_comunidad on crm_comunidades.trato for select
--   using (exists (
--     select 1 from crm_comunidades.usuario_comunidad uc
--     where uc.usuario_id = auth.uid() and uc.rol = 'am_estratega'
--       and uc.comunidad_id = trato.comunidad_id
--   ));

grant select, insert, update, delete on crm_comunidades.trato to authenticated, service_role;
grant select on crm_comunidades.trato to anon;
