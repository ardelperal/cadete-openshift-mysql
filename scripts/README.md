# Scripts de Automatización MySQL

Este directorio contiene los scripts principales para la automatización de backups y despliegues MySQL en OpenShift.

## Scripts Disponibles

### `mysql_backup.ps1`
**Propósito**: Automatiza la creación de backups MySQL desde pods en OpenShift

**Características**:
- Descubrimiento automático del contenedor MySQL
- Backup selectivo o completo de bases de datos
- Compresión automática con gzip
- Almacenamiento organizado en `../backups/`

**Uso**:
```powershell
.\mysql_backup.ps1
```

### `mysql_seed_apply.ps1`
**Propósito**: Automatiza el proceso completo de seeding/restauración MySQL

**Características**:
- Creación automática de PVC de semilla
- Upload de archivos de backup y configuración
- Aplicación de initContainer para restauración
- Validación de bases de datos y usuarios
- Limpieza opcional de recursos temporales

**Uso**:
```powershell
.\mysql_seed_apply.ps1
```

## Requisitos Previos

### Herramientas Necesarias
- **OpenShift CLI (`oc`)**: Versión 4.x o superior
- **PowerShell**: Versión 7.x o superior
- **Acceso a cluster**: Sesión activa con `oc login`

### Permisos Requeridos
- Lectura/escritura en el namespace objetivo
- Capacidad de crear PVCs y modificar deployments
- Acceso de ejecución en pods (para `oc exec`)

## Estructura de Dependencias

```
scripts/
├── mysql_backup.ps1      # Script de backup
├── mysql_seed_apply.ps1  # Script de seeding
└── README.md            # Esta documentación

../templates/            # Archivos de configuración
├── 00-users-and-grants.sql
├── db_list.txt
└── README.md

../backups/             # Backups generados
├── *.sql.gz
└── README.md

../examples/            # Archivos de ejemplo
├── cadete-example-backup.sql.gz
└── README.md
```

## Flujo de Trabajo Recomendado

1. **Crear Backup**:
   ```powershell
   cd scripts
   .\mysql_backup.ps1
   ```

2. **Aplicar Seeding**:
   ```powershell
   .\mysql_seed_apply.ps1
   # Usar el backup recién creado desde ../backups/
   ```

3. **Verificación**:
   - Los scripts incluyen validaciones automáticas
   - Consulta los logs para confirmar el éxito de las operaciones

## Solución de Problemas

### Errores Comunes

**Error**: "No se pudo obtener el nombre del contenedor"
- **Solución**: Verifica que el deployment existe y tiene contenedores

**Error**: "No existe: [archivo]"
- **Solución**: Verifica las rutas de los archivos de configuración

**Error**: "PVC ya existe"
- **Solución**: El script maneja automáticamente PVCs existentes

### Logs y Debugging

Los scripts proporcionan salida detallada con códigos de color:
- **Cyan**: Información general
- **Yellow**: Advertencias y datos importantes
- **Green**: Operaciones exitosas
- **Red**: Errores críticos

## Personalización

### Variables de Entorno
Puedes preconfigurar algunos valores:

```powershell
$env:DEFAULT_NAMESPACE = "mi-namespace"
$env:DEFAULT_STORAGE_CLASS = "mi-storage-class"
```

### Modificación de Scripts
Los scripts están diseñados para ser modificables. Las secciones principales están claramente comentadas para facilitar la personalización.