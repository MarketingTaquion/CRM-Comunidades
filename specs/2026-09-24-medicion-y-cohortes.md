# Spec — Medición, tracking y cohortes (Fase 7)

Estado: **propuesta, pendiente de revisión — nada de esto está implementado todavía**. Registra el reencuadre de prioridades salido de la reunión Jazleidis Lesmes / Juan Marroncle (2026-09-23, notas de Gemini) y las 4 decisiones tomadas con el usuario el 2026-09-24 para resolverlo.

## Por qué esta fase pasa a ser la prioridad

La reunión decidió explícitamente: *"priorizar el desarrollo del CRM enfocado en el tratamiento de leads y el flujo de métricas, en lugar de una plataforma tipo pipeline comercial"*, con un entregable concreto: cohortes de ingreso y retención semana a semana, por corredor, para poder mostrarle resultados consolidados al cliente final. El detalle de KPIs que pidió Jazleidis para el tablero de Pulso: inversión en pauta, costo por lead (CPL), conversaciones completadas (Meta), clics, volumen de usuarios semanal/mensual, tasa de abandono — todo con corte semanal.

Como consecuencia directa, la Fase 4 (Activaciones avanzadas, incluido el pipeline de tratos agregado el mismo 2026-09-23) queda diferida — ver `specs/2026-09-18-roadmap-crm-comunidades.md`.

## Decisiones tomadas (2026-09-24)

1. **La inversión en pauta/CPL/conversaciones se carga aparte** — no se integra con Pulso Ignite (que ya trackea spend por cliente/plataforma vía Windsor.ai) en esta fase. Son campos de carga manual en este CRM.
2. **El sistema de Jazleidis en Google Sheets convive con este CRM** — no hay plan de reemplazo inmediato. Este CRM construye su propia foto semanal en paralelo, sin importar del Sheet ni depender de él.
3. **Cohortes = fotos semanales guardadas**, no un cálculo al vuelo sobre el estado actual — para poder mirar cómo se veía la cohorte de una semana puntual aunque los datos de `contacto` hayan cambiado después.
4. **El pipeline de tratos y el disparo a WhatsApp (Fase 4) quedan como spec para recordar y revisar después** — no se tocan ni se retiran, solo se documenta la pausa (ya reflejado en el roadmap).

## Qué ya existe vs. qué falta (auditoría contra el esquema actual)

| Dato pedido | Ya existe | Falta |
|---|---|---|
| Retención/cohorte por corredor | `contacto.fecha_alta`/`fecha_baja` + `corredor_localidad` — calculable sin dato nuevo | Nada calculable — falta el mecanismo de "foto" (ver abajo) |
| Tasa de abandono, engagement, referidos | `comunidad_metricas` ya las calcula en vivo | Solo point-in-time, no serie semanal |
| Inversión en pauta, CPL, conversaciones (Meta), clics | Nada en el esquema | Sí, genuinamente nuevo — carga manual (decisión 1) |
| Identificador único para cruzar fuentes | `contacto.telefono_hash` ya cumple ese rol acá | — |

## Propuesta de modelo: tabla `metrica_semanal`

```sql
create table if not exists crm_comunidades.metrica_semanal (
  id                    uuid primary key default gen_random_uuid(),
  comunidad_id          uuid not null references crm_comunidades.comunidad(id) on delete cascade,
  corredor_localidad    text,   -- null = total de la comunidad; con valor = foto de ese corredor puntual
  semana_inicio         date not null,   -- lunes de la semana que representa esta foto

  -- auto-calculables al momento de sacar la foto (mismo criterio que comunidad_metricas)
  contactos_nuevos      int not null default 0,
  contactos_activos     int not null default 0,
  contactos_dados_de_baja int not null default 0,
  engagement_rate       numeric(6,4),
  tasa_abandono         numeric(6,4),
  tasa_referidos        numeric(6,4),

  -- carga manual, aparte (decisión 1) — nullable porque no todas las semanas van a tener el dato cargado a tiempo
  inversion_pauta       numeric(12,2),
  cpl                   numeric(12,2),
  conversaciones_meta   int,
  clics                 int,

  cargado_por           text,
  creado_en             timestamptz not null default now(),

  unique (comunidad_id, corredor_localidad, semana_inicio)
);
```

RLS y grants: mismo patrón `admin_full_access` que el resto del esquema (`es_admin(auth.uid())`), plantilla comentada para `am_estratega`/`cliente`.

**Por qué una sola tabla y no separar "lo automático" de "lo manual":** una foto semanal es un solo evento en el tiempo — partirla en dos tablas obligaría a un join por semana/corredor cada vez que se lea, sin ninguna ganancia real (los campos manuales son pocos y opcionales).

## Cómo se genera la foto (propuesta, a confirmar)

Para no construir automatización antes de necesitarla: un botón **"Guardar foto de esta semana"** en el panel (probablemente dentro de Overview o una sección nueva de Métricas), que:
1. Calcula los campos automáticos con la misma lógica que `comunidad_metricas`/`overview_por_barrio`, acotada a la semana en curso.
2. Deja un formulario chico para cargar inversión/CPL/conversaciones/clics de esa semana.
3. Inserta la fila en `metrica_semanal` (o la actualiza si ya existe una foto para esa semana — `on conflict` sobre el `unique` de arriba).

Automatizar esto (cron semanal, sin intervención manual) queda para más adelante — hay una superposición natural con la Fase 2 (Reportes automáticos programables) que conviene resolver cuando esa fase se retome, no ahora.

## Vista de cohortes (propuesta, a confirmar)

Una vista `cohorte_semanal` sobre `metrica_semanal`, calculando semanas transcurridas desde el `semana_inicio` más antiguo de cada comunidad/corredor, para poder graficar la curva de retención (contactos_activos / contactos_nuevos de la semana de origen) — el diseño exacto de esta vista se termina de definir cuando haya al menos unas semanas de fotos reales cargadas, para no diseñar en el vacío.

## Fuera de alcance de esta fase

- Integración con Pulso Ignite / Windsor.ai (decisión 2 — no ahora).
- Importar o sincronizar con el Google Sheet de Jazleidis (decisión 2 — conviven, no se integran).
- Automatización sin intervención manual de la foto semanal (cron) — queda para cuando se retome Fase 2.
- Cualquier cosa de Activaciones/tratos/WhatsApp — Fase 4, diferida.

## Próximo paso

Con este spec aprobado, el siguiente paso sería `db/008_metrica_semanal.sql` + la vista `cohorte_semanal` + el botón "Guardar foto de esta semana" en el panel — **nada de esto se escribe todavía**, a la espera de tu revisión.
