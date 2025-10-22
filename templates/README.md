# Templates - Archivos de Configuración

Este directorio contiene plantillas y archivos de configuración necesarios para el funcionamiento de los scripts de automatización.

## Archivos Incluidos

### `00-users-and-grants.sql`
Plantilla SQL que contiene:
- Definición de usuarios MySQL
- Configuración de permisos y grants
- Estructura base para la configuración de seguridad de la base de datos

### `db_list.txt`
Lista de bases de datos disponibles para backup y restauración:
- Una base de datos por línea
- Formato simple de texto plano
- Utilizado por `mysql_backup.ps1` para mostrar opciones disponibles

### `openshift_push_auth.json`
**Archivo de autenticación para Quay Registry**
- Contiene credenciales codificadas en base64 para acceso a Quay
- Utilizado automáticamente por `cadete_deploy.ps1`
- **CRÍTICO**: Este archivo contiene información sensible

Formato esperado:
```json
{
  "auths": {
    "quay.apps.ocgc4tools.mgmt.dc.es.telefonica": {
      "auth": "base64_encoded_credentials",
      "email": ""
    }
  }
}
```

## Personalización

### Para `00-users-and-grants.sql`:
1. Copia el archivo como plantilla
2. Modifica los nombres de usuario según tu entorno
3. Ajusta los permisos según los requisitos de seguridad
4. Actualiza los hosts permitidos

### Para `db_list.txt`:
1. Lista una base de datos por línea
2. No incluyas espacios adicionales
3. Usa nombres exactos de las bases de datos
4. Comenta líneas con `#` si es necesario

### `openshift_config.json`
**Archivo de configuración para conexión automática a OpenShift**
- Contiene tokens y servidores por entorno
- Utilizado automáticamente por `cadete_deploy.ps1`
- **CRÍTICO**: Este archivo contiene información sensible

Formato esperado:
```json
{
  "environments": {
    "wcdy-cert-frt": {
      "server": "https://api.ocgc4pgpre01.mgmt.test.dc.es.telefonica:6443",
      "token": "sha256~XqwRAHNoRSuCIPvpeNd1ZQb8mZ-S06SkpkNW1Rq4RmI",
      "namespace": "wcdy-cert-frt"
    },
    "wcdy-inte-frt": {
      "server": "https://api.ocgc4pgpre01.mgmt.test.dc.es.telefonica:6443",
      "token": "sha256~REPLACE_WITH_INTEGRATION_TOKEN",
      "namespace": "wcdy-inte-frt"
    },
    "production": {
      "server": "https://api.ocgc4prod01.mgmt.dc.es.telefonica:6443",
      "token": "sha256~REPLACE_WITH_PRODUCTION_TOKEN",
      "namespace": "wcdy-prod"
    }
  },
  "default_environment": "wcdy-cert-frt"
}
```

## Instrucciones de Uso

### Para MySQL Scripts
1. **Personaliza `00-users-and-grants.sql`**:
   - Modifica usuarios según tus necesidades
   - Ajusta permisos y grants
   - Mantén la estructura SQL válida

2. **Actualiza `db_list.txt`**:
   - Añade las bases de datos de tu entorno
   - Una por línea, sin espacios adicionales
   - Nombres exactos como aparecen en MySQL

### Para Cadete Deployment
1. **Configura `openshift_push_auth.json`**:
   - Obtén las credenciales de tu administrador de Quay
   - Asegúrate de que el formato JSON sea válido
   - Verifica que las credenciales tengan permisos de push

2. **Configura `openshift_config.json`**:
   - Obtén los tokens de OpenShift para cada entorno
   - Actualiza las URLs de los servidores según tu infraestructura
   - Verifica que los namespaces sean correctos

**Para obtener tokens de OpenShift:**
1. Accede a la consola web de OpenShift
2. Ve a tu perfil (esquina superior derecha)
3. Selecciona "Copy login command"
4. Copia el token que aparece en el comando `oc login`

### Para `quay_auth.json`:
1. **NUNCA** incluyas este archivo en el control de versiones
2. Asegúrate de que las credenciales sean válidas
3. Verifica que el robot account tenga permisos de push
4. Rota las credenciales regularmente por seguridad

## Seguridad y Consideraciones

⚠️ **IMPORTANTE - DATOS SENSIBLES**:
- `openshift_push_auth.json` contiene credenciales de acceso a Quay
- `openshift_config.json` contiene tokens de OpenShift
- Estos archivos están excluidos del control de versiones (`.gitignore`)
- **NUNCA** compartas estos archivos públicamente
- Mantén copias de seguridad seguras de las credenciales

### Buenas Prácticas
- Revisa periódicamente los permisos de los archivos
- Actualiza credenciales según políticas de seguridad corporativas
- Rota tokens de OpenShift regularmente (recomendado cada 90 días)
- Documenta cambios en configuraciones críticas
- Usa variables de entorno para datos sensibles cuando sea posible
- Verifica que los tokens tengan solo los permisos mínimos necesarios

## Estructura de Archivos

```
templates/
├── .gitignore                    # Exclusiones de control de versiones
├── README.md                     # Esta documentación
├── 00-users-and-grants.sql      # Plantilla SQL para usuarios MySQL
├── db_list.txt                   # Lista de bases de datos
├── openshift_push_auth.json      # Credenciales Quay (NO en repo)
└── openshift_config.json         # Configuración OpenShift (NO en repo)
```

**Archivos excluidos del repositorio:**
- `openshift_push_auth.json` - Credenciales de Quay
- `openshift_config.json` - Tokens de OpenShift
- Cualquier archivo `*_auth.json` o `*.env`