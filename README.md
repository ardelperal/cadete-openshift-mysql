# Cadete OpenShift - Automatización MySQL Backup y Despliegue

Este repositorio contiene scripts PowerShell para automatizar el proceso de backup, despliegue y gestión de aplicaciones Cadete en entornos OpenShift corporativos.

## 📋 Requisitos Previos

- PowerShell 5.1 o superior
- Cliente `oc` (OpenShift CLI) instalado y configurado
- Cliente `podman` instalado (para despliegues de imágenes)
- Tokens de acceso a OpenShift para cada entorno
- Credenciales de acceso a Quay (registro de imágenes)
- Permisos de administración en los namespaces objetivo

### Verificar Requisitos

```powershell
# Verificar versión de PowerShell
$PSVersionTable.PSVersion

# Verificar cliente oc
oc version --client

# Verificar cliente podman
podman version

# Verificar conectividad (después de configurar tokens)
oc whoami
oc project
```

## 🏗️ Estructura del Proyecto

```
cadete_oc/
├── scripts/                   # Scripts principales
│   ├── cadete_deploy.ps1     # Script principal de despliegue de Cadete
│   ├── mysql_backup.ps1      # Script para extraer backups de MySQL
│   ├── mysql_seed_apply.ps1  # Script para aplicar semillas de datos
│   └── README.md             # Documentación de scripts
├── templates/                # Archivos de configuración
│   ├── .gitignore            # Exclusiones de control de versiones
│   ├── openshift_config.json # Configuración de tokens OpenShift (NO en repo)
│   ├── openshift_push_auth.json # Credenciales Quay (NO en repo)
│   ├── 00-users-and-grants.sql # Archivo de grants y usuarios
│   ├── db_list.txt           # Lista de bases de datos a respaldar
│   └── README.md             # Documentación de templates
├── backups/                  # Backups generados (excluido de git)
│   ├── *.sql.gz             # Archivos de backup comprimidos
│   └── README.md             # Documentación de backups
├── examples/                 # Archivos de ejemplo
│   ├── cadete-example-backup.sql.gz # Backup de ejemplo
│   └── README.md             # Documentación de ejemplos
├── docs/                     # Documentación adicional
│   └── CADETE_DEPLOYMENT.md  # Documentación detallada de despliegue
├── exports/                  # Exportaciones de recursos OpenShift
├── prepared/                 # Recursos preparados para aplicar
├── cadete-route.ps1          # Script para gestión de rutas
├── create_github_repo.ps1    # Script para crear repositorio GitHub
└── README.md                 # Este archivo
```

## ⚙️ Configuración Inicial

### 1. Configuración de Tokens OpenShift

Antes de usar los scripts, debes configurar los tokens de acceso para cada entorno:

1. **Obtener tokens de OpenShift**:
   ```bash
   # Conectarse manualmente a cada entorno y obtener el token
   oc login <servidor-openshift>
   oc whoami -t
   ```

2. **Crear archivo de configuración**:
   ```powershell
   # Copiar el template de configuración
   Copy-Item "templates/openshift_config.json" "openshift_config.json"
   ```

3. **Editar configuración con tokens reales**:
   ```json
   {
     "environments": {
       "wcdy-cert-frt": {
         "server": "https://api.ocgc4tools.mgmt.dc.es.telefonica:6443",
         "token": "sha256~TU_TOKEN_REAL_CERT",
         "namespace": "wcdy-cert-frt"
       },
       "wcdy-inte-frt": {
         "server": "https://api.ocgc4tools.mgmt.dc.es.telefonica:6443", 
         "token": "sha256~TU_TOKEN_REAL_INTE",
         "namespace": "wcdy-inte-frt"
       },
       "production": {
         "server": "https://api.ocgc4prod.mgmt.dc.es.telefonica:6443",
         "token": "sha256~TU_TOKEN_REAL_PROD", 
         "namespace": "wcdy-prod-frt"
       }
     },
     "default_environment": "wcdy-cert-frt"
   }
   ```

### 2. Configuración de Credenciales Quay

Para despliegues de imágenes, configura las credenciales de Quay:

