# Script para build, tag y push de Cadete a Quay corporativo
# Uso: .\scripts\build_and_push.ps1 -Tag "1.0.16"

param(
    [Parameter(Mandatory=$true)]
    [string]$Tag,
    
    [Parameter(Mandatory=$false)]
    [string]$Engine = "docker"  # "docker" o "podman"
)

# Configuración de proxy corporativo
$env:HTTP_PROXY = "http://185.46.212.88:80"
$env:HTTPS_PROXY = "http://185.46.212.88:80"
$env:NO_PROXY = "localhost,127.0.0.1,.svc,.cluster.local,ocgc4pgpre01.serv.dev.dc.es.telefonica,quay.apps.ocgc4tools.mgmt.dc.es.telefonica"

# Variables
$LocalImageName = "cadete"
$QuayRepo = "quay.apps.ocgc4tools.mgmt.dc.es.telefonica/wcdy/cadete"
$AuthFile = "c:\Proyectos\cadete_oc\openshift_push_auth.txt"

Write-Host "=== Build, Tag y Push de Cadete a Quay ===" -ForegroundColor Green
Write-Host "Tag: $Tag" -ForegroundColor Yellow
Write-Host "Engine: $Engine" -ForegroundColor Yellow
Write-Host "Proxy: $env:HTTP_PROXY" -ForegroundColor Yellow

# Verificar que estamos en el directorio correcto
if (-not (Test-Path "Dockerfile")) {
    Write-Error "No se encuentra Dockerfile. Ejecuta desde c:\Proyectos\cadete_oc\"
    exit 1
}

# Verificar archivo de autenticación
if (-not (Test-Path $AuthFile)) {
    Write-Error "No se encuentra el archivo de autenticación: $AuthFile"
    exit 1
}

Write-Host "`n1. Construyendo imagen..." -ForegroundColor Cyan

if ($Engine -eq "docker") {
    # Build con Docker
    docker build `
        --build-arg HTTP_PROXY=$env:HTTP_PROXY `
        --build-arg HTTPS_PROXY=$env:HTTPS_PROXY `
        --build-arg NO_PROXY=$env:NO_PROXY `
        -t "${LocalImageName}:${Tag}" .
    
    if ($LASTEXITCODE -ne 0) {
        Write-Error "Error en docker build"
        exit 1
    }
    
    Write-Host "`n2. Etiquetando para Quay..." -ForegroundColor Cyan
    docker tag "${LocalImageName}:${Tag}" "${QuayRepo}:${Tag}"
    
    Write-Host "`n3. Configurando autenticación Docker..." -ForegroundColor Cyan
    $DockerConfigDir = "$env:USERPROFILE\.docker"
    if (-not (Test-Path $DockerConfigDir)) {
        New-Item -ItemType Directory -Force -Path $DockerConfigDir | Out-Null
    }
    Copy-Item $AuthFile "$DockerConfigDir\config.json" -Force
    
    Write-Host "`n4. Subiendo a Quay..." -ForegroundColor Cyan
    docker push "${QuayRepo}:${Tag}"
    
} elseif ($Engine -eq "podman") {
    # Build con Podman
    podman build `
        --build-arg HTTP_PROXY=$env:HTTP_PROXY `
        --build-arg HTTPS_PROXY=$env:HTTPS_PROXY `
        --build-arg NO_PROXY=$env:NO_PROXY `
        -t "${LocalImageName}:${Tag}" .
    
    if ($LASTEXITCODE -ne 0) {
        Write-Error "Error en podman build"
        exit 1
    }
    
    Write-Host "`n2. Etiquetando para Quay..." -ForegroundColor Cyan
    podman tag "${LocalImageName}:${Tag}" "${QuayRepo}:${Tag}"
    
    Write-Host "`n3. Subiendo a Quay con authfile..." -ForegroundColor Cyan
    podman push --authfile $AuthFile "${QuayRepo}:${Tag}"
    
} else {
    Write-Error "Engine debe ser 'docker' o 'podman'"
    exit 1
}

if ($LASTEXITCODE -eq 0) {
    Write-Host "`n✅ Imagen subida exitosamente:" -ForegroundColor Green
    Write-Host "   ${QuayRepo}:${Tag}" -ForegroundColor White
    Write-Host "`nPara desplegar en OpenShift:" -ForegroundColor Yellow
    Write-Host "   oc set image deployment/cadetefrt container=${QuayRepo}:${Tag} -n wcdy-inte-frt" -ForegroundColor White
    Write-Host "   oc rollout status deployment/cadetefrt -n wcdy-inte-frt" -ForegroundColor White
} else {
    Write-Error "Error en el push a Quay"
    exit 1
}