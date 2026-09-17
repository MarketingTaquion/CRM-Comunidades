-- ============================================================================
-- CRM de Comunidades — esquema inicial
-- Ref: specs/006-crm-comunidades.md
--
-- Este proyecto vive en el MISMO proyecto de Supabase que `pulso-ignite`,
-- pero apartado (decisión confirmada 2026-09-17, specs/006 sección
-- "Relación con arquitectura ya existente"): todo lo de este archivo va en
-- un schema propio, `crm_comunidades` — NUNCA en `public` (ahí vive
-- pulso-ignite) y sin FKs ni queries cruzadas hacia sus tablas.
--
-- Cómo aplicar: pegar en el SQL Editor de Supabase del proyecto compartido,
-- o como primera migración del CLI (`supabase migration new init_crm` y
-- pegar acá adentro). Todo el archivo es idempotente (create if not exists /
-- or replace) para poder re-correrlo sin romper nada si se interrumpe.
-- ============================================================================

create schema if not exists crm_comunidades;
set search_path = crm_comunidades, public;

create extension if not exists pgcrypto; -- gen_random_uuid()

-- ----------------------------------------------------------------------------
-- Función utilitaria compartida (updated_at automático)
-- ----------------------------------------------------------------------------
create or replace function crm_comunidades.set_updated_at()
returns trigger language plpgsql as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

-- ============================================================================
-- ENUMS
-- Los enums de progresión (etapa, estado_identificacion) se declaran en
-- orden ascendente a propósito: Postgres compara enums por orden de
-- declaración, así que `estado_identificacion >= 'enriquecido'` funciona
-- para filtros de rango sin tener que mapear a un entero aparte.
-- ============================================================================

do $$ begin
  create type crm_comunidades.etapa_comunidad as enum
    ('detectar','entender','disenar','activar','crecer');
exception when duplicate_object then null; end $$;

do $$ begin
  create type crm_comunidades.activo_tipo as enum
    ('conocimiento','voz','crecimiento','relacion','activaciones','decisiones');
exception when duplicate_object then null; end $$;

do $$ begin
  -- specs/006 sección "Estado de identificación (escalera de 6 pasos)"
  create type crm_comunidades.estado_identificacion as enum
    ('anonimo','pseudo_anonimo','semi_identificado','identificado','enriquecido','confirmado');
exception when duplicate_object then null; end $$;

do $$ begin
  -- specs/006 sección "Roles y alcance de acceso" — solo admin_taquion está
  -- implementado hoy; am_estratega y cliente quedan modelados para no
  -- reescribir el esquema cuando se construyan (backlog explícito).
  create type crm_comunidades.rol_crm as enum
    ('admin_taquion','am_estratega','cliente');
exception when duplicate_object then null; end $$;

do $$ begin
  create type crm_comunidades.nivel_exportacion as enum ('1','2','3');
exception when duplicate_object then null; end $$;

-- ============================================================================
-- TABLA: comunidad
-- specs/006 → "Modelo de datos" → Cliente/Comunidad
-- ============================================================================
create table if not exists crm_comunidades.comunidad (
  id                     uuid primary key default gen_random_uuid(),
  nombre_interno         text not null,                 -- nunca se expone públicamente fuera de Taquión
  cliente                text,                           -- ej. "GCBA", "San Luis" — organización dueña
  etapa                  crm_comunidades.etapa_comunidad not null default 'detectar',
  temporada_numero       int not null default 1,
  fecha_inicio_temporada date,
  activo                 boolean not null default true,  -- para archivar sin borrar
  created_at             timestamptz not null default now(),
  updated_at             timestamptz not null default now()
);

drop trigger if exists trg_comunidad_updated_at on crm_comunidades.comunidad;
create trigger trg_comunidad_updated_at
  before update on crm_comunidades.comunidad
  for each row execute function crm_comunidades.set_updated_at();

comment on table crm_comunidades.comunidad is
  'Una comunidad = un cliente de Taquión (specs/006). etapa gobierna qué activos están habilitados en comunidad_activo.';

