# Documentación — CRM de Comunidades

Esta documentación está organizada según [Diátaxis](https://diataxis.fr/): en vez de agrupar por tema, agrupa **por lo que necesitás en el momento en que lo buscás**. Antes de buscar algo puntual, ubicá primero qué tipo de necesidad tenés:

| Si necesitás... | Mirá en... |
|---|---|
| Levantar el proyecto por primera vez, de punta a punta | [`tutorials/`](tutorials/) |
| Resolver una tarea concreta que ya sabés que tenés que hacer (deployar, agregar una comunidad, dar de alta un admin) | [`how-to/`](how-to/) |
| El dato exacto — una columna, una variable de entorno, un archivo — sin explicación alrededor | [`reference/`](reference/) |
| Entender **por qué** algo está hecho así, qué alternativas se descartaron | [`explanation/`](explanation/) |

## Tutorials — aprender haciendo

- [Primer arranque en local](tutorials/primer-arranque-local.md)

## How-to — resolver una tarea puntual

- [Desplegar a Netlify](how-to/desplegar-a-netlify.md)
- [Agregar una comunidad nueva](how-to/agregar-una-comunidad.md)
- [Dar de alta un usuario admin](how-to/dar-de-alta-un-usuario-admin.md)
- [Exportar datos (Nivel 1)](how-to/exportar-datos-nivel-1.md)
- [Diagnosticar problemas de acceso (login, permisos, email)](how-to/diagnosticar-problemas-de-acceso.md)

## Reference — consultar un dato exacto

- [Esquema de base de datos](reference/esquema-de-base-de-datos.md)
- [Variables de entorno y config](reference/variables-de-entorno-y-config.md)
- [Estructura del repositorio](reference/estructura-del-repositorio.md)

## Explanation — entender el porqué

- [Arquitectura y aislamiento de datos](explanation/arquitectura-y-aislamiento-de-datos.md)
- [Modelo de identificación y gobernanza de exportación](explanation/modelo-de-identificacion-y-gobernanza-de-exportacion.md)
- [Seguridad: RLS, GRANTs y visibilidad de Netlify](explanation/seguridad-rls-grants-y-netlify.md)

---

La spec original de producto (contexto de negocio, research, decisiones de alcance) vive fuera de este repo, en el workspace local de planificación (`SDD-TAQUION/specs/006-crm-comunidades.md`) — no es un repo de GitHub. Esta documentación cubre el **código tal como existe hoy**, no el research que lo originó.
