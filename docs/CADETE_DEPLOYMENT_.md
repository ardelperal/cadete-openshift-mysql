# Despliegue de Cadete - Guía Completa

## Descripción General

Este documento describe el proceso completo de despliegue de la aplicación Cadete en los entornos OpenShift corporativos. El ciclo típico incluye la carga de una imagen desde un archivo `.tar`, su subida al registry Quay, y la actualización del deployment en OpenShift.

## Arquitectura del Proceso

```
Desarrollador → cadeteVX.tar → Script Deploy → Quay Registry → OpenShift Pod
     ↓              ↓              ↓              ↓              ↓
  Cambios      Imagen local    Carga/Tag      Push imagen    Rollout
```

## Entornos Disponibles

| Entorno | Namespace | Descripción |
|---------|-----------|-------------|
| `cert` | `wcdy-cert-frt` | Certificación/Preproducción 1 |
| `inte` | `wcdy-inte-frt` | Integración/Preproducción 2 |
| `prod` | `wcdy-prod-frt` | Producción |

## Prerrequisitos

### Herramientas Requeridas

1. **OpenShift CLI (oc)**
   ```powershell
   # Verificar instalación
   oc version --client
   ```

2. **Podman**
   ```powershell
   # Verificar instalación
   podman --version
   ```

3. **Conexión a OpenShift**
   ```powershell
   # Login al cluster
   oc login https://api.ocgc4tools.mgmt.dc.es.telefonica:6443
   ```

### Permisos Necesarios

- Acceso de lectura/escritura al registry Quay: `quay.apps.ocgc4tools.mgmt.dc.es.telefonica/wcdy`
- Permisos de deployment en los namespaces objetivo
- Capacidad para ejecutar `oc rollout` y `oc set image`

### Configuración de Autenticación
El script requiere un archivo de autenticación para Quay ubicado en `templates/quay_auth.json`:

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

**Para obtener las credenciales:**
1. Accede a Quay: https://quay.apps.ocgc4tools.mgmt.dc.es.telefonica
2. Ve a Account Settings > Robot Accounts
3. Crea o usa un robot account existente con permisos de push
4. Descarga el archivo de configuración Docker
5. Renómbralo a `quay_auth.json` y colócalo en `templates/`

⚠️ **Nota de Seguridad**: Este archivo contiene credenciales sensibles y está excluido del control de versiones.

## Uso del Script

### Sintaxis Básica

```powershell
.\scripts\cadete_deploy.ps1 [parámetros]
```

### Parámetros Disponibles

| Parámetro | Tipo | Descripción | Ejemplo |
|-----------|------|-------------|---------|
| `-TarFilePath` | String | Ruta al archivo .tar de Cadete | `"C:\temp\cadeteV2.tar"` |
| `-Environment` | String | Entorno de despliegue (cert/inte/prod) | `"inte"` |
| `-DeploymentName` | String | Nombre del deployment (default: cadete) | `"cadete"` |
| `-QuayRegistry` | String | URL del registry Quay | `"quay.apps.ocgc4tools.mgmt.dc.es.telefonica"` |
| `-QuayProject` | String | Proyecto en Quay (default: wcdy) | `"wcdy"` |
| `-SkipImagePush` | Switch | Saltar carga y push de imagen | |
| `-DryRun` | Switch | Modo simulación (no ejecuta comandos) | |

### Ejemplos de Uso

#### Despliegue Interactivo (Recomendado)
```powershell
# El script preguntará por el archivo .tar y entorno
.\scripts\cadete_deploy.ps1
```

#### Despliegue Automatizado
```powershell
# Despliegue completo especificando parámetros
.\scripts\cadete_deploy.ps1 -TarFilePath ".\cadeteV2.tar" -Environment "inte"
```

#### Modo Simulación
```powershell
# Ver qué comandos se ejecutarían sin hacer cambios reales
.\scripts\cadete_deploy.ps1 -TarFilePath ".\cadeteV2.tar" -Environment "cert" -DryRun
```