-- ============================================================================
-- TABLA: comunidad_activo
-- Habilitación de los 6 activos por comunidad — normalizado (no un array de
-- booleanos) para poder trackear cuándo se habilitó cada uno y por qué.
-- specs/006 → "Estructura del panel de cliente (los 6 activos)"
-- ============================================================================
create table if not exists crm_comunidades.comunidad_activo (
  comunidad_id    uuid not null references crm_comunidades.comunidad(id) on delete cascade,
  activo          crm_comunidades.activo_tipo not null,
  habilitado      boolean not null default false,
  habilitado_en   timestamptz,
  deshabilitado_en timestamptz,
  nota            text,   -- ej. "se habilita ante campaña puntual" para Activaciones
  primary key (comunidad_id, activo)
);

comment on table crm_comunidades.comunidad_activo is
  'Relación/Activaciones/Decisiones arrancan en habilitado=false por defecto (Playbook de Producto) — nunca se borra la fila, se actualiza habilitado + timestamps.';

-- Seed: al crear una comunidad, crear sus 6 filas de activo en false por defecto.
create or replace function crm_comunidades.seed_activos_comunidad()
returns trigger language plpgsql as $$
begin
  insert into crm_comunidades.comunidad_activo (comunidad_id, activo, habilitado)
  select new.id, a, false
  from unnest(enum_range(null::crm_comunidades.activo_tipo)) as a
  on conflict (comunidad_id, activo) do nothing;
  return new;
end;
$$;

drop trigger if exists trg_seed_activos on crm_comunidades.comunidad;
create trigger trg_seed_activos
  after insert on crm_comunidades.comunidad
  for each row execute function crm_comunidades.seed_activos_comunidad();

-- ============================================================================
-- TABLA: arquetipo
-- Los arquetipos son reutilizables como metodología pero el ROSTER activo es
-- por comunidad (Cortado en Jarrito usa C1/C4/C5/C6; Todo un País, ninguno
-- todavía). incluido=false + motivo_exclusion deja la regla de exclusión de
-- arquetipos EXPLÍCITA en el dato, no aplicada en silencio (specs/001).
-- ============================================================================
create table if not exists crm_comunidades.arquetipo (
  id                 uuid primary key default gen_random_uuid(),
  comunidad_id       uuid not null references crm_comunidades.comunidad(id) on delete cascade,
  codigo             text not null,          -- ej. 'C4'
  nombre             text not null,          -- ej. 'Felipe, el porteño orgulloso'
  prioridad          int,                    -- 1 = máxima prioridad de foco
  corredor_principal text,
  incluido           boolean not null default true,
  motivo_exclusion   text,                   -- obligatorio en la práctica si incluido=false
  created_at         timestamptz not null default now(),
  unique (comunidad_id, codigo),
  check (incluido or motivo_exclusion is not null)
);

comment on table crm_comunidades.arquetipo is
  'Roster de arquetipos por comunidad (Playbook_Arquetipos_Inspire_Ignite.pdf). incluido=false exige motivo — nunca una exclusión silenciosa.';