1. **Crear archivo de autenticación**:
   ```powershell
   # Copiar el template
   Copy-Item "templates/openshift_push_auth.json" "openshift_push_auth.json"
   ```

2. **Editar con credenciales reales**:
   ```json
   {
     "auths": {
       "quay.apps.ocgc4tools.mgmt.dc.es.telefonica": {
         "username": "tu_usuario_quay",
         "password": "tu_password_quay"
       }
     }
   }
   ```

### 3. Verificar Configuración

```powershell
# Probar conexión automática
.\scripts\cadete_deploy.ps1 -Environment wcdy-cert-frt -TestConnection

# Verificar acceso a todos los entornos
oc login --token=<token-cert> --server=<servidor>
oc project wcdy-cert-frt
oc get pods

oc login --token=<token-inte> --server=<servidor>  
oc project wcdy-inte-frt
oc get pods
```

## 🎯 Entornos Disponibles

Los scripts soportan los siguientes entornos OpenShift corporativos:

| Entorno | Namespace | Servidor | Propósito |
|---------|-----------|----------|-----------||
| **wcdy-cert-frt** | wcdy-cert-frt | api.ocgc4tools.mgmt.dc.es.telefonica:6443 | Certificación/Preproducción 1 |
| **wcdy-inte-frt** | wcdy-inte-frt | api.ocgc4tools.mgmt.dc.es.telefonica:6443 | Integración/Preproducción 2 |
| **production** | wcdy-prod-frt | api.ocgc4prod.mgmt.dc.es.telefonica:6443 | Producción |

### Cambio Automático de Entorno

Los scripts ahora cambian automáticamente entre entornos usando la configuración de tokens:

```powershell
# Despliegue en certificación (por defecto)
.\scripts\cadete_deploy.ps1

# Despliegue en integración
.\scripts\cadete_deploy.ps1 -Environment wcdy-inte-frt

# Despliegue en producción
.\scripts\cadete_deploy.ps1 -Environment production
```

**Nota**: Ya no es necesario hacer `oc login` manual. Los scripts se conectan automáticamente usando los tokens configurados.

## 🚀 Script Principal: Despliegue de Cadete (`scripts/cadete_deploy.ps1`)

Este es el script principal para desplegar aplicaciones Cadete en OpenShift con autenticación automática.

### Características Principales

- ✅ **Autenticación automática** con tokens configurados
- ✅ **Cambio automático de entorno** y namespace
- ✅ **Construcción y push de imágenes** a Quay
- ✅ **Actualización de DeploymentConfig** con nueva imagen
- ✅ **Validación post-despliegue** automática
- ✅ **Gestión de rutas** y conectividad

### Uso Básico

```powershell
# Despliegue completo en certificación (entorno por defecto)
.\scripts\cadete_deploy.ps1

# Despliegue en entorno específico
.\scripts\cadete_deploy.ps1 -Environment wcdy-inte-frt

# Solo probar conexión
.\scripts\cadete_deploy.ps1 -Environment wcdy-cert-frt -TestConnection

# Despliegue con versión específica
.\scripts\cadete_deploy.ps1 -Environment production -ImageTag "1.0.12"
```

### Parámetros Disponibles

| Parámetro | Descripción | Ejemplo |
|-----------|-------------|---------|
| `-Environment` | Entorno objetivo | `wcdy-cert-frt`, `wcdy-inte-frt`, `production` |
| `-ImageTag` | Versión de imagen | `1.0.11`, `latest` |
| `-TestConnection` | Solo probar conectividad | Switch |
| `-SkipBuild` | Omitir construcción de imagen | Switch |
| `-SkipDeploy` | Omitir despliegue | Switch |

### Flujo de Ejecución

1. **Conexión OpenShift**: Autenticación automática con token
2. **Validación de entorno**: Verificación de namespace y recursos
3. **Construcción de imagen**: Build con Podman y tag apropiado
4. **Push a Quay**: Subida al registro corporativo
5. **Actualización DC**: Modificación del DeploymentConfig
6. **Validación**: Verificación de despliegue exitoso
7. **Información post-despliegue**: URLs y estado de recursos

### Ejemplo de Salida

