# Ejemplos de Uso

Este directorio contiene archivos de ejemplo para demostrar el uso de los scripts de automatización MySQL.

## Archivos Incluidos

### `cadete-example-backup.sql.gz`
- **Descripción**: Backup de ejemplo comprimido en formato gzip
- **Uso**: Puede utilizarse para probar el script `mysql_seed_apply.ps1` sin necesidad de un backup real
- **Contenido**: Estructura básica de base de datos con datos de prueba

## Cómo Usar los Ejemplos

1. **Para probar el seeding con datos de ejemplo**:
   ```powershell
   cd scripts
   .\mysql_seed_apply.ps1
   # Cuando se solicite la ruta del backup, usar: examples/cadete-example-backup.sql.gz
   ```

2. **Para crear tu propio backup de ejemplo**:
   ```powershell
   cd scripts
   .\mysql_backup.ps1
   # El backup se guardará automáticamente en el directorio backups/
   ```

## Notas Importantes

- Los archivos de ejemplo NO contienen datos sensibles de producción
- Siempre verifica el contenido antes de aplicar en entornos productivos
- Los ejemplos están diseñados para funcionar con la configuración por defecto