# Cómo exportar datos (Nivel 1)

De los 3 niveles de exportación que modela el producto, solo el **Nivel 1** tiene un endpoint funcionando hoy — ver el porqué de los 3 niveles en [Modelo de identificación y gobernanza de exportación](../explanation/modelo-de-identificacion-y-gobernanza-de-exportacion.md).

## Pasos

1. Logueate en el CRM y elegí la comunidad en el selector de la izquierda.
2. En el menú "Sistema", clickeá **Exportación de datos**.
3. En la tarjeta "Nivel 1 · Operativo/cliente", clickeá **Exportar CSV**.
4. Se descarga un `.csv` (`export-nivel1-<nombre-de-la-comunidad>.csv`) con los datos agregados de la vista `crm_comunidades.export_nivel1_agregado` para esa comunidad.

## Qué contiene el archivo

Una fila por combinación de `corredor_localidad` × `arquetipo_o_interes` × `nivel_activacion` × `estado_identificacion`, con `cantidad_contactos` como conteo agregado. Ver el detalle de columnas en [Esquema de base de datos](../reference/esquema-de-base-de-datos.md#vista-export_nivel1_agregado).

## Qué NO contiene (a propósito)

Nombre, teléfono, username, ni ningún identificador individual — la vista está armada para que estructuralmente sea imposible exportar de más desde este botón, incluso por error humano. Si necesitás datos nominales (Mapa de Voces incluido), eso es Nivel 2, que **todavía no tiene endpoint construido** (el botón en la UI aparece deshabilitado con un candado) y va a requerir siempre un motivo registrado en `crm_comunidades.exportacion_log` cuando se construya.

## Si el botón no descarga nada

Revisá la consola del navegador: `loadExportNivel1()` lanza la excepción tal cual la devuelve Supabase (por ejemplo `permission denied for schema crm_comunidades` si faltan los GRANTs — ver [Diagnosticar problemas de acceso](diagnosticar-problemas-de-acceso.md)).
