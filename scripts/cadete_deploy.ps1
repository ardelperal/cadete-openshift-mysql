param(
    [Parameter(Mandatory=$false)]
    [string]$TarFilePath,
    
    [Parameter(Mandatory=$false)]
    [string]$Environment,
    
    [Parameter(Mandatory=$false)]
    [string]$DeploymentName = "cadete",
    
    [Parameter(Mandatory=$false)]
    [string]$QuayRegistry = "quay.apps.ocgc4tools.mgmt.dc.es.telefonica",
    
    [Parameter(Mandatory=$false)]
    [string]$QuayProject = "wcdy",
    
    [Parameter(Mandatory=$false)]
    [switch]$SkipImagePush,
    
    [Parameter(Mandatory=$false)]
    [switch]$DryRun
)

$ErrorActionPreference = "Stop"

# Configuración de entornos
$Environments = @{
    "cert" = @{
        "namespace" = "wcdy-cert-frt"
        "displayName" = "Certificación/Preproducción 1"
    }
    "inte" = @{
        "namespace" = "wcdy-inte-frt"
        "displayName" = "Integración/Preproducción 2"
    }
    "prod" = @{
        "namespace" = "wcdy-prod-frt"
        "displayName" = "Producción"
    }
}

function Write-Header {
    param([string]$Title)
    Write-Host "`n" + "="*60 -ForegroundColor Cyan
    Write-Host " $Title" -ForegroundColor Cyan
    Write-Host "="*60 -ForegroundColor Cyan
}

function Connect-OpenShift {
    param([string]$Environment)
    
    Write-Step "Conectando a OpenShift" 1
    
    # Cargar configuración de OpenShift
    $ocConfigFile = Join-Path $PSScriptRoot "..\templates\openshift_config.json"
    try {
        $ocConfig = Get-Content $ocConfigFile -Raw | ConvertFrom-Json
    }
    catch {
        Write-Error "Error al leer configuración de OpenShift: $_"
        exit 1
    }
    
    # Obtener configuración del entorno
    if (-not $ocConfig.environments.$Environment) {
        Write-Error "Entorno '$Environment' no encontrado en la configuración"
        Write-Host "Entornos disponibles: $($ocConfig.environments.PSObject.Properties.Name -join ', ')" -ForegroundColor Yellow
        exit 1
    }
    
    $envConfig = $ocConfig.environments.$Environment
    
    # Realizar login automático
    Write-Host "Conectando a: $($envConfig.server)" -ForegroundColor Cyan
    Write-Host "Namespace: $($envConfig.namespace)" -ForegroundColor Cyan
    
    try {
        $loginResult = oc login --token=$($envConfig.token) --server=$($envConfig.server) 2>&1
        if ($LASTEXITCODE -ne 0) {
            throw "Login falló: $loginResult"
        }
        
        # Cambiar al namespace correcto
        $projectResult = oc project $($envConfig.namespace) 2>&1
        if ($LASTEXITCODE -ne 0) {
            throw "No se pudo cambiar al proyecto: $projectResult"
        }
        
        Write-Success "Conectado exitosamente a OpenShift"
        Write-Success "Proyecto actual: $($envConfig.namespace)"
        
        return $envConfig
    }
    catch {
        Write-Error "Error al conectar con OpenShift: $_"
        Write-Host "Verifica que el token y servidor sean correctos en openshift_config.json" -ForegroundColor Yellow
        exit 1
    }
}

function Write-Step {
    param([string]$Step, [int]$Number)
    Write-Host "`n[$Number] $Step" -ForegroundColor Yellow
}

function Write-Command {
    param([string]$Command)
    Write-Host "    > $Command" -ForegroundColor Gray
}

function Write-Success {
    param([string]$Message)
    Write-Host "✅ $Message" -ForegroundColor Green
}

function Write-Warning {
    param([string]$Message)
    Write-Host "⚠️  $Message" -ForegroundColor Yellow
}

function Write-Error {
    param([string]$Message)
    Write-Host "❌ $Message" -ForegroundColor Red
}