```
[PASO 1] Conectando a OpenShift...
✓ Conectado exitosamente a wcdy-cert-frt
✓ Usuario actual: tf04681
✓ Proyecto actual: wcdy-cert-frt

[PASO 2] Validando entorno...
✓ Namespace wcdy-cert-frt accesible
✓ DeploymentConfig 'cadetefrt' encontrado

[PASO 3] Construyendo imagen...
✓ Imagen construida: cadete:1.0.11

[PASO 4] Subiendo imagen a Quay...
✓ Push exitoso a quay.apps.ocgc4tools.mgmt.dc.es.telefonica/wcdy/cadete:1.0.11

[PASO 5] Actualizando despliegue...
✓ DeploymentConfig actualizado con nueva imagen
✓ Rollout iniciado

[PASO 6] Validando despliegue...
✓ Despliegue completado exitosamente
✓ Pod cadete-xxx-yyy en estado Running

[PASO 7] Información post-despliegue...
✓ Aplicación disponible en: https://cadete3-wcdy-cert-frt.apps.ocgc4tools.mgmt.dc.es.telefonica
```

## 🔧 Script de Backup MySQL (`scripts/mysql_backup.ps1`)

### Propósito
Extrae backups completos de bases de datos MySQL desde pods en OpenShift, con autenticación automática.

### Características
- ✅ **Conexión automática** a OpenShift con tokens
- ✅ **Detección automática** del contenedor MySQL
- ✅ **Descubrimiento automático** de credenciales
- ✅ **Selección de bases de datos** (todas o específicas)
- ✅ **Compresión automática** con gzip
- ✅ **Validación** de conectividad

### Uso

```powershell
# Backup interactivo (selección de entorno y pod)
.\scripts\mysql_backup.ps1

# Backup con parámetros específicos
.\scripts\mysql_backup.ps1 -Environment wcdy-cert-frt -PodName cadete-db-xxx -DatabaseListFile templates/db_list.txt
```

### Parámetros Interactivos

El script te solicitará:

1. **Entorno**: Selección automática con tokens configurados
2. **Deployment MySQL**: Nombre del deployment (ej: `cadete-db`)
3. **Selección de BD**: 
   - `ALL` - Todas las bases de datos (excluyendo sistema)
   - Ruta a `templates/db_list.txt` - Bases específicas
4. **Password MySQL**: Solo si no se detecta automáticamente

### Ejemplo de Ejecución

```powershell
PS C:\Proyectos\cadete_oc\scripts> .\mysql_backup.ps1

=== MySQL Backup Tool ===
✓ Conectado automáticamente a wcdy-cert-frt
Deployment MySQL: cadete-db
Database selection (ALL o templates/db_list.txt): templates/db_list.txt

✓ Pod encontrado: cadete-db-7d67b44f75-mzsdl
✓ MYSQL_ROOT_PASSWORD detectada automáticamente
✓ Conectividad MySQL verificada
✓ Backup generado: ../backups/cadete-cert-20241207-143022.sql.gz (2.5 MB)
```

### Archivos Generados

Los backups se almacenan automáticamente en el directorio `backups/`:

```
backups/
├── wcdy-inte-frt-cadete-db-20241207.sql.gz   # Backup comprimido
└── wcdy-cert-frt-cadete-db-20241207.sql.gz   # Otro backup de ejemplo
```

## 🌱 Script de Aplicación MySQL (`scripts/mysql_seed_apply.ps1`)

### Propósito
Automatiza el proceso completo de importación de datos MySQL en OpenShift con autenticación automática.

### Características
- ✅ **Conexión automática** a OpenShift con tokens
- ✅ **Creación automática** de PVC temporal
- ✅ **Upload de archivos** de semilla
- ✅ **Configuración de initContainers**
- ✅ **Importación automática** de datos
- ✅ **Aplicación de grants** y usuarios
- ✅ **Validación completa**
- ✅ **Limpieza opcional**

### Uso

```powershell
# Aplicación interactiva
.\scripts\mysql_seed_apply.ps1

# Aplicación con archivo específico
.\scripts\mysql_seed_apply.ps1 -Environment wcdy-inte-frt -BackupFile backups/cadete-prod-20241201.sql.gz
```

### Parámetros Interactivos