-- ============================================================================
-- TABLA: contacto
-- Un solo registro por persona — el mismo contacto avanza por
-- estado_identificacion, nunca dos bases separadas (specs/006, hallazgo 6).
-- ============================================================================
create table if not exists crm_comunidades.contacto (
  id                          uuid primary key default gen_random_uuid(),
  comunidad_id                uuid not null references crm_comunidades.comunidad(id) on delete cascade,

  -- identidad — ver política de visibilidad en las vistas más abajo,
  -- nunca se expone telefono_plano/nombre_declarado/username directo a
  -- un rol que no sea admin_taquion o am_estratega.
  telefono_hash               text,           -- sha256, usado para CAPI y dedupe; obligatorio desde "semi_identificado"
  telefono_plano              text,           -- solo si se capturó; gobernado, nunca en export nivel 1
  nombre_declarado            text,
  username                    text,
  pixel_id                    text,           -- para vincular eventos previos a la identificación

  estado_identificacion       crm_comunidades.estado_identificacion not null default 'anonimo',

  corredor_localidad          text,
  interes_declarado           text,           -- comunidades sin sistema de arquetipos (ej. Todo un País)
  arquetipo_id                uuid references crm_comunidades.arquetipo(id),
  arquetipo_confianza         numeric(3,2) check (arquetipo_confianza between 0 and 1),
  arquetipo_estado            text check (arquetipo_estado in ('preliminar','confirmado')),

  nivel_activacion            smallint check (nivel_activacion between 1 and 5),
  nivel_activacion_actualizado_en timestamptz,
  semanas_consecutivas_activo smallint not null default 0,  -- para el criterio de Mapa de Voces (UMC 5.4: 3+ semanas)

  fuente_utm_source           text,
  fuente_utm_medium           text,
  fuente_utm_campaign         text,

  score_compuesto             jsonb,          -- multidimensional, se calcula recién con datos maduros (UMC 8.2) — null hasta entonces
  consentimiento_registrado   boolean not null default false, -- Ley 25.326 — debe ser true antes de que el resto de los campos se llenen

  fecha_alta                  timestamptz not null default now(),
  created_at                  timestamptz not null default now(),
  updated_at                  timestamptz not null default now(),

  -- un teléfono es único DENTRO de una comunidad; el mismo número en otra
  -- comunidad es una persona distinta a los fines de este CRM (comunidades
  -- aisladas — specs/006, regla de comunidades que no se nombran entre sí)
  constraint uq_contacto_telefono_por_comunidad unique (comunidad_id, telefono_hash)
);

drop trigger if exists trg_contacto_updated_at on crm_comunidades.contacto;
create trigger trg_contacto_updated_at
  before update on crm_comunidades.contacto
  for each row execute function crm_comunidades.set_updated_at();

create index if not exists idx_contacto_comunidad on crm_comunidades.contacto (comunidad_id);
create index if not exists idx_contacto_estado on crm_comunidades.contacto (comunidad_id, estado_identificacion);
create index if not exists idx_contacto_pixel on crm_comunidades.contacto (pixel_id) where pixel_id is not null;

comment on table crm_comunidades.contacto is
  'Entidad central. Mapa de Voces NO es una tabla — es la vista mapa_de_voces filtrada sobre esta misma tabla (specs/006, hallazgo 6).';
comment on column crm_comunidades.contacto.estado_identificacion is
  'Anónimo → Pseudo-anónimo → Semi-identificado → Identificado → Enriquecido → Confirmado. Un solo sentido salvo anonimización explícita (ver función anonimizar_contacto).';

-- ============================================================================
-- TABLA: contacto_afinidad_eje
-- Afinidad narrativa por eje temático — un contacto puede tener varios ejes
-- con distinto score (UMC 8.2), de ahí la tabla aparte en vez de una sola
-- columna.
-- ============================================================================
create table if not exists crm_comunidades.contacto_afinidad_eje (
  contacto_id  uuid not null references crm_comunidades.contacto(id) on delete cascade,
  eje          text not null,             -- ej. 'Seguridad', 'Espacios públicos'
  score        numeric(3,2) not null check (score between 0 and 1),
  actualizado_en timestamptz not null default now(),
  primary key (contacto_id, eje)
);

-- ============================================================================
-- TABLA: evento_journey
-- specs/006 → "Modelo de datos" → Evento de journey
-- ============================================================================
create table if not exists crm_comunidades.evento_journey (
  id            uuid primary key default gen_random_uuid(),
  contacto_id   uuid not null references crm_comunidades.contacto(id) on delete cascade,
  comunidad_id  uuid not null references crm_comunidades.comunidad(id) on delete cascade, -- denormalizado a propósito: acelera RLS/queries por comunidad sin joinear contacto
  tipo          text not null check (tipo in ('awareness','clic','lead','whatsapp','activacion','encuesta','encuentro')),
  fecha         timestamptz not null default now(),
  metadata      jsonb,        -- ej. {"ad_id": "...", "encuesta_id": "..."}
  created_at    timestamptz not null default now()
);

create index if not exists idx_evento_contacto on crm_comunidades.evento_journey (contacto_id, fecha);
create index if not exists idx_evento_comunidad on crm_comunidades.evento_journey (comunidad_id, fecha);

