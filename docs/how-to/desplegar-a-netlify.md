# Cómo desplegar a Netlify

Asume que ya existe el sitio de Netlify (`crm-comunidades-taquion`, team `Marketing-Taquion-IGNITE`) enganchado a este repo. Esto cubre cómo queda configurado y qué revisar si algo se rompe, no cómo crear un sitio nuevo desde cero.

## Configuración de build

En Netlify, el sitio ya tiene (definido en [`netlify.toml`](../../netlify.toml)):

```toml
[build]
  publish = "."
  command = "npm run build"
```

`npm run build` corre `scripts/generate-config.js`, que lee `SUPABASE_URL` y `SUPABASE_ANON_KEY` de las variables de entorno del sitio en Netlify y escribe `config.js` (no commiteado) antes de publicar. Sin esas dos variables cargadas en Netlify (Site settings → Environment variables), el deploy igual se completa, pero el sitio público muestra "Config no disponible" en el login.

## Deploy automático

Cada push a `master` dispara un deploy de producción automático — no hace falta ningún paso manual para que un cambio de código llegue a `https://crm-comunidades-taquion.netlify.app`. Podés seguir el build en Netlify → el sitio → **Deploys**.

## Variables de entorno requeridas

Ver [Variables de entorno y config](../reference/variables-de-entorno-y-config.md) para el detalle de cada una. Se cargan en Netlify → Site settings → Environment variables, con el mismo nombre exacto que usa `generate-config.js`.

## Visibilidad del proyecto (importante para el login)

El sitio tiene que estar en **Project visibility: Public** (Project configuration → General → Visitor access). Si queda en "Private" (el default de Netlify para proyectos nuevos en esta org), cualquier visitante —incluidos los links de recuperación de contraseña de Supabase— tiene que autenticarse primero con una cuenta de Netlify del team antes de llegar siquiera a `index.html`, lo cual rompe el flujo de login de la app. Ver el porqué en [Seguridad: RLS, GRANTs y visibilidad de Netlify](../explanation/seguridad-rls-grants-y-netlify.md).

## Auth de Supabase apuntando al dominio correcto

En Supabase → Authentication → URL Configuration, **Site URL** y **Redirect URLs** tienen que apuntar al dominio de Netlify (`https://crm-comunidades-taquion.netlify.app`, con `/**` en el redirect). Si quedan en el default (`http://localhost:3000`), los links de invitación/recuperación de contraseña redirigen a una URL que no existe en producción.

## Checklist para un deploy nuevo desde cero

1. Conectar el repo de GitHub al sitio de Netlify.
2. Build command `npm run build`, publish directory `.` (o confirmar que ya están en `netlify.toml`).
3. Cargar `SUPABASE_URL` y `SUPABASE_ANON_KEY` en Environment variables.
4. Poner Project visibility en `Public`.
5. En Supabase, actualizar Site URL / Redirect URLs al dominio de Netlify.
6. Confirmar en Supabase → Project Settings → Data API que el schema `crm_comunidades` y sus tablas/vistas están expuestos (ver [Esquema de base de datos](../reference/esquema-de-base-de-datos.md)) y que los GRANTs de schema están aplicados.
7. Disparar un deploy (push a `master`) y probar el login real.