El script te solicitará:

1. **Entorno**: Selección automática con tokens configurados
2. **MySQL Deployment**: Nombre del deployment MySQL
3. **Seed PVC Name**: Nombre del PVC temporal (default: `mysql-seed-pvc`)
4. **PVC Size**: Tamaño del PVC (default: `3Gi`)
5. **Storage Class**: Clase de almacenamiento (default: `apps-csi`)
6. **BusyBox Image**: Imagen para upload (default: `quay.apps.ocgc4tools.mgmt.dc.es.telefonica/wcdy/busybox:1.0`)
7. **Image Pull Secret**: Secret para registry privado (opcional)
8. **Backup File**: Ruta al archivo .sql.gz (ej: `backups/cadete-db-20241207.sql.gz` o `examples/cadete-example-backup.sql.gz`)
9. **Grants File**: Ruta al archivo de grants (default: `templates/00-users-and-grants.sql`)
10. **DB List File**: Ruta al archivo de lista de BD (default: `templates/db_list.txt`)

### Ejemplo de Ejecución Completa

```powershell
PS C:\Proyectos\cadete-openshift-mysql\scripts> .\mysql_seed_apply.ps1

=== Implementación MySQL Seed vía oc ===
Namespace destino: wcdy-prod-frt
Nombre del Deployment MySQL: cadete-db
Nombre del PVC de semilla [mysql-seed-pvc]: 
Tamaño del PVC [3Gi]: 
StorageClassName [apps-csi]: 
Imagen BusyBox [quay.apps.ocgc4tools.mgmt.dc.es.telefonica/wcdy/busybox:1.0]: 
ImagePullSecret (opcional): quay-wcdy-pullsecret
Ruta del backup .sql.gz: backups/cadete-db-20241207.sql.gz
Ruta del fichero de grants [templates/00-users-and-grants.sql]: 
Ruta del fichero de lista de bases [templates/db_list.txt]: 

✓ PVC mysql-seed-pvc creado
✓ Pod uploader-seed creado y listo
✓ Archivos copiados al pod
✓ MySQL escalado a 0 réplicas
✓ Deployment patcheado con seed volume e initContainer
✓ Pod uploader-seed eliminado
✓ MySQL escalado a 1 réplica
✓ Rollout completado exitosamente
✓ Grants aplicados correctamente
✓ Validación de usuarios y BD exitosa

¿Realizar limpieza? (Y/N): Y
✓ InitContainer y seed volume removidos
✓ Deployment limpio y funcional
```

## 📁 Archivos de Configuración

### `templates/db_list.txt`
Lista de bases de datos específicas para backup:

```
00_adjuntos
00_ayuda
mydb
cadete_main
```

### `templates/00-users-and-grants.sql`
Archivo de usuarios y permisos MySQL:

```sql
-- Crear usuario si no existe
CREATE USER IF NOT EXISTS 'user'@'%' IDENTIFIED BY 'tu_password_aqui';

-- Otorgar privilegios globales
GRANT ALL PRIVILEGES ON *.* TO 'user'@'%' WITH GRANT OPTION;

-- Aplicar cambios
FLUSH PRIVILEGES;
```

## 🔍 Comandos de Verificación Manual

### Verificar Estado del Deployment

```bash
# Ver estado del deployment
oc get deploy cadete-db -n wcdy-inte-frt

# Ver pods en ejecución
oc get pods -n wcdy-inte-frt -l app=cadete-db

# Ver logs del pod MySQL
oc logs -f deployment/cadete-db -n wcdy-inte-frt
```

### Verificar Volúmenes y Montajes

```bash
# Ver volúmenes del deployment
oc get deploy cadete-db -n wcdy-inte-frt -o jsonpath='{.spec.template.spec.volumes[*].name}'

# Ver montajes del contenedor
oc get deploy cadete-db -n wcdy-inte-frt -o jsonpath='{.spec.template.spec.containers[0].volumeMounts[*].mountPath}'

# Ver initContainers (debe estar vacío después de limpieza)
oc get deploy cadete-db -n wcdy-inte-frt -o jsonpath='{.spec.template.spec.initContainers}'
```

### Verificar Base de Datos