-- ============================================================================
-- TABLA: usuario_comunidad
-- Puente auth.users ↔ comunidad ↔ rol. Se crea desde ya (schema listo) pero
-- NO hay flujo de invitación/login construido todavía — hoy la única fila
-- esperable es el admin único usando la service role key, sin pasar por acá.
-- Cuando se construyan am_estratega/cliente (backlog), esta tabla es la base
-- de las políticas de RLS de esos roles.
-- comunidad_id NULL = acceso global (así se modela admin_taquion).
-- ============================================================================
create table if not exists crm_comunidades.usuario_comunidad (
  id            uuid primary key default gen_random_uuid(),
  usuario_id    uuid not null references auth.users(id) on delete cascade,
  comunidad_id  uuid references crm_comunidades.comunidad(id) on delete cascade,
  rol           crm_comunidades.rol_crm not null,
  creado_en     timestamptz not null default now(),
  unique (usuario_id, comunidad_id, rol)
);

comment on table crm_comunidades.usuario_comunidad is
  'Backlog funcional (specs/006): tabla lista para cuando se construyan los roles am_estratega/cliente. Hoy no se usa desde ninguna UI.';

-- ============================================================================
-- TABLA: exportacion_log (audit log — obligatorio para nivel 2, sin excepción)
-- specs/006 → "Exportación de datos (3 niveles de gobernanza)"
-- ============================================================================
create table if not exists crm_comunidades.exportacion_log (
  id            uuid primary key default gen_random_uuid(),
  comunidad_id  uuid references crm_comunidades.comunidad(id) on delete set null,
  nivel         crm_comunidades.nivel_exportacion not null,
  usuario_id    uuid references auth.users(id),      -- null admite el caso de hoy (sin auth de usuarios reales todavía)
  usuario_label text,                                 -- fallback legible mientras no haya auth.users poblada (ej. 'admin_taquion (MVP)')
  motivo        text,
  filtro_usado  jsonb,
  formato       text check (formato in ('csv','xlsx')),   -- null para nivel 3 (no es archivo)
  destino       text check (destino in ('meta_custom_audience','google_sheets','airtable')), -- solo nivel 3
  creado_en     timestamptz not null default now(),
  constraint chk_motivo_obligatorio_nivel2 check (nivel <> '2' or motivo is not null),
  constraint chk_formato_o_destino check (
    (nivel in ('1','2') and formato is not null and destino is null) or
    (nivel = '3' and destino is not null and formato is null)
  )
);

comment on table crm_comunidades.exportacion_log is
  'Toda exportación de nivel 2 (y el push de nivel 3) queda acá sin excepción, ni siquiera para admin_taquion (specs/006).';

-- ============================================================================
-- TABLA: importacion_log
-- No pedido explícitamente en specs/006 pero simétrico al audit log de
-- exportación y necesario para la convivencia con la planilla de
-- "Todo un País" durante la migración — trackea qué se importó y cuántos
-- duplicados se resolvieron.
-- ============================================================================
create table if not exists crm_comunidades.importacion_log (
  id               uuid primary key default gen_random_uuid(),
  comunidad_id     uuid not null references crm_comunidades.comunidad(id) on delete cascade,
  origen           text not null check (origen in ('planilla_todo_un_pais','export_manychat','otro')),
  archivo_nombre   text,
  filas_totales    int not null default 0,
  filas_nuevas     int not null default 0,
  filas_duplicadas int not null default 0,
  importado_por    text,
  creado_en        timestamptz not null default now()
);

-- ============================================================================
-- VISTA: mapa_de_voces
-- specs/006, hallazgo 6: "no es una tabla aparte" — filtro sobre contacto.
-- Criterio de UMC 5.4: estado Enriquecido/Confirmado + 3+ semanas
-- consecutivas de actividad + nivel de activación 4 o 5.
-- Visible solo para admin_taquion / am_estratega — NUNCA para cliente
-- (aplicar el permiso a nivel de GRANT, ver sección de permisos al final).
-- ============================================================================
create or replace view crm_comunidades.mapa_de_voces as
select
  c.id as contacto_id,
  c.comunidad_id,
  coalesce(c.nombre_declarado, c.username) as nombre,
  c.corredor_localidad,
  a.nombre as arquetipo,
  c.nivel_activacion,
  c.semanas_consecutivas_activo,
  (select af.eje from crm_comunidades.contacto_afinidad_eje af
     where af.contacto_id = c.id order by af.score desc limit 1) as afinidad_narrativa_principal,
  c.estado_identificacion
