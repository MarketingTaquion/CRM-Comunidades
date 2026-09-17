# Cómo agregar una comunidad nueva

## 1. Insertar la fila en `comunidad`

Desde el SQL Editor de Supabase (schema `crm_comunidades`):

```sql
insert into crm_comunidades.comunidad (nombre_interno, cliente, etapa, temporada_numero)
values ('Nombre Interno', 'Nombre del cliente', 'detectar', 1)
returning id;
```

`etapa` acepta `'detectar' | 'entender' | 'disenar' | 'activar' | 'crecer'` (enum `etapa_comunidad`). Guardá el `id` que devuelve — lo vas a necesitar para los pasos siguientes.

No hace falta insertar nada más a mano en este paso: un trigger (`trg_seed_activos` → `seed_activos_comunidad()`) crea automáticamente las 6 filas en `comunidad_activo` (una por cada valor de `activo_tipo`), todas con `habilitado = false`.

## 2. Habilitar los activos que correspondan

Por default, los 6 activos (Conocimiento, Voz, Crecimiento, Relación, Activaciones, Decisiones) arrancan deshabilitados. Habilitá los que correspondan a la etapa actual de la comunidad:

```sql
update crm_comunidades.comunidad_activo
set habilitado = true, habilitado_en = now()
where comunidad_id = '<el-id-del-paso-1>'
  and activo in ('conocimiento', 'voz'); -- ajustar según la etapa
```

`index.html` refleja este estado en vivo: un activo con `habilitado = false` aparece bloqueado en el tablero (candado + explicación), sin necesidad de tocar el frontend.

## 3. (Opcional) Cargar arquetipos

Si la comunidad usa el sistema de arquetipos (no todas lo usan — ver [Modelo de identificación y gobernanza de exportación](../explanation/modelo-de-identificacion-y-gobernanza-de-exportacion.md)):

```sql
insert into crm_comunidades.arquetipo (comunidad_id, codigo, nombre, prioridad, corredor_principal, incluido)
values ('<el-id-del-paso-1>', 'C1', 'Nombre del arquetipo', 1, 'Nombre del corredor', true);
```

Si un arquetipo del roster general no aplica a esta comunidad, insertalo igual con `incluido = false` y `motivo_exclusion` completo — la tabla tiene un `check` que exige el motivo cuando `incluido = false`.

## 4. Confirmar en el panel

Logueate en el CRM ([Primer arranque en local](../tutorials/primer-arranque-local.md) o el sitio en vivo) — la comunidad nueva aparece automáticamente en el selector "Comunidad activa" de la izquierda, sin ningún cambio de código ni redeploy.
