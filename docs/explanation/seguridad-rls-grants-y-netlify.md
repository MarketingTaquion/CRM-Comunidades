# Seguridad: RLS, GRANTs y visibilidad de Netlify

Este documento junta el porqué de varias decisiones de seguridad e infraestructura que no son evidentes leyendo el código una sola vez — la mayoría se descubrieron como incidentes reales en producción, no como diseño anticipado.

## RLS como único control de fila, hoy solo para `admin_taquion`

Las 9 tablas del schema tienen Row Level Security habilitado desde el día uno, aunque hoy solo exista un único rol con login real (`admin_taquion`). La policy `admin_full_access` se aplica a todas por igual, usando `es_admin(auth.uid())` en vez de repetir la misma subquery en cada policy. Las policies de `am_estratega`/`cliente` ya están escritas como plantilla comentada en el SQL — la decisión fue diseñar el modelo de permisos completo desde ahora (aunque esos roles estén en backlog) para no tener que rediseñar RLS cuando se construyan, solo activar policies ya pensadas.

## Por qué `es_admin()` es `security definer`

Para saber si un usuario es admin hay que leer `usuario_comunidad`. Pero si esa lectura pasara por el RLS normal de `usuario_comunidad` (que a su vez depende de si sos admin), queda un candado circular: para probar que sos admin necesitás leer la tabla, y leer la tabla exige ya haber probado que sos admin. `security definer` (con `search_path` fijado explícitamente, para evitar que alguien manipule el search_path y haga que la función resuelva a un objeto distinto) hace que esta función puntual corra con los permisos de quien la creó, salteando el RLS del llamador solo para esta consulta — el resto de las queries del usuario normal siguen respetando RLS sin excepción.

## Por qué las vistas usan `security_invoker = true`

Es el mecanismo inverso al anterior: sin `security_invoker`, una vista corre con los permisos de quien la creó (típicamente el owner del schema), lo que efectivamente saltearía el RLS de la tabla base para cualquiera que consulte la vista. Con `security_invoker = true`, `mapa_de_voces` y `export_nivel1_agregado` respetan el RLS de `contacto` según quien las consulta — así se puede combinar "columnas limitadas" (lo que la vista expone) con "filas limitadas" (RLS de la tabla base) sin duplicar lógica de permisos en dos lugares.

## El GRANT que RLS no reemplaza

**Incidente real (2026-09-17):** con RLS y policies ya aplicados y verificados, el primer login real de un usuario devolvió `permission denied for schema crm_comunidades` en vez de datos. La causa: Supabase auto-configura permisos de `anon`/`authenticated`/`service_role` únicamente para el schema `public` — un schema propio como `crm_comunidades` no hereda nada de eso. Postgres exige `USAGE` sobre el schema *antes* de siquiera llegar a evaluar RLS; sin ese grant, da igual cuán bien estén escritas las policies.

No se había detectado antes porque todo el testing previo del schema se hizo desde el SQL Editor de Supabase, que corre como superusuario y no pasa por ningún grant — el primer momento en que esto se vuelve visible es, necesariamente, el primer acceso real vía la API REST (PostgREST) con un usuario autenticado de verdad. El fix (bloque `GRANT` al final de `001_init_crm_comunidades.sql`) replica manualmente lo que Supabase da gratis en `public`: `USAGE` sobre el schema, privilegios de tabla/secuencia/función para `anon`/`authenticated`/`service_role`, y `ALTER DEFAULT PRIVILEGES` para que las tablas que se creen después también los reciban automáticamente.

## Por qué `[hidden]` necesitó `!important` en el CSS

Otro incidente real: la pantalla de "Establecé tu contraseña" (agregada para el flujo de recuperación) nunca se mostraba, aunque la lógica de JS que la activaba era correcta. La causa era CSS, no JS: `.login-screen{display:flex}` y `.app{display:grid}` son reglas de la hoja de estilos del propio documento (autor), mientras que `display:none` para el atributo `[hidden]` viene de la hoja de estilos por default del navegador (user-agent). En la cascada de CSS, una regla de autor le gana a una regla de user-agent con la misma especificidad, sin importar el orden en que aparezcan — así que togglear `.hidden = true` en JS no tenía ningún efecto visual: las tres pantallas (login, recuperación, panel) quedaban siempre renderizadas, apiladas una debajo de la otra. La regla `[hidden]{ display:none !important; }` (agregada al final de la hoja de estilos) resuelve esto forzando que `hidden` gane siempre, independientemente de qué otra regla de `display` exista para ese elemento.

## Por qué Netlify "Project visibility" tiene que ser `Public`

Netlify, para esta organización, crea proyectos nuevos con visibilidad `Private` por default — cualquier visitante tiene que autenticarse con una cuenta de Netlify del team antes de llegar al contenido real del sitio. Esto es invisible en el uso normal (quien ya tiene sesión de Netlify abierta no lo nota), pero rompe cualquier flujo que dependa de que un tercero externo (en este caso, el link de recuperación de contraseña que manda Supabase por email) llegue directo a una URL del sitio con un hash de autenticación en la URL — ese hash se puede perder en el camino del gate de Netlify. La gobernanza real de quién puede ver datos sigue siendo Supabase Auth + RLS, no la capa de Netlify — por eso tiene sentido que el hosting sea público y la seguridad de datos viva enteramente en el backend, en vez de duplicar control de acceso en dos capas independientes que además interfieren entre sí.

## Por qué el límite de 2 emails/hora no se "arregla" subiendo un número

El servicio de mail integrado de Supabase (el que se usa mientras no haya SMTP propio configurado) tiene un límite fijo de 2 emails por hora por proyecto. Aparece como un campo editable en Authentication → Rate Limits, pero el valor no se puede subir desde ahí mientras se use el mailer por default — es un límite del servicio compartido, no una configuración del proyecto. La única forma real de levantarlo es configurar un proveedor SMTP propio (Authentication → Emails → SMTP Settings). Mientras el volumen de invitaciones/recuperaciones sea bajo (hoy, un solo usuario real), esperar la ventana de una hora es más simple que sumar una dependencia externa — pero es la primera pieza a resolver si el número de usuarios reales crece.
