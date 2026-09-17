# Primer arranque en local

Esta guía te lleva de un clone limpio del repo a ver el panel del CRM funcionando en tu navegador, logueado con datos reales. Al final vas a haber corrido el build, generado tu propio `config.js` y entrado al panel como `admin_taquion`.

No hace falta instalar dependencias de Node: este proyecto no tiene ninguna (`package.json` no declara `dependencies`). El único paso de "build" es un script que genera un archivo de config a partir de variables de entorno.

## Requisitos previos

- Node.js instalado (para correr `npm run build` — el script usa solo `fs`/`path` del propio Node, sin librerías externas).
- Acceso al proyecto de Supabase `crm-comunidades` (org `Marketing-Taquion-IGNITE`): necesitás la **URL del proyecto** y la **clave `anon` (publishable)**. Pedíselas a quien administre el proyecto — están en Supabase, Project Settings → API Keys → "Legacy anon, service_role API keys" (usá la `anon`, nunca la `service_role`).
- Un usuario ya creado en Supabase Auth para ese proyecto, con una fila correspondiente en `crm_comunidades.usuario_comunidad` (rol `admin_taquion`). Si no tenés uno, ver [Dar de alta un usuario admin](../how-to/dar-de-alta-un-usuario-admin.md).

## 1. Cloná el repo

```bash
git clone https://github.com/MarketingTaquion/CRM-Comunidades.git
cd CRM-Comunidades
```

## 2. Generá `config.js`

`index.html` carga `config.js` antes de todo lo demás, y ese archivo **no está commiteado** (está en `.gitignore`) — lo genera `scripts/generate-config.js` leyendo variables de entorno:

```bash
# bash/zsh
export SUPABASE_URL="https://<tu-proyecto>.supabase.co"
export SUPABASE_ANON_KEY="<tu-clave-anon>"
npm run build
```

```powershell
# PowerShell
$env:SUPABASE_URL = "https://<tu-proyecto>.supabase.co"
$env:SUPABASE_ANON_KEY = "<tu-clave-anon>"
npm run build
```

Vas a ver `[generate-config] config.js generado (con credenciales).` en la consola. Si te falta alguna de las dos variables, el script igual genera el archivo pero avisa que faltan — y el sitio va a mostrar "Config no disponible" en la pantalla de login en vez de fallar en silencio.

## 3. Serví el proyecto con un servidor estático

`index.html` usa `<script type="module">` para importar el cliente de Supabase — los navegadores bloquean imports de módulos ES servidos como `file://`, así que no alcanza con abrir el archivo con doble clic. Usá cualquier servidor estático simple:

```bash
npx serve .
```

y abrí la URL que te indique (típicamente `http://localhost:3000`).

## 4. Logueate

Vas a ver la pantalla de login de "Comunidades". Entrá con el email y contraseña de tu usuario de Supabase Auth.

Si es la primera vez que ese usuario inicia sesión y todavía no tiene contraseña (fue invitado por email), no uses este formulario — seguí el link de invitación/recuperación que te llegó por mail, que te lleva a una pantalla separada de "Establecé tu contraseña" antes de poder loguearte acá.

## 5. Confirmá que ves datos reales

Una vez adentro deberías ver, en el selector de la izquierda, las comunidades cargadas en la base (`crm_comunidades.comunidad`), y al elegir una, el tablero de sus 6 activos según cuáles estén habilitados (`comunidad_activo.habilitado`). Si en cambio ves "No se pudo cargar la base" con `permission denied for schema crm_comunidades`, es un problema de permisos de base, no de tu setup local — ver [Diagnosticar problemas de acceso](../how-to/diagnosticar-problemas-de-acceso.md).

A partir de acá, cualquier cambio que hagas en `index.html` se ve recargando la página — no hay paso de build para el frontend en sí, solo para `config.js`.
