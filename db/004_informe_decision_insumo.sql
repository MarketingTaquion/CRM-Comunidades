-- ============================================================================
-- CRM de Comunidades — Insumo cuantitativo para el Informe de Decisión
-- Ejecutiva (activo 6, Decisiones) + registro de temporadas.
-- Ref: specs/2026-09-18-informe-decision-insumo.md (aprobado 2026-09-18:
-- "foto acumulada al cierre + actividad" — el insumo trae AMBAS cosas,
-- nunca una sola).
--
-- Playbook de producto (specs/006): "Decisiones es la única vista que no se
-- completa con datos en vivo: se escribe manualmente al cierre de cada
-- temporada". Por eso este archivo crea DOS objetos separados a propósito:
--   1. informe_decision_insumo (vista, 100% automática, solo números)
--   2. informe_decision (tabla, 100% humana — nada en este esquema le
--      escribe nunca; si en el futuro alguien le agrega un default
--      automático a semaforo/aprendizajes, está rompiendo esta regla)
--
-- Aplicar después de 003_activaciones.sql. Idempotente.
-- ============================================================================
set search_path = crm_comunidades, public;

-- ----------------------------------------------------------------------------
-- TABLA: temporada
-- comunidad.temporada_numero/fecha_inicio_temporada solo guardan la
-- temporada ACTUAL — sin esta tabla no hay forma de reconstruir el cierre de
-- temporadas pasadas. Mismo criterio que comunidad_activo: nunca se borra,
-- se completa fecha_fin cuando cierra.
--
-- Nota operativa: esta tabla arranca VACÍA para las comunidades existentes
-- (Todo un País, Cortado en Jarrito) porque comunidad.fecha_inicio_temporada
-- es NULL para ambas hoy — no hay una fecha real que migrar, y esta migración
-- no inventa una. informe_decision_insumo devuelve 0 filas para una comunidad
-- hasta que alguien cargue su primera fila de temporada con una fecha real.
-- ----------------------------------------------------------------------------
create table if not exists crm_comunidades.temporada (
  comunidad_id  uuid not null references crm_comunidades.comunidad(id) on delete cascade,
  numero        int not null,
  fecha_inicio  date not null,
  fecha_fin     date,   -- null mientras la temporada sigue abierta
  primary key (comunidad_id, numero),
  constraint chk_temporada_fechas check (fecha_fin is null or fecha_fin >= fecha_inicio)
);

comment on table crm_comunidades.temporada is
  'Registro de fechas de cada temporada por comunidad. fecha_fin null = temporada abierta. Base de informe_decision_insumo.';

-- ----------------------------------------------------------------------------
-- VISTA: informe_decision_insumo
-- Trae AMBAS lecturas por temporada (decisión de producto 2026-09-18):
--   - "foto acumulada al cierre": estado de la comunidad tal como estaba en
--     fecha_fin (o a hoy, si la temporada sigue abierta) — usa el mismo
--     criterio que comunidad_metricas/mapa_de_voces (db/001, db/002) pero
--     acotado a esa fecha de corte.
--   - "actividad de la temporada": lo que pasó ESTRICTAMENTE entre
--     fecha_inicio y fecha_fin (altas, referidos, bajas nuevas) — no se
--     puede derivar de comunidad_metricas (que es histórico completo, sin
--     ventana de fechas), de ahí la fórmula propia acá.
-- engagement_rate NO tiene versión "de la temporada": nivel_activacion es un
-- valor puntual (contacto.nivel_activacion_actualizado_en), sin tabla de
-- historial — no hay from dónde reconstruir "engagement en marzo" después
-- de mayo. Queda como métrica de foto, no de período (limitación real,
-- documentada en vez de aproximada).
-- ----------------------------------------------------------------------------
create or replace view crm_comunidades.informe_decision_insumo as
select
  t.comunidad_id,
  t.numero as temporada_numero,
  t.fecha_inicio,
  t.fecha_fin,

  -- foto acumulada al cierre (o a hoy, si sigue abierta)
  count(c.*) filter (
    where c.fecha_alta <= coalesce(t.fecha_fin, now())
  ) as total_contactos,
  count(c.*) filter (
    where c.fecha_alta <= coalesce(t.fecha_fin, now()) and c.fecha_baja is null
  ) as contactos_activos,
  count(c.*) filter (
    where c.fecha_baja is not null and c.fecha_baja <= coalesce(t.fecha_fin, now())
  ) as contactos_dados_de_baja,
  round(
    count(c.*) filter (
      where c.nivel_activacion >= 3 and c.fecha_baja is null and c.fecha_alta <= coalesce(t.fecha_fin, now())
    )::numeric
    / nullif(count(c.*) filter (
      where c.fecha_baja is null and c.fecha_alta <= coalesce(t.fecha_fin, now())
    ), 0), 4
  ) as engagement_rate,
  round(
    count(c.*) filter (
      where c.referido_por_contacto_id is not null and c.fecha_alta <= coalesce(t.fecha_fin, now())
    )::numeric
    / nullif(count(c.*) filter (where c.fecha_alta <= coalesce(t.fecha_fin, now())), 0), 4
  ) as tasa_referidos,
  round(
    count(c.*) filter (
      where c.fecha_baja is not null and c.fecha_baja <= coalesce(t.fecha_fin, now())
    )::numeric
    / nullif(count(c.*) filter (where c.fecha_alta <= coalesce(t.fecha_fin, now())), 0), 4
  ) as tasa_abandono,
  count(distinct c.id) filter (
    where c.estado_identificacion in ('enriquecido','confirmado')
      and c.nivel_activacion >= 4 and c.semanas_consecutivas_activo >= 3
      and c.fecha_alta <= coalesce(t.fecha_fin, now())
  ) as cantidad_mapa_de_voces,

  -- actividad ocurrida EN la temporada (entre fecha_inicio y fecha_fin/hoy)
  count(c.*) filter (
    where c.fecha_alta >= t.fecha_inicio and c.fecha_alta <= coalesce(t.fecha_fin, now())
  ) as contactos_nuevos_temporada,
  count(c.*) filter (
    where c.referido_por_contacto_id is not null
      and c.fecha_alta >= t.fecha_inicio and c.fecha_alta <= coalesce(t.fecha_fin, now())
  ) as referidos_temporada,
  count(c.*) filter (
    where c.fecha_baja is not null
      and c.fecha_baja >= t.fecha_inicio and c.fecha_baja <= coalesce(t.fecha_fin, now())
  ) as bajas_temporada