function Test-Prerequisites {
    Write-Step "Verificando prerrequisitos" 1
    
    # Verificar oc CLI
    try {
        $ocVersion = oc version --client 2>$null
        Write-Success "oc CLI disponible: $($ocVersion -split "`n" | Select-Object -First 1)"
    }
    catch {
        Write-Error "oc CLI no está disponible. Instala OpenShift CLI."
        exit 1
    }
    
    # Verificar podman
    try {
        $podmanVersion = podman --version 2>$null
        Write-Success "Podman disponible: $podmanVersion"
    }
    catch {
        Write-Error "Podman no está disponible. Instala Podman para manejar imágenes."
        exit 1
    }
    
    # Verificar archivo de autenticación Quay
    $authFile = Join-Path $PSScriptRoot "..\templates\openshift_push_auth.json"
    if (-not (Test-Path $authFile)) {
        Write-Error "Archivo de autenticación Quay no encontrado: $authFile"
        Write-Host "Asegúrate de que el archivo openshift_push_auth.json esté en la carpeta templates/" -ForegroundColor Yellow
        exit 1
    }
    Write-Success "Archivo de autenticación Quay encontrado: $authFile"
    
    # Verificar archivo de configuración OpenShift
    $ocConfigFile = Join-Path $PSScriptRoot "..\templates\openshift_config.json"
    if (-not (Test-Path $ocConfigFile)) {
        Write-Error "Archivo de configuración OpenShift no encontrado: $ocConfigFile"
        Write-Host "Asegúrate de que el archivo openshift_config.json esté en la carpeta templates/" -ForegroundColor Yellow
        exit 1
    }
    Write-Success "Archivo de configuración OpenShift encontrado: $ocConfigFile"
}

function Get-TarFilePath {
    if (-not $TarFilePath) {
        Write-Host "`n📁 Selecciona el archivo .tar de Cadete:" -ForegroundColor Cyan
        
        # Buscar archivos .tar en el directorio actual
        $tarFiles = Get-ChildItem -Path "." -Filter "cadete*.tar" -ErrorAction SilentlyContinue
        
        if ($tarFiles.Count -gt 0) {
            Write-Host "`nArchivos .tar encontrados:" -ForegroundColor Green
            for ($i = 0; $i -lt $tarFiles.Count; $i++) {
                Write-Host "  [$($i+1)] $($tarFiles[$i].Name)" -ForegroundColor White
            }
            
            $selection = Read-Host "`nSelecciona un archivo (1-$($tarFiles.Count)) o ingresa la ruta completa"
            
            if ($selection -match '^\d+$' -and [int]$selection -le $tarFiles.Count -and [int]$selection -gt 0) {
                $TarFilePath = $tarFiles[[int]$selection - 1].FullName
            } else {
                $TarFilePath = $selection
            }
        } else {
            $TarFilePath = Read-Host "Ingresa la ruta completa al archivo .tar de Cadete"
        }
    }
    
    if (-not (Test-Path $TarFilePath)) {
        Write-Error "El archivo $TarFilePath no existe."
        exit 1
    }
    
    Write-Success "Archivo .tar seleccionado: $TarFilePath"
    return $TarFilePath
}

function Get-Environment {
    if (-not $Environment) {
        Write-Host "`n🌍 Selecciona el entorno de despliegue:" -ForegroundColor Cyan
        
        $envKeys = $Environments.Keys | Sort-Object
        for ($i = 0; $i -lt $envKeys.Count; $i++) {
            $key = $envKeys[$i]
            $env = $Environments[$key]
            Write-Host "  [$($i+1)] $key - $($env.displayName) ($($env.namespace))" -ForegroundColor White
        }
        
        $selection = Read-Host "`nSelecciona un entorno (1-$($envKeys.Count))"
        
        if ($selection -match '^\d+$' -and [int]$selection -le $envKeys.Count -and [int]$selection -gt 0) {
            $Environment = $envKeys[[int]$selection - 1]
        } else {
            Write-Error "Selección inválida."
            exit 1
        }
    }
    
    if (-not $Environments.ContainsKey($Environment)) {
        Write-Error "Entorno '$Environment' no válido. Opciones: $($Environments.Keys -join ', ')"
        exit 1
    }
    
    $selectedEnv = $Environments[$Environment]
    Write-Success "Entorno seleccionado: $($selectedEnv.displayName) ($($selectedEnv.namespace))"
    return $Environment
}

