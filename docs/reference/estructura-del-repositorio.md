# Referencia: estructura del repositorio

```
index.html                       El panel completo — HTML/CSS/JS vanilla en un solo archivo,
                                  sin build propio ni framework. Incluye login, recuperación de
                                  contraseña, y las 5 vistas del tablero (Conocimiento, Voz,
                                  Crecimiento, Relación, Exportación).

package.json                     Un único script: "build" → node scripts/generate-config.js.
                                  Sin dependencias declaradas.

netlify.toml                     Config de build para Netlify (publish = ".", command = "npm run build").

scripts/
  generate-config.js             Genera config.js a partir de SUPABASE_URL / SUPABASE_ANON_KEY
                                  en tiempo de build. Ver reference/variables-de-entorno-y-config.md.

db/
  001_init_crm_comunidades.sql   Esquema completo de Postgres: schema crm_comunidades, enums,
                                  tablas, triggers, vistas, RLS, GRANTs. Fuente de verdad del
                                  modelo de datos — ver reference/esquema-de-base-de-datos.md.

mockups/
  panel-admin-6-versiones.html   Exploración visual previa (6 direcciones de diseño), superada
                                  por index.html. Se conserva como referencia histórica, no se
                                  mantiene activamente.

docs/                            Esta documentación (Diátaxis).

.gitignore                       Excluye config.js, node_modules/, .env*, .netlify/.

README.md                        Punto de entrada del repo: estado actual, link a esta
                                  documentación, historial de hitos de deploy/conexión.
```

## Archivos NO commiteados (generados o de credenciales)

| Archivo | Por qué no está en el repo |
|---|---|
| `config.js` | Contiene la URL y clave de Supabase — se regenera en cada build, nunca se edita a mano |
| `node_modules/` | No hay dependencias declaradas, pero queda excluido por si acaso |
| `.env*` | Convención estándar, aunque hoy las variables se pasan directo como env vars de shell/Netlify, no vía archivo `.env` |
| `.netlify/` | Metadata local del CLI de Netlify |

## Relación con otros repos de Taquión

Este repo es hermano de `pulso-ignite` ([`Dashboard-Consumos-Ignite`](https://github.com/MarketingTaquion/Dashboard-Consumos-Ignite)) e `ignite-brief` ([`Brief-Campana-Ignite`](https://github.com/MarketingTaquion/Brief-Campana-Ignite)) — mismo patrón de HTML estático + cliente de Supabase vía CDN + `generate-config.js` en build time. Ver el porqué de esa convención y del aislamiento de datos en [Arquitectura y aislamiento de datos](../explanation/arquitectura-y-aislamiento-de-datos.md).