```bash
# Conectar al pod MySQL
oc rsh deployment/cadete-db -n wcdy-inte-frt

# Dentro del pod - conectar a MySQL
mysql -uroot -p$MYSQL_ROOT_PASSWORD

# Comandos SQL útiles
SHOW DATABASES;
SHOW GRANTS FOR 'user'@'%';
SELECT User, Host FROM mysql.user;
```

### Port-Forward para Verificar Aplicación Web

```bash
# Listar servicios
oc get svc -n wcdy-inte-frt

# Port-forward al servicio web
oc port-forward -n wcdy-inte-frt svc/cadete3 8080:8080

# Abrir en navegador: http://localhost:8080/
```

## 🚨 Solución de Problemas

### Error: "Access denied for user 'root'"

```bash
# Verificar variables de entorno
oc get deploy cadete-db -n wcdy-inte-frt -o jsonpath='{.spec.template.spec.containers[0].env[*].name}'

# Obtener password desde secret si existe
oc get secret mysql-secret -n wcdy-inte-frt -o jsonpath='{.data.MYSQL_ROOT_PASSWORD}' | base64 -d
```

### Error: "PVC already exists"

```bash
# Eliminar PVC existente
oc delete pvc mysql-seed-pvc -n wcdy-inte-frt

# Verificar que no hay pods usando el PVC
oc get pods -n wcdy-inte-frt -o jsonpath='{.items[*].spec.volumes[*].persistentVolumeClaim.claimName}' | grep mysql-seed-pvc
```

### Error: "Pod stuck in Pending"

```bash
# Verificar eventos del pod
oc describe pod uploader-seed -n wcdy-inte-frt

# Verificar storage class disponible
oc get storageclass

# Verificar PVC status
oc get pvc mysql-seed-pvc -n wcdy-inte-frt
```

### Error: "Image pull failed"

```bash
# Verificar image pull secrets
oc get secrets -n wcdy-inte-frt | grep pull

# Verificar acceso al registry
oc get deploy cadete-db -n wcdy-inte-frt -o jsonpath='{.spec.template.spec.imagePullSecrets[*].name}'
```

## 📊 Flujo de Trabajo Recomendado

### Para Despliegue Completo de Cadete

1. **Configurar entorno** (solo primera vez):
   ```powershell
   # Copiar templates de configuración
   Copy-Item "templates/openshift_config.json" "openshift_config.json"
   Copy-Item "templates/openshift_push_auth.json" "openshift_push_auth.json"
   
   # Editar con tokens y credenciales reales
   notepad openshift_config.json
   notepad openshift_push_auth.json
   ```

2. **Despliegue automático**:
   ```powershell
   # Despliegue en certificación
   .\scripts\cadete_deploy.ps1
   
   # Despliegue en integración
   .\scripts\cadete_deploy.ps1 -Environment wcdy-inte-frt
   
   # Despliegue en producción
   .\scripts\cadete_deploy.ps1 -Environment production
   ```

3. **Verificar aplicación**:
   ```powershell
   # El script mostrará automáticamente la URL de la aplicación
   # Ejemplo: https://cadete3-wcdy-cert-frt.apps.ocgc4tools.mgmt.dc.es.telefonica
   ```

### Para Migración de Datos Entre Entornos

1. **Extraer backup de origen**:
   ```powershell
   # En entorno fuente (ej: INTE)
   .\scripts\mysql_backup.ps1
   # El script se conectará automáticamente y te guiará
   ```

2. **Aplicar en destino**:
   ```powershell
   # En entorno destino (ej: PROD)
   .\scripts\mysql_seed_apply.ps1
   # Usar el archivo .sql.gz generado en backups/
   ```

3. **Verificar aplicación web**:
   ```bash
   # La URL se mostrará automáticamente después del despliegue
   # O usar port-forward si es necesario
   oc port-forward -n wcdy-prod-frt svc/cadete3 8080:8080
   ```

### Para Restauración de Backup

1. **Preparar archivos**:
   - Backup: `backups/cadete-prod-YYYYMMDD.sql.gz`
   - Grants: `templates/00-users-and-grants.sql`
   - Lista BD: `templates/db_list.txt`

