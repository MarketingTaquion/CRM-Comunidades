# Cómo diagnosticar problemas de acceso

Guía rápida para los síntomas de login/permisos que ya se dieron en producción. Para el porqué de fondo de cada uno, ver [Seguridad: RLS, GRANTs y visibilidad de Netlify](../explanation/seguridad-rls-grants-y-netlify.md).

## "Email o contraseña incorrectos" después de usar un link de recuperación

**Causa más probable:** la persona nunca llegó a guardar una contraseña nueva. El link de recuperación de Supabase autentica una sesión temporal, pero `index.html` necesita mostrar explícitamente la pantalla "Establecé tu contraseña" (`#recoveryScreen`) y llamar a `supabase.auth.updateUser({ password })` — si ese paso no se completó, no hay ninguna contraseña guardada en la cuenta.

**Cómo confirmar:** pedile a la persona que repita el flujo desde cero (Supabase → Users → el usuario → **Send password recovery**) y que preste atención a si ve la pantalla "Establecé tu contraseña" (correcto) o si cae directo en el login normal (algo está roto antes de llegar ahí — seguir con el siguiente punto).

## El link de recuperación no muestra la pantalla de "Establecé tu contraseña"

Revisar en este orden:

1. **Netlify → Project visibility.** Si el sitio está en `Private`, cualquier visitante (incluido el link de recuperación) tiene que autenticarse con una cuenta de Netlify del team antes de llegar a `index.html` — el hash con el token de Supabase se puede perder en el camino. Tiene que estar en `Public` (Project configuration → General → Visitor access).
2. **Supabase → Authentication → URL Configuration.** Si `Site URL` sigue en el default (`http://localhost:3000`) o no coincide con el dominio real, el link redirige a una URL que no existe en producción.
3. **El link ya expiró o ya fue consumido.** Los links de recuperación de Supabase valen 60 minutos y son de un solo uso. Si pasó ese tiempo, hay que mandar uno nuevo (Supabase → Users → el usuario → **Send password recovery**).

## "Failed to send password recovery... email rate limit exceeded"

El servicio de mail integrado de Supabase (el que se usa mientras no haya un SMTP propio configurado) tiene un límite fijo de **2 emails por hora por proyecto**, visible pero no editable en Authentication → Rate Limits. No es un valor que se pueda subir desde ahí: la única forma real de levantar el límite es configurar un proveedor SMTP propio en Authentication → Emails → SMTP Settings (ej. Resend, con plan gratis de 3000 emails/mes). Mientras tanto, la única opción es esperar a que la ventana de una hora se libere sola.

## "No se pudo cargar la base" / `permission denied for schema crm_comunidades`

RLS y las policies pueden estar perfectas y este error igual aparece: Postgres exige `USAGE` sobre el schema **antes** de llegar a evaluar cualquier policy de fila, y Supabase **no** otorga ese permiso automáticamente para un schema propio (solo lo hace para `public`). Se soluciona corriendo el bloque de `GRANT` al final de [`db/001_init_crm_comunidades.sql`](../../db/001_init_crm_comunidades.sql) contra la base real (no alcanza con haberlo corrido en otro ambiente).

Para confirmar el diagnóstico antes de aplicar el fix, correr en el SQL Editor:

```sql
select has_schema_privilege('authenticated', 'crm_comunidades', 'USAGE');
```

Si devuelve `false`, ese es el problema.

## El panel carga pero se ve vacío (sin error)

Esto es RLS filtrando filas silenciosamente, no un error de conexión. Lo más probable es que el usuario logueado no tenga una fila en `crm_comunidades.usuario_comunidad` con `rol = 'admin_taquion'` — ver [Dar de alta un usuario admin](dar-de-alta-un-usuario-admin.md) para verificarlo y corregirlo.
