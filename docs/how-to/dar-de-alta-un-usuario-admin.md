# Cómo dar de alta un usuario admin

El único rol con login real hoy es `admin_taquion` (`am_estratega` y `cliente` están modelados en la base pero sin flujo de login propio — ver [Modelo de identificación y gobernanza de exportación](../explanation/modelo-de-identificacion-y-gobernanza-de-exportacion.md)). Dar de alta un admin nuevo son dos pasos separados: crear el usuario en Supabase Auth, y vincularlo a `usuario_comunidad` con ese rol.

## 1. Crear (o invitar) el usuario en Supabase Auth

En Supabase → Authentication → Users:

- Si la persona todavía no tiene cuenta: **Add user → Send invitation** (por email, sin definir contraseña vos — la persona la define al abrir el link de invitación, que la va a llevar a la pantalla "Establecé tu contraseña" del propio `index.html`).
- Nunca uses la opción de crear usuario con contraseña manual escrita por vos: mandar solo la invitación por email mantiene la contraseña como algo que solo la persona conoce.

## 2. Vincularlo a `usuario_comunidad` como `admin_taquion`

```sql
insert into crm_comunidades.usuario_comunidad (usuario_id, comunidad_id, rol)
values ('<uid-del-usuario-en-auth.users>', null, 'admin_taquion');
```

`comunidad_id = null` es lo que modela "acceso global" en este esquema — la función `es_admin()` (usada por las policies de RLS) solo devuelve `true` cuando encuentra una fila así. Sin esta fila, el usuario puede loguearse (Supabase Auth lo autentica igual) pero todas las consultas a `crm_comunidades` le van a devolver 0 filas por RLS — no un error, silencio total.

Para encontrar el `usuario_id` (UID) de un usuario ya invitado: Supabase → Authentication → Users → click en su email → el UID aparece en el panel de detalle (también es el que loguea Supabase en "Raw JSON").

## Verificar que quedó bien

```sql
select uc.rol, uc.comunidad_id, u.email
from crm_comunidades.usuario_comunidad uc
join auth.users u on u.id = uc.usuario_id
where u.email = 'la-persona@ejemplo.com';
```

Debería devolver una fila con `rol = admin_taquion` y `comunidad_id = null`. Si el usuario ya logueó pero ve el panel vacío o sin datos, esta es la primera tabla a revisar.