2. **Ejecutar restauración**:
   ```powershell
   .\scripts\mysql_seed_apply.ps1
   # El script se conectará automáticamente al entorno seleccionado
   ```

3. **Validar y limpiar**:
   - Verificar datos importados
   - Aceptar limpieza automática

### Para Pruebas con Datos de Ejemplo

1. **Usar backup de ejemplo**:
   ```powershell
   .\scripts\mysql_seed_apply.ps1
   # Especificar: examples/cadete-example-backup.sql.gz
   ```
   - Confirmar funcionamiento de la aplicación

## 🔐 Consideraciones de Seguridad

### Archivos Sensibles

Los siguientes archivos contienen información sensible y están excluidos del control de versiones:

- ✅ `openshift_config.json` - Tokens de acceso OpenShift
- ✅ `openshift_push_auth.json` - Credenciales de Quay
- ✅ `*_auth.json` - Cualquier archivo de autenticación
- ✅ `*.env` - Variables de entorno
- ✅ `backups/` - Archivos de backup (pueden contener datos sensibles)

### Mejores Prácticas de Tokens

- 🔄 **Rotación regular**: Renueva los tokens OpenShift periódicamente
- 🔒 **Permisos mínimos**: Usa tokens con los permisos mínimos necesarios
- 📝 **No logs**: Los tokens nunca se muestran en logs o salida de consola
- 🚫 **No commits**: Nunca commitees archivos con tokens reales
- 🔐 **Almacenamiento seguro**: Guarda los tokens en ubicaciones seguras

### Validación de Seguridad

```powershell
# Verificar que archivos sensibles no están en git
git status --ignored

# Verificar permisos del token actual
oc auth can-i --list

# Verificar usuario actual
oc whoami
```

### Gestión de Tokens

```bash
# Obtener token actual (después de login manual)
oc whoami -t

# Verificar expiración del token
oc whoami --show-token | base64 -d | jq .exp

# Login con token específico
oc login --token=sha256~tu_token --server=https://api.servidor:6443
```

## 📞 Soporte

Para problemas o mejoras, contactar al equipo Trae 2.0 o revisar los logs detallados que generan los scripts.

### Logs Importantes

```bash
# Logs del deployment MySQL
oc logs -f deployment/cadete-db -n <namespace>

# Eventos del namespace
oc get events -n <namespace> --sort-by='.lastTimestamp'

# Estado de recursos
oc get all -n <namespace>
```

---

**Nota**: Estos scripts están optimizados para los entornos corporativos OpenShift con autenticación automática mediante tokens y las configuraciones estándar del equipo Trae 2.0.

## 🚀 Inicio Rápido

### Configuración Inicial (Solo Primera Vez)

1. **Clonar y configurar**:
   ```powershell
   git clone <repositorio>
   cd cadete_oc
   
   # Copiar templates de configuración
   Copy-Item "templates/openshift_config.json" "openshift_config.json"
   Copy-Item "templates/openshift_push_auth.json" "openshift_push_auth.json"
   ```

2. **Obtener tokens OpenShift**:
   ```bash
   # Para cada entorno, hacer login manual y obtener token
   oc login https://api.ocgc4tools.mgmt.dc.es.telefonica:6443
   oc whoami -t  # Copiar este token
   ```

3. **Configurar archivos**:
   ```powershell
   # Editar openshift_config.json con tokens reales
   notepad openshift_config.json
   
   # Editar openshift_push_auth.json con credenciales Quay
   notepad openshift_push_auth.json
   ```

### Primer Despliegue

```powershell
# Probar conexión
.\scripts\cadete_deploy.ps1 -TestConnection

# Despliegue completo en certificación
.\scripts\cadete_deploy.ps1

# ¡Listo! La aplicación estará disponible en la URL mostrada
```

### Comandos Más Usados

```powershell
# Despliegue rápido en certificación
.\scripts\cadete_deploy.ps1

# Despliegue en integración
.\scripts\cadete_deploy.ps1 -Environment wcdy-inte-frt

# Backup de base de datos
.\scripts\mysql_backup.ps1

# Aplicar datos de ejemplo
.\scripts\mysql_seed_apply.ps1
```