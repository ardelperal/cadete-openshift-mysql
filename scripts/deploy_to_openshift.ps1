# Script para desplegar nueva imagen de Cadete en OpenShift
# Uso: .\scripts\deploy_to_openshift.ps1 -Tag "1.0.16" -Environment "inte"

param(
    [Parameter(Mandatory=$true)]
    [string]$Tag,
    
    [Parameter(Mandatory=$false)]
    [ValidateSet("cert", "inte", "prod")]
    [string]$Environment = "inte"
)

# Mapeo de entornos a namespaces
$Namespaces = @{
    "cert" = "wcdy-cert-frt"
    "inte" = "wcdy-inte-frt" 
    "prod" = "wcdy-prod-frt"  # Ajustar según el namespace real de producción
}

$Namespace = $Namespaces[$Environment]
$QuayRepo = "quay.apps.ocgc4tools.mgmt.dc.es.telefonica/wcdy/cadete"
$DeploymentName = "cadetefrt"
$ContainerName = "container"
$ServiceName = "cadete3"

Write-Host "=== Despliegue de Cadete en OpenShift ===" -ForegroundColor Green
Write-Host "Entorno: $Environment ($Namespace)" -ForegroundColor Yellow
Write-Host "Tag: $Tag" -ForegroundColor Yellow
Write-Host "Imagen: ${QuayRepo}:${Tag}" -ForegroundColor Yellow

# Verificar conexión a OpenShift
Write-Host "`n1. Verificando conexión a OpenShift..." -ForegroundColor Cyan
$CurrentProject = oc project -q 2>$null
if ($LASTEXITCODE -ne 0) {
    Write-Error "No hay conexión a OpenShift. Ejecuta: oc login <cluster-url>"
    exit 1
}

# Cambiar al proyecto correcto
Write-Host "`n2. Cambiando al proyecto $Namespace..." -ForegroundColor Cyan
oc project $Namespace
if ($LASTEXITCODE -ne 0) {
    Write-Error "Error al cambiar al proyecto $Namespace"
    exit 1
}

# Verificar que existe el pull secret (crear si no existe)
Write-Host "`n3. Verificando pull secret..." -ForegroundColor Cyan
$SecretExists = oc get secret quay-pull -n $Namespace 2>$null
if ($LASTEXITCODE -ne 0) {
    Write-Host "   Creando pull secret..." -ForegroundColor Yellow
    oc create secret generic quay-pull `
        --type=kubernetes.io/dockerconfigjson `
        --from-file=.dockerconfigjson=c:\Proyectos\cadete_oc\openshift_push_auth.txt `
        -n $Namespace
    
    if ($LASTEXITCODE -eq 0) {
        Write-Host "   Vinculando secret al ServiceAccount default..." -ForegroundColor Yellow
        oc secrets link default quay-pull --for=pull -n $Namespace
    } else {
        Write-Error "Error creando pull secret"
        exit 1
    }
} else {
    Write-Host "   Pull secret 'quay-pull' ya existe" -ForegroundColor Green
}

# Actualizar imagen del deployment
Write-Host "`n4. Actualizando imagen del deployment..." -ForegroundColor Cyan
oc set image deployment/$DeploymentName $ContainerName=${QuayRepo}:${Tag} -n $Namespace

if ($LASTEXITCODE -ne 0) {
    Write-Error "Error actualizando la imagen del deployment"
    exit 1
}

# Esperar al rollout
Write-Host "`n5. Esperando rollout..." -ForegroundColor Cyan
oc rollout status deployment/$DeploymentName -n $Namespace --timeout=300s

if ($LASTEXITCODE -eq 0) {
    Write-Host "`n✅ Despliegue completado exitosamente" -ForegroundColor Green
    
    # Mostrar información del deployment
    Write-Host "`n📊 Estado del deployment:" -ForegroundColor Cyan
    oc get deployment $DeploymentName -n $Namespace
    
    # Mostrar pods
    Write-Host "`n📦 Pods:" -ForegroundColor Cyan
    oc get pods -l app=$DeploymentName -n $Namespace
    
    # Mostrar route si existe
    $RouteExists = oc get route -n $Namespace 2>$null
    if ($LASTEXITCODE -eq 0) {
        Write-Host "`n🌐 Routes:" -ForegroundColor Cyan
        oc get route -n $Namespace
    }
    
    Write-Host "`n🔍 Para verificar:" -ForegroundColor Yellow
    Write-Host "   Logs: oc logs deploy/$DeploymentName -n $Namespace --tail=50" -ForegroundColor White
    Write-Host "   Port-forward: oc port-forward svc/$ServiceName 8080:8080 -n $Namespace" -ForegroundColor White
    
} else {
    Write-Error "Error en el rollout. Verificar logs:"
    Write-Host "oc logs deploy/$DeploymentName -n $Namespace --tail=50" -ForegroundColor Red
    exit 1
}