function Load-ImageFromTar {
    param([string]$TarPath)
    
    Write-Step "Cargando imagen desde archivo .tar" 2
    
    $loadCommand = "podman load -i `"$TarPath`""
    Write-Command $loadCommand
    
    if (-not $DryRun) {
        try {
            $loadResult = Invoke-Expression $loadCommand 2>&1
            Write-Host $loadResult -ForegroundColor Gray
            
            # Extraer el nombre de la imagen del resultado
            $imageNameMatch = $loadResult | Select-String "Loaded image.*: (.+)" 
            if ($imageNameMatch) {
                $imageName = $imageNameMatch.Matches[0].Groups[1].Value
                Write-Success "Imagen cargada: $imageName"
                return $imageName
            } else {
                Write-Error "No se pudo determinar el nombre de la imagen cargada."
                exit 1
            }
        }
        catch {
            Write-Error "Error al cargar la imagen: $($_.Exception.Message)"
            exit 1
        }
    } else {
        Write-Host "    [DRY RUN] Imagen se cargaría desde: $TarPath" -ForegroundColor Magenta
        return "cadete:latest"
    }
}

function Push-ImageToQuay {
    param([string]$LocalImageName, [string]$Environment)
    
    Write-Step "Subiendo imagen a Quay" 3
    
    # Autenticarse con Quay usando el archivo de credenciales
    $authFile = Join-Path $PSScriptRoot "..\templates\openshift_push_auth.json"
    $loginCommand = "podman login --authfile `"$authFile`" $QuayRegistry"
    Write-Command $loginCommand
    
    if (-not $DryRun) {
        try {
            Invoke-Expression $loginCommand 2>$null
            Write-Success "Autenticado exitosamente con Quay Registry"
        }
        catch {
            Write-Error "Error al autenticarse con Quay: $($_.Exception.Message)"
            Write-Host "Verifica que el archivo openshift_push_auth.json tenga las credenciales correctas" -ForegroundColor Yellow
            exit 1
        }
    }
    
    # Generar timestamp para el tag
    $timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
    $newTag = "$QuayRegistry/$QuayProject/cadete:$Environment-$timestamp"
    $latestTag = "$QuayRegistry/$QuayProject/cadete:$Environment-latest"
    
    # Tag de la imagen
    $tagCommand = "podman tag `"$LocalImageName`" `"$newTag`""
    Write-Command $tagCommand
    
    if (-not $DryRun) {
        try {
            Invoke-Expression $tagCommand
            Write-Success "Imagen etiquetada: $newTag"
        }
        catch {
            Write-Error "Error al etiquetar la imagen: $($_.Exception.Message)"
            exit 1
        }
    }
    
    # Tag latest
    $tagLatestCommand = "podman tag `"$LocalImageName`" `"$latestTag`""
    Write-Command $tagLatestCommand
    
    if (-not $DryRun) {
        try {
            Invoke-Expression $tagLatestCommand
            Write-Success "Imagen etiquetada: $latestTag"
        }
        catch {
            Write-Error "Error al etiquetar la imagen latest: $($_.Exception.Message)"
            exit 1
        }
    }
    
    # Push de la imagen con timestamp
    $pushCommand = "podman push --authfile `"$authFile`" `"$newTag`""
    Write-Command $pushCommand
    
    if (-not $DryRun) {
        try {
            Invoke-Expression $pushCommand
            Write-Success "Imagen subida a Quay: $newTag"
        }
        catch {
            Write-Error "Error al subir la imagen: $($_.Exception.Message)"
            exit 1
        }
    }
    
    # Push de la imagen latest
    $pushLatestCommand = "podman push --authfile `"$authFile`" `"$latestTag`""
    Write-Command $pushLatestCommand
    
    if (-not $DryRun) {
        try {
            Invoke-Expression $pushLatestCommand
            Write-Success "Imagen latest subida a Quay: $latestTag"
        }
        catch {
            Write-Error "Error al subir la imagen latest: $($_.Exception.Message)"
            exit 1
        }
    } else {
        Write-Host "    [DRY RUN] Se subirían las imágenes:" -ForegroundColor Magenta
        Write-Host "    - $newTag" -ForegroundColor Magenta
        Write-Host "    - $latestTag" -ForegroundColor Magenta
    }
    
    return $newTag
}

