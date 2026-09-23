-- ============================================================================
-- Activaciones nativas de WhatsApp — pivot a tratamiento de leads
-- Ref: specs/2026-09-23-pivot-leads-whatsapp.md,
--      specs/2026-09-18-utm-manychat-y-disparo-campanas.md (diseño original
--      de activacion_disparo, ahora implementado acá)
--
-- Tres piezas, deliberadamente independientes:
--   1. activacion.formato_operativo — clasifica QUÉ tipo de acción es
--      (entrevista indagatoria / promoción / anuncio de lanzamiento), sin
--      tocar activacion.tipo (que sigue siendo el eje comercial: sponsor
--      vs. marca contratante — db/003_activaciones.sql). Son dos ejes
--      distintos, nunca se combinan en una sola columna.
--   2. contacto.manychat_subscriber_id — el vínculo que falta hoy entre un
--      contacto del CRM y su suscriptor real en ManyChat. Sin esto no se
--      puede direccionar un tag por WhatsApp a nadie. Arranca vacía para
--      toda la base existente — poblarla depende de la Fase 3 del roadmap
--      (webhook ManyChat → CRM, todavía sin construir) o de carga manual
--      para pruebas puntuales.
--   3. activacion_disparo — audit log de cada intento de disparo, mismo
--      nivel de trazabilidad que exportacion_log: qué activación, qué
--      filtro, cuántos contactos, resultado de la llamada a ManyChat.
--
-- Aplicar después de 005_api_publica.sql. Idempotente.
-- ============================================================================
set search_path = crm_comunidades, public;

-- ----------------------------------------------------------------------------
-- activacion.formato_operativo
-- ----------------------------------------------------------------------------
alter table crm_comunidades.activacion
  add column if not exists formato_operativo text
  check (formato_operativo in ('entrevista_indagatoria','promocion','anuncio_lanzamiento'));

comment on column crm_comunidades.activacion.formato_operativo is
  'Qué tipo de acción es (entrevista indagatoria / promoción / anuncio de lanzamiento) — eje independiente de "tipo" (sponsor_anunciante/marca_contratante, quién la pide). Nullable: las activaciones ya cargadas antes del pivot no lo tienen retroactivamente.';

-- ----------------------------------------------------------------------------
-- contacto.manychat_subscriber_id
-- Único por comunidad, no globalmente: cada comunidad puede tener su propia
-- cuenta/página de ManyChat (specs/2026-09-18-utm-manychat...), así que el
-- mismo subscriber_id en dos comunidades distintas no implica la misma
-- persona — mismo criterio que uq_contacto_telefono_por_comunidad (db/001).
-- ----------------------------------------------------------------------------
alter table crm_comunidades.contacto
  add column if not exists manychat_subscriber_id text;

comment on column crm_comunidades.contacto.manychat_subscriber_id is
  'Subscriber ID de ManyChat vinculado a este contacto. NULL = todavía no vinculado (nadie lo cargó, o llegó por un canal que no es ManyChat). Sin esto, activacion-manychat no puede direccionarle un tag.';

create unique index if not exists uq_contacto_manychat_subscriber_por_comunidad
  on crm_comunidades.contacto (comunidad_id, manychat_subscriber_id)
  where manychat_subscriber_id is not null;

-- ----------------------------------------------------------------------------
-- TABLA: activacion_disparo
-- ----------------------------------------------------------------------------
create table if not exists crm_comunidades.activacion_disparo (
  id               uuid primary key default gen_random_uuid(),
  activacion_id    uuid not null references crm_comunidades.activacion(id) on delete cascade,
  filtro_usado     jsonb not null default '{}'::jsonb,
  cantidad_contactos int not null default 0,
  tag_manychat     text not null,
  estado           text not null check (estado in ('ok','parcial','error')),
  respuesta_api    jsonb,
  disparado_por    text,
  creado_en        timestamptz not null default now()
);

comment on table crm_comunidades.activacion_disparo is
  'Audit log de cada intento de disparo hacia ManyChat/WhatsApp para una activación — mismo nivel de trazabilidad que exportacion_log. estado=parcial cuando algunos contactos del segmento fallaron y otros no.';

alter table crm_comunidades.activacion_disparo enable row level security;

drop policy if exists admin_full_access on crm_comunidades.activacion_disparo;
create policy admin_full_access on crm_comunidades.activacion_disparo for all
  using (crm_comunidades.es_admin(auth.uid())) with check (crm_comunidades.es_admin(auth.uid()));

-- ----------------------------------------------------------------------------
-- GRANTs — declarados explícitos, mismo criterio que 002-005.
-- ----------------------------------------------------------------------------
grant select, insert, update, delete on crm_comunidades.activacion_disparo to authenticated, service_role;
grant select on crm_comunidades.activacion_disparo to anon;