#### Solo Actualizar Deployment
```powershell
# Si la imagen ya está en Quay, solo actualizar el deployment
.\scripts\cadete_deploy.ps1 -Environment "inte" -SkipImagePush
```

## Flujo de Trabajo Detallado

### Paso 1: Verificación de Prerrequisitos
- ✅ Verifica que `oc` CLI esté disponible
- ✅ Verifica que `podman` esté instalado
- ✅ Confirma conexión activa a OpenShift

### Paso 2: Carga de Imagen desde .tar
```powershell
podman load -i "cadeteV2.tar"
```
- Carga la imagen del archivo .tar al registro local de Podman
- Extrae automáticamente el nombre de la imagen cargada

### Paso 3: Etiquetado y Push a Quay
```powershell
# Etiquetado con timestamp
podman tag cadete:latest quay.apps.ocgc4tools.mgmt.dc.es.telefonica/wcdy/cadete:inte-20240115-143022

# Etiquetado como latest
podman tag cadete:latest quay.apps.ocgc4tools.mgmt.dc.es.telefonica/wcdy/cadete:inte-latest

# Push al registry
podman push quay.apps.ocgc4tools.mgmt.dc.es.telefonica/wcdy/cadete:inte-20240115-143022
podman push quay.apps.ocgc4tools.mgmt.dc.es.telefonica/wcdy/cadete:inte-latest
```

### Paso 4: Actualización del Deployment
```powershell
# Cambiar al namespace correcto
oc project wcdy-inte-frt

# Actualizar la imagen del deployment
oc set image deployment/cadete cadete="quay.apps.ocgc4tools.mgmt.dc.es.telefonica/wcdy/cadete:inte-20240115-143022" -n wcdy-inte-frt

# Verificar el rollout
oc rollout status deployment/cadete -n wcdy-inte-frt --timeout=300s
```

### Paso 5: Verificación Post-Despliegue
```powershell
# Verificar pods
oc get pods -n wcdy-inte-frt -l app=cadete

# Ver logs
oc logs -f deployment/cadete -n wcdy-inte-frt

# Describir deployment
oc describe deployment cadete -n wcdy-inte-frt
```

## Comandos oc Útiles

### Gestión de Deployments
```powershell
# Ver estado actual del deployment
oc get deployment cadete -n wcdy-inte-frt

# Ver historial de rollouts
oc rollout history deployment/cadete -n wcdy-inte-frt

# Rollback a versión anterior
oc rollout undo deployment/cadete -n wcdy-inte-frt

# Rollback a versión específica
oc rollout undo deployment/cadete --to-revision=2 -n wcdy-inte-frt

# Pausar rollout
oc rollout pause deployment/cadete -n wcdy-inte-frt

# Reanudar rollout
oc rollout resume deployment/cadete -n wcdy-inte-frt
```

### Escalado
```powershell
# Escalar deployment
oc scale deployment/cadete --replicas=3 -n wcdy-inte-frt

# Auto-escalado
oc autoscale deployment/cadete --min=1 --max=5 --cpu-percent=80 -n wcdy-inte-frt
```

### Debugging
```powershell
# Ver eventos del namespace
oc get events -n wcdy-inte-frt --sort-by='.lastTimestamp'

# Describir pod específico
oc describe pod <pod-name> -n wcdy-inte-frt

# Ejecutar comando en pod
oc exec -it deployment/cadete -n wcdy-inte-frt -- /bin/bash

# Port forwarding para debugging
oc port-forward deployment/cadete 8080:8080 -n wcdy-inte-frt
```

## Estrategias de Despliegue

### Rolling Update (Por Defecto)
- Actualización gradual de pods
- Sin downtime
- Configuración por defecto en OpenShift

### Blue-Green Deployment
```powershell
# Crear deployment green
oc create deployment cadete-green --image=quay.apps.ocgc4tools.mgmt.dc.es.telefonica/wcdy/cadete:inte-latest -n wcdy-inte-frt

# Cambiar service para apuntar a green
oc patch service cadete -p '{"spec":{"selector":{"app":"cadete-green"}}}' -n wcdy-inte-frt

# Eliminar deployment blue después de verificar
oc delete deployment cadete-blue -n wcdy-inte-frt
```