from crm_comunidades.temporada t
join crm_comunidades.contacto c on c.comunidad_id = t.comunidad_id
group by 1,2,3,4;

alter view crm_comunidades.informe_decision_insumo set (security_invoker = true);

comment on view crm_comunidades.informe_decision_insumo is
  'Insumo 100% automático para el Informe de Decisión Ejecutiva: foto acumulada al cierre de temporada + actividad ocurrida en esa temporada. Nunca escribe el análisis cualitativo — eso vive en informe_decision. Devuelve 0 filas para una comunidad sin fila en temporada todavía.';

-- ----------------------------------------------------------------------------
-- TABLA: informe_decision
-- Lo que se ESCRIBE. Ningún job, función ni trigger de este esquema
-- inserta ni actualiza esta tabla — si en el futuro alguien le agrega un
-- default automático a semaforo/aprendizajes, está rompiendo la regla de
-- producto de que Decisiones es la única vista que no se llena con datos.
-- ----------------------------------------------------------------------------
create table if not exists crm_comunidades.informe_decision (
  comunidad_id     uuid not null references crm_comunidades.comunidad(id) on delete cascade,
  temporada_numero int not null,
  semaforo         text check (semaforo in ('verde','amarillo','rojo')),
  aprendizajes     text,
  plan_accion      jsonb,   -- [{accion, prioridad, responsable, fecha_limite}, ...]
  escrito_por      text,
  creado_en        timestamptz not null default now(),
  actualizado_en   timestamptz not null default now(),
  primary key (comunidad_id, temporada_numero),
  foreign key (comunidad_id, temporada_numero) references crm_comunidades.temporada (comunidad_id, numero)
);

comment on table crm_comunidades.informe_decision is
  'Análisis cualitativo del cierre de temporada — semáforo, aprendizajes, plan de acción. Se carga a mano (Insights/liderazgo). NINGÚN objeto de este esquema escribe acá automáticamente.';

-- ----------------------------------------------------------------------------
-- set_updated_at() (ver 001) usa la columna updated_at — informe_decision
-- usa actualizado_en, así que necesita su propia función trigger.
-- ----------------------------------------------------------------------------
create or replace function crm_comunidades.set_actualizado_en()
returns trigger language plpgsql as $$
begin
  new.actualizado_en = now();
  return new;
end;
$$;

drop trigger if exists trg_informe_decision_updated_at on crm_comunidades.informe_decision;
create trigger trg_informe_decision_updated_at
  before update on crm_comunidades.informe_decision
  for each row execute function crm_comunidades.set_actualizado_en();

-- ----------------------------------------------------------------------------
-- RLS — mismo patrón que el resto del schema.
-- ----------------------------------------------------------------------------
alter table crm_comunidades.temporada enable row level security;
alter table crm_comunidades.informe_decision enable row level security;

drop policy if exists admin_full_access on crm_comunidades.temporada;
create policy admin_full_access on crm_comunidades.temporada for all
  using (crm_comunidades.es_admin(auth.uid())) with check (crm_comunidades.es_admin(auth.uid()));

drop policy if exists admin_full_access on crm_comunidades.informe_decision;
create policy admin_full_access on crm_comunidades.informe_decision for all
  using (crm_comunidades.es_admin(auth.uid())) with check (crm_comunidades.es_admin(auth.uid()));

-- Plantillas para cuando am_estratega/cliente salgan de backlog (NO ejecutar
-- todavía). informe_decision SÍ es contenido pensado para llegar al cliente
-- (es literalmente lo que el activo "Decisiones" le muestra, specs/006) —
-- a diferencia de mapa_de_voces, no hay razón de gobernanza para ocultárselo
-- más allá de acotarlo a su propia comunidad:
--
-- create policy am_estratega_su_comunidad on crm_comunidades.informe_decision for select
--   using (exists (
--     select 1 from crm_comunidades.usuario_comunidad uc
--     where uc.usuario_id = auth.uid() and uc.rol = 'am_estratega'
--       and uc.comunidad_id = informe_decision.comunidad_id
--   ));
--
-- create policy cliente_su_comunidad on crm_comunidades.informe_decision for select
--   using (exists (
--     select 1 from crm_comunidades.usuario_comunidad uc
--     where uc.usuario_id = auth.uid() and uc.rol = 'cliente'
--       and uc.comunidad_id = informe_decision.comunidad_id
--   ));

-- ----------------------------------------------------------------------------
-- GRANTs — declarados explícitos para que el archivo sea autocontenido
-- (mismo criterio que 002/003).
-- ----------------------------------------------------------------------------
grant select, insert, update, delete on crm_comunidades.temporada to authenticated, service_role;
grant select on crm_comunidades.temporada to anon;
grant select, insert, update, delete on crm_comunidades.informe_decision to authenticated, service_role;
grant select on crm_comunidades.informe_decision to anon;
grant select on crm_comunidades.informe_decision_insumo to anon, authenticated, service_role;
