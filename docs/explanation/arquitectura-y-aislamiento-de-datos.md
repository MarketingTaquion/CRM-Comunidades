# Arquitectura y aislamiento de datos

## Por qué este repo existe aparte

El CRM de Comunidades es el producto resultante del servicio "Comunidades" de Taquión, pensado para reemplazar el patrón actual de planillas sueltas + ManyChat con un registro único de comunidades, contactos y su nivel de identificación. Es un repo propio (`MarketingTaquion/CRM-Comunidades`), no una carpeta dentro de otro proyecto — mismo patrón que sus hermanos `pulso-ignite` e `ignite-brief`: HTML estático sin framework, cliente de Supabase vía CDN (`esm.sh`), y un paso de build mínimo que solo inyecta config.

La spec de producto (research, decisiones de alcance, historial completo de decisiones) vive fuera de este repo, en el workspace local de planificación (`SDD-TAQUION/specs/006-crm-comunidades.md`) — deliberadamente no es un repo de GitHub. La separación es intencional: ese documento es donde se decide **qué** construir; este repo es donde se construye.

## Por qué comparte proyecto de Supabase con `pulso-ignite` pero en un schema aparte

Ambos productos viven en la misma organización de Supabase (`Marketing-Taquion-IGNITE`) porque son parte del mismo ecosistema de herramientas internas de Taquión y no hay necesidad operativa de separarlos en cuentas distintas. Pero son productos diferentes con datos que no deberían mezclarse ni cruzarse por accidente — de ahí que todo lo de este CRM vive en su propio schema de Postgres, `crm_comunidades`, nunca en `public` (donde vive `pulso-ignite`), sin foreign keys ni queries cruzadas hacia sus tablas.

La consecuencia práctica de esta decisión es la que terminó generando el incidente documentado en [Seguridad: RLS, GRANTs y visibilidad de Netlify](seguridad-rls-grants-y-netlify.md): un schema custom no hereda automáticamente ninguno de los permisos que Supabase preconfigura para `public`, así que hay pasos manuales (exponer el schema en Data API, otorgar GRANTs) que no existen en el camino feliz de "creá una tabla en `public` y andá" que ofrece la documentación oficial de Supabase por default.

## Por qué comunidades distintas nunca se referencian entre sí

`contacto.telefono_hash` es único por `comunidad_id`, no globalmente — el mismo número de teléfono en dos comunidades distintas se modela como dos personas distintas a los fines de este CRM. Esto refleja que cada comunidad es un contexto de relación separado (una persona puede participar en "Todo un País" y en "Cortado en Jarrito" con roles y estados de identificación completamente independientes), y evita el riesgo de que una fuga de datos o un bug de query en una comunidad exponga contactos de otra.

## Por qué no hay build para el frontend

`index.html` es un único archivo sin bundler, sin framework, sin transpilación — el único paso de "build" (`npm run build`) genera `config.js` a partir de variables de entorno, nada más. Esto sigue el mismo patrón que `ignite-brief`, priorizando que cualquiera pueda abrir el archivo, entender el flujo completo de principio a fin sin saltar entre módulos, y desplegar sin pipeline de CI complejo. El costo es que el archivo crece con cada feature (hoy ronda las 600 líneas) — una decisión consciente de simplicidad operativa sobre modularidad, válida mientras el producto siga en esta escala.