from crm_comunidades.contacto c
left join crm_comunidades.arquetipo a on a.id = c.arquetipo_id
where c.estado_identificacion in ('enriquecido','confirmado')
  and c.nivel_activacion >= 4
  and c.semanas_consecutivas_activo >= 3;

comment on view crm_comunidades.mapa_de_voces is
  'Vista, no tabla. Nunca otorgar select directo a un rol cliente sobre esta vista ni sobre crm_comunidades.contacto.';

-- security_invoker: al consultarla, la vista respeta el RLS de la tabla
-- base (crm_comunidades.contacto) según el usuario que ejecuta la query,
-- en vez de correr siempre con los permisos de quien la creó. Es lo que
-- permite combinar "columnas limitadas" (las que expone la vista) con
-- "filas limitadas" (RLS de contacto) sin duplicar la lógica de permisos.
alter view crm_comunidades.mapa_de_voces set (security_invoker = true);

-- ============================================================================
-- VISTA: export_nivel1_agregado
-- La base técnica del Nivel 1 de exportación: agregado por arquetipo,
-- corredor y nivel de activación — estructuralmente sin nombre/teléfono/
-- username, así que "exportar de más" por error humano no es posible desde
-- acá (specs/006 sección "Exportación de datos").
-- ============================================================================
create or replace view crm_comunidades.export_nivel1_agregado as
select
  c.comunidad_id,
  c.corredor_localidad,
  coalesce(a.nombre, c.interes_declarado, 'sin asignar') as arquetipo_o_interes,
  c.nivel_activacion,
  c.estado_identificacion,
  count(*) as cantidad_contactos
from crm_comunidades.contacto c
left join crm_comunidades.arquetipo a on a.id = c.arquetipo_id
group by 1,2,3,4,5;

alter view crm_comunidades.export_nivel1_agregado set (security_invoker = true);

-- ============================================================================
-- FUNCIÓN: anonimizar_contacto
-- La única forma soportada de "retroceder" un estado_identificacion —
-- siempre una acción explícita, nunca automática (specs/006).
-- ============================================================================
create or replace function crm_comunidades.anonimizar_contacto(p_contacto_id uuid, p_motivo text)
returns void language plpgsql as $$
begin
  update crm_comunidades.contacto
     set telefono_plano = null,
         nombre_declarado = null,
         username = null,
         estado_identificacion = 'pseudo_anonimo'
   where id = p_contacto_id;
  -- TODO (backlog): registrar este llamado en una tabla de auditoría de
  -- anonimización propia cuando haga falta trazabilidad de este evento
  -- puntual (hoy no está pedido en specs/006, se deja la función lista).
end;
$$;

-- ============================================================================
-- RLS — habilitado en todas las tablas. Política real hoy: solo
-- admin_taquion (vía service role key, que Supabase bypassa RLS
-- automáticamente — la política de abajo cubre el caso de un usuario
-- autenticado con rol admin_taquion en usuario_comunidad, para cuando deje
-- de operarse solo con la service role key).
-- Las políticas de am_estratega/cliente quedan como plantilla comentada:
-- activarlas es la tarea de cuando esos roles salgan de backlog.
-- ============================================================================
alter table crm_comunidades.comunidad enable row level security;
alter table crm_comunidades.comunidad_activo enable row level security;
alter table crm_comunidades.arquetipo enable row level security;
alter table crm_comunidades.contacto enable row level security;
alter table crm_comunidades.contacto_afinidad_eje enable row level security;
alter table crm_comunidades.evento_journey enable row level security;
alter table crm_comunidades.usuario_comunidad enable row level security;
alter table crm_comunidades.exportacion_log enable row level security;
alter table crm_comunidades.importacion_log enable row level security;

