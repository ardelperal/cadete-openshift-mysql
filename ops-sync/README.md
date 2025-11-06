# Ops Sync Scripts

Este directorio contiene herramientas para sincronizar datos y ficheros entre entornos y para exportar la base de datos desde Docker en producción.

## export-from-docker-mysql.ps1

Script para ejecutar en el host Docker (producción) que exporta la base de datos `user` del contenedor MySQL (por defecto, sin menú) y añade las sentencias necesarias para recrear el usuario de aplicación y sus permisos.

- Entrada:
  - `-ContainerName` (opcional): nombre del contenedor MySQL. Si se omite, se detecta automáticamente.
  - `-DatabaseName` (opcional): si se indica, exporta esa base. Si no se indica, exporta automáticamente la base `user` sin mostrar ningún menú.
  - `-AppUser` (opcional): usuario de aplicación. Por defecto se toma de `MYSQL_USER` del contenedor; si no existe, se usa `user`.
  - `-AppPassword` (opcional): contraseña del usuario de aplicación. Por defecto se toma de `MYSQL_PASSWORD` del contenedor; si no existe, se solicitará por consola.
  - `-OutPath` (opcional): ruta del fichero SQL resultante. Por defecto `ops-sync/backups/docker-prod-export-<timestamp>.sql`.

- Comportamiento:
  - Pide la contraseña de `root` de MySQL del contenedor.
  - Excluye bases de sistema (`information_schema`, `performance_schema`, `mysql`, `sys`).
  - Por defecto exporta `user`; si no existe o es sistema, aborta con error. También permite exportar otra base pasando `-DatabaseName`.
  - Genera el volcado con `mysqldump` (opciones: `--single-transaction --quick --routines --triggers --events`).
  - Añade al final del dump: `CREATE USER IF NOT EXISTS 'user'@'%' IDENTIFIED BY '<pwd>'; GRANT ...; FLUSH PRIVILEGES;` usando `-AppUser`/`-AppPassword` o los valores detectados.

- Ejemplos:
  - Exportar la base `user` (sin menú):
    `powershell -ExecutionPolicy Bypass -File ops-sync/export-from-docker-mysql.ps1`
  - Exportar solo la base `user` indicando contenedor y credenciales:
    `powershell -ExecutionPolicy Bypass -File ops-sync/export-from-docker-mysql.ps1 -ContainerName mysql-prod -DatabaseName user -AppUser user -AppPassword <pwd>`
  - Exportar otra base específica:
    `powershell -ExecutionPolicy Bypass -File ops-sync/export-from-docker-mysql.ps1 -DatabaseName cadete_db`

El resultado (`.sql`) puede consumirse directamente con el script de sincronización.

## sync-to-openshift.ps1

Script para sincronizar archivos `ext` y datos MySQL hacia OpenShift (INTE/CERT), sin tocar imágenes.

- Parámetros clave:
  - `-Env` (`inte` | `cert`): entorno de destino.
  - `-ExtPath` (opcional): ruta local de `ext`. Por defecto `C:\Proyectos\cadete\ext`.
  - `-SqlPath` (opcional): ruta del dump SQL a importar.
  - `-SourceMySqlHost`, `-SourceMySqlPort`, `-SourceMySqlUser`, `-SourceMySqlPassword`, `-SourceMySqlDatabase` (opcionales): si no se proporciona `-SqlPath`, el script puede exportar automáticamente desde una base de datos origen.

- Comportamiento:
  - Verifica `oc` y el proyecto (`wcdy-<env>-frt`).
  - Asegura el `volumeMount` del `web-pvc` en el deployment `cadetefrt`.
  - Sincroniza `ext` hacia `/var/www/html/public/ext`.
  - Importa el SQL en el pod `cadete3` y asegura `CREATE USER`/`GRANT` de usuario de aplicación.

- Ejemplos:
  - Usando un `.sql` exportado desde Docker:
    `powershell -ExecutionPolicy Bypass -File ops-sync/sync-to-openshift.ps1 -Env inte -SqlPath ops-sync/backups/docker-prod-export-20250101.sql`
  - Exportando desde origen MySQL (sin `-SqlPath`):
    `powershell -ExecutionPolicy Bypass -File ops-sync/sync-to-openshift.ps1 -Env cert -SourceMySqlHost 10.0.0.5 -SourceMySqlPort 3306 -SourceMySqlUser root -SourceMySqlPassword <pwd> -SourceMySqlDatabase user`

## Notas
- Los scripts no gestionan imágenes Docker; solo sincronizan ficheros y datos.
- Requisitos:
  - En host Docker: `docker` y acceso al contenedor MySQL.
  - En OpenShift: `oc` autenticado y permisos en el proyecto.
  - Para exportar desde origen: `mysqldump` disponible en el origen.