function Update-Deployment {
    param([string]$ImageName, [string]$Environment)
    
    Write-Step "Actualizando deployment en OpenShift" 4
    
    $namespace = $Environments[$Environment].namespace
    
    # Cambiar al namespace correcto
    $projectCommand = "oc project $namespace"
    Write-Command $projectCommand
    
    if (-not $DryRun) {
        try {
            Invoke-Expression $projectCommand
            Write-Success "Cambiado al proyecto: $namespace"
        }
        catch {
            Write-Error "Error al cambiar al proyecto $namespace : $($_.Exception.Message)"
            exit 1
        }
    }
    
    # Verificar si existe el deployment
    $checkDeploymentCommand = "oc get deployment $DeploymentName -n $namespace"
    Write-Command $checkDeploymentCommand
    
    if (-not $DryRun) {
        try {
            Invoke-Expression $checkDeploymentCommand | Out-Null
            Write-Success "Deployment '$DeploymentName' encontrado en $namespace"
        }
        catch {
            Write-Error "Deployment '$DeploymentName' no encontrado en $namespace"
            exit 1
        }
    }
    
    # Actualizar la imagen del deployment
    $setImageCommand = "oc set image deployment/$DeploymentName cadete=`"$ImageName`" -n $namespace"
    Write-Command $setImageCommand
    
    if (-not $DryRun) {
        try {
            Invoke-Expression $setImageCommand
            Write-Success "Imagen del deployment actualizada: $ImageName"
        }
        catch {
            Write-Error "Error al actualizar la imagen del deployment: $($_.Exception.Message)"
            exit 1
        }
    }
    
    # Verificar el rollout
    $rolloutStatusCommand = "oc rollout status deployment/$DeploymentName -n $namespace --timeout=300s"
    Write-Command $rolloutStatusCommand
    
    if (-not $DryRun) {
        try {
            Invoke-Expression $rolloutStatusCommand
            Write-Success "Deployment actualizado exitosamente"
        }
        catch {
            Write-Error "Error en el rollout del deployment: $($_.Exception.Message)"
            Write-Warning "Puedes verificar el estado manualmente con: oc get pods -n $namespace"
            exit 1
        }
    } else {
        Write-Host "    [DRY RUN] Se actualizaría el deployment con la imagen: $ImageName" -ForegroundColor Magenta
    }
}

function Show-PostDeploymentInfo {
    param([string]$Environment, [string]$ImageName)
    
    Write-Step "Información post-despliegue" 5
    
    $namespace = $Environments[$Environment].namespace
    
    Write-Host "`n📋 Comandos útiles para verificación:" -ForegroundColor Cyan
    Write-Host "# Verificar pods:" -ForegroundColor Gray
    Write-Host "oc get pods -n $namespace -l app=$DeploymentName" -ForegroundColor White
    
    Write-Host "`n# Ver logs del pod:" -ForegroundColor Gray
    Write-Host "oc logs -f deployment/$DeploymentName -n $namespace" -ForegroundColor White
    
    Write-Host "`n# Verificar el deployment:" -ForegroundColor Gray
    Write-Host "oc describe deployment $DeploymentName -n $namespace" -ForegroundColor White
    
    Write-Host "`n# Rollback si es necesario:" -ForegroundColor Gray
    Write-Host "oc rollout undo deployment/$DeploymentName -n $namespace" -ForegroundColor White
    
    Write-Host "`n🎯 Resumen del despliegue:" -ForegroundColor Green
    Write-Host "- Entorno: $($Environments[$Environment].displayName)" -ForegroundColor White
    Write-Host "- Namespace: $namespace" -ForegroundColor White
    Write-Host "- Deployment: $DeploymentName" -ForegroundColor White
    Write-Host "- Nueva imagen: $ImageName" -ForegroundColor White
}

# ============================================================================
# MAIN EXECUTION
# ============================================================================

Write-Header "DESPLIEGUE DE CADETE - CICLO COMPLETO"

if ($DryRun) {
    Write-Warning "Modo DRY RUN activado - No se ejecutarán comandos reales"
}

# 1. Verificar prerrequisitos
Test-Prerequisites

# 2. Obtener parámetros si no se proporcionaron
$TarFilePath = Get-TarFilePath
$Environment = Get-Environment

# 3. Conectar a OpenShift automáticamente
$envConfig = Connect-OpenShift -Environment $Environment

# 4. Mostrar confirmación
Write-Host "`n🔍 CONFIRMACIÓN DE DESPLIEGUE:" -ForegroundColor Yellow
Write-Host "- Archivo .tar: $TarFilePath" -ForegroundColor White
Write-Host "- Entorno: $($Environments[$Environment].displayName)" -ForegroundColor White
Write-Host "- Namespace: $($Environments[$Environment].namespace)" -ForegroundColor White
Write-Host "- Deployment: $DeploymentName" -ForegroundColor White
Write-Host "- Registry: $QuayRegistry/$QuayProject" -ForegroundColor White

if (-not $DryRun) {
    $confirmation = Read-Host "`n¿Continuar con el despliegue? (s/N)"
    if ($confirmation -ne 's' -and $confirmation -ne 'S') {
        Write-Host "Despliegue cancelado por el usuario." -ForegroundColor Yellow
        exit 0
    }
}

try {
    # 5. Cargar imagen desde .tar
    if (-not $SkipImagePush) {
        $localImageName = Load-ImageFromTar -TarPath $TarFilePath
        
        # 6. Subir imagen a Quay
        $quayImageName = Push-ImageToQuay -LocalImageName $localImageName -Environment $Environment
    } else {
        Write-Warning "Saltando carga y push de imagen (--SkipImagePush especificado)"
        $timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
        $quayImageName = "$QuayRegistry/$QuayProject/cadete:$Environment-$timestamp"
    }
    
    # 7. Actualizar deployment
    Update-Deployment -ImageName $quayImageName -Environment $Environment
    
    # 8. Mostrar información post-despliegue
    Show-PostDeploymentInfo -Environment $Environment -ImageName $quayImageName
    
    Write-Header "DESPLIEGUE COMPLETADO EXITOSAMENTE"
    Write-Success "Cadete ha sido desplegado correctamente en $($Environments[$Environment].displayName)"
    
} catch {
    Write-Header "ERROR EN EL DESPLIEGUE"
    Write-Error "Error durante el despliegue: $($_.Exception.Message)"
    Write-Host "`nPara más detalles, revisa los logs anteriores." -ForegroundColor Yellow
    exit 1
}