-- security definer + search_path fijo: es_admin() necesita leer
-- usuario_comunidad SIN pasar por su propio RLS — si no, queda un candado
-- circular (para saber si sos admin hay que leer la tabla, pero leer la
-- tabla exige ya haber probado que sos admin). security definer corre esta
-- función con los permisos de quien la creó (el owner del schema),
-- salteando el RLS del llamador solo para esta consulta puntual.
create or replace function crm_comunidades.es_admin(p_uid uuid)
returns boolean language sql stable security definer set search_path = crm_comunidades, pg_temp as $$
  select exists (
    select 1 from crm_comunidades.usuario_comunidad
    where usuario_id = p_uid and rol = 'admin_taquion' and comunidad_id is null
  );
$$;

do $$
declare
  t text;
begin
  foreach t in array array['comunidad','comunidad_activo','arquetipo','contacto',
                            'contacto_afinidad_eje','evento_journey','usuario_comunidad',
                            'exportacion_log','importacion_log']
  loop
    execute format(
      'drop policy if exists admin_full_access on crm_comunidades.%I; ' ||
      'create policy admin_full_access on crm_comunidades.%I for all ' ||
      'using (crm_comunidades.es_admin(auth.uid())) with check (crm_comunidades.es_admin(auth.uid()));',
      t, t
    );
  end loop;
end $$;

-- Plantilla para cuando am_estratega salga de backlog (NO ejecutar todavía):
--
-- create policy am_estratega_su_comunidad on crm_comunidades.contacto for select
--   using (exists (
--     select 1 from crm_comunidades.usuario_comunidad uc
--     where uc.usuario_id = auth.uid() and uc.rol = 'am_estratega'
--       and uc.comunidad_id = contacto.comunidad_id
--   ));
--
-- Plantilla para cuando cliente salga de backlog (NO ejecutar todavía).
-- RLS es a nivel de FILA y se define sobre la tabla base, no sobre la vista
-- — por eso la policy va en crm_comunidades.contacto. Lo que mantiene a
-- cliente lejos de los campos de identidad es la combinación de dos cosas:
-- (a) esta policy limita QUÉ FILAS puede tocar, (b) a cliente solo se le
-- hace GRANT SELECT sobre la vista export_nivel1_agregado (que ya tiene
-- security_invoker=true y no expone teléfono/nombre/username como columnas)
-- — nunca GRANT SELECT directo sobre crm_comunidades.contacto ni sobre
-- mapa_de_voces:
--
-- create policy cliente_su_comunidad on crm_comunidades.contacto for select
--   using (exists (
--     select 1 from crm_comunidades.usuario_comunidad uc
--     where uc.usuario_id = auth.uid() and uc.rol = 'cliente'
--       and uc.comunidad_id = contacto.comunidad_id
--   ));
-- revoke all on crm_comunidades.contacto from cliente_role;
-- grant select on crm_comunidades.export_nivel1_agregado to cliente_role;

-- ----------------------------------------------------------------------------
-- GRANTs de schema/tabla (Supabase NO los aplica automáticamente para un
-- schema propio como este — solo lo hace para `public`). Sin esto, PostgREST
-- devuelve "permission denied for schema crm_comunidades" incluso con RLS y
-- policies bien definidas: RLS filtra FILAS, pero antes de llegar ahí Postgres
-- exige USAGE sobre el schema y el privilegio de tabla correspondiente.
-- Detectado en producción 2026-09-17 tras el primer login real.
-- ----------------------------------------------------------------------------
grant usage on schema crm_comunidades to anon, authenticated, service_role;
grant select, insert, update, delete on all tables in schema crm_comunidades to authenticated;
grant select on all tables in schema crm_comunidades to anon;
grant select, insert, update, delete on all tables in schema crm_comunidades to service_role;
grant usage, select on all sequences in schema crm_comunidades to authenticated, service_role;
grant execute on all functions in schema crm_comunidades to anon, authenticated, service_role;
alter default privileges in schema crm_comunidades grant select, insert, update, delete on tables to authenticated, service_role;
alter default privileges in schema crm_comunidades grant select on tables to anon;
alter default privileges in schema crm_comunidades grant usage, select on sequences to authenticated, service_role;
alter default privileges in schema crm_comunidades grant execute on functions to anon, authenticated, service_role;