### Canary Deployment
```powershell
# Escalar deployment actual
oc scale deployment/cadete --replicas=4 -n wcdy-inte-frt

# Crear deployment canary con 1 replica
oc create deployment cadete-canary --image=quay.apps.ocgc4tools.mgmt.dc.es.telefonica/wcdy/cadete:inte-latest -n wcdy-inte-frt
oc scale deployment/cadete-canary --replicas=1 -n wcdy-inte-frt
```

## Troubleshooting

### Problemas Comunes

#### Error: "Image pull failed"
```powershell
# Verificar que la imagen existe en Quay
podman search quay.apps.ocgc4tools.mgmt.dc.es.telefonica/wcdy/cadete

# Verificar pull secret
oc get secret quay-wcdy-pullsecret -n wcdy-inte-frt -o yaml
```

#### Error: "Deployment not found"
```powershell
# Listar deployments disponibles
oc get deployments -n wcdy-inte-frt

# Crear deployment si no existe
oc create deployment cadete --image=quay.apps.ocgc4tools.mgmt.dc.es.telefonica/wcdy/cadete:inte-latest -n wcdy-inte-frt
```

#### Rollout Stuck
```powershell
# Verificar estado detallado
oc describe deployment cadete -n wcdy-inte-frt

# Forzar recreación de pods
oc rollout restart deployment/cadete -n wcdy-inte-frt

# Verificar recursos del namespace
oc describe quota -n wcdy-inte-frt
oc describe limitrange -n wcdy-inte-frt
```

### Logs de Debugging
```powershell
# Logs del deployment
oc logs deployment/cadete -n wcdy-inte-frt --previous

# Logs de todos los pods
oc logs -l app=cadete -n wcdy-inte-frt --tail=100

# Logs en tiempo real
oc logs -f deployment/cadete -n wcdy-inte-frt
```

## Mejores Prácticas

### Seguridad
- ✅ Nunca incluir credenciales en los scripts
- ✅ Usar pull secrets para acceso a registries privados
- ✅ Verificar imágenes antes del despliegue
- ✅ Mantener logs de auditoría de despliegues

### Operaciones
- ✅ Siempre hacer backup antes de despliegues en producción
- ✅ Probar en entornos de certificación antes de producción
- ✅ Mantener versionado de imágenes con timestamps
- ✅ Documentar cambios en cada despliegue

### Monitoreo
- ✅ Verificar health checks después del despliegue
- ✅ Monitorear métricas de la aplicación
- ✅ Configurar alertas para fallos de deployment
- ✅ Mantener dashboards de estado de la aplicación

## Integración con CI/CD

### GitLab CI Example
```yaml
deploy_cadete:
  stage: deploy
  script:
    - oc login $OPENSHIFT_SERVER --token=$OPENSHIFT_TOKEN
    - .\scripts\cadete_deploy.ps1 -TarFilePath "cadete-$CI_COMMIT_SHA.tar" -Environment "inte"
  only:
    - main
```

### Jenkins Pipeline Example
```groovy
pipeline {
    agent any
    stages {
        stage('Deploy Cadete') {
            steps {
                script {
                    powershell """
                        oc login ${OPENSHIFT_SERVER} --token=${OPENSHIFT_TOKEN}
                        .\\scripts\\cadete_deploy.ps1 -TarFilePath "cadete-${BUILD_NUMBER}.tar" -Environment "inte"
                    """
                }
            }
        }
    }
}
```

## Contacto y Soporte

Para problemas relacionados con el despliegue de Cadete:

1. **Revisar logs**: Usar los comandos de debugging proporcionados
2. **Verificar estado**: Comprobar el estado de pods y deployments
3. **Documentar el problema**: Incluir logs relevantes y pasos para reproducir
4. **Escalar al equipo**: Contactar al equipo de DevOps si el problema persiste

---

**Última actualización**: Enero 2024  
**Versión del documento**: 1.0  
**Mantenido por**: Equipo Trae 2.0