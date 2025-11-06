param(
    [Parameter(Mandatory=$true)]
    [ValidateSet('wcdy-inte-frt','wcdy-cert-frt','wcdy-prod-frt')]
    [string]$Env,

    [Parameter(Mandatory=$true)]
    [string]$ExtPath,

    [string]$SqlPath,

    [string]$SourceMySqlHost,
    [int]$SourceMySqlPort = 3306,
    [string]$SourceMySqlUser,
    [string]$SourceMySqlPassword,
    [string]$SourceMySqlDatabase,

    [switch]$DeleteExtra
)

$ErrorActionPreference = 'Stop'

function Write-Info($msg) { Write-Host "[SYNC] $msg" -ForegroundColor Cyan }
function Write-Ok($msg)   { Write-Host "[SYNC] $msg" -ForegroundColor Green }
function Write-Warn($msg) { Write-Host "[SYNC] $msg" -ForegroundColor Yellow }
function Write-Err($msg)  { Write-Host "[SYNC] $msg" -ForegroundColor Red }

function Ensure-Command($name) {
    if (-not (Get-Command $name -ErrorAction SilentlyContinue)) {
        throw "Comando requerido no encontrado: $name"
    }
}

function Ensure-Project($env) {
    Write-Info "Seleccionando proyecto $env"
    & oc project $env | Out-Null
}

function Get-RunningPodByLabel($label) {
    $pod = & oc get pods -l $label --field-selector=status.phase=Running -o jsonpath='{.items[0].metadata.name}'
    if (-not $pod) { throw "No se encontró pod en estado Running para label: $label" }
    return $pod
}

function Describe-Deploy($name) {
    return & oc describe deploy $name
}

function Ensure-ExtVolumeMounted($env) {
    Write-Info "Verificando volumeMount del PVC web-pvc en deploy/cadetefrt"
    $desc = Describe-Deploy 'cadetefrt'
    if ($desc -match 'Volumes:\s*\n\s*ext-volume:') {
        if ($desc -notmatch 'Mounts:\s*/var/www/html/public/ext') {
            Write-Warn "PVC web-pvc existe como volumen, pero no aparece mounted en el contenedor. Añadiendo volumeMount..."
            & oc set volume deploy/cadetefrt --add -t pvc --name=ext-volume --claim-name=web-pvc --mount-path=/var/www/html/public/ext -n $Env | Out-Null
            Write-Info "Esperando rollout del deployment cadetefrt"
            & oc rollout status deploy/cadetefrt -n $Env | Out-Null
            Write-Ok "volumeMount añadido y deployment actualizado"
        } else {
            Write-Ok "El volumeMount de web-pvc ya está presente en /var/www/html/public/ext"
        }
    } else {
        Write-Warn "No se encontró el volumen ext-volume asociado a web-pvc en el deployment. Intentando añadirlo y montarlo..."
        & oc set volume deploy/cadetefrt --add -t pvc --name=ext-volume --claim-name=web-pvc --mount-path=/var/www/html/public/ext -n $Env | Out-Null
        & oc rollout status deploy/cadetefrt -n $Env | Out-Null
        Write-Ok "ext-volume añadido y montado en /var/www/html/public/ext"
    }
}

function Sync-ExtToPod($env, $pod, $extPath, [switch]$deleteExtra) {
    if (-not (Test-Path $extPath)) { throw "Ruta local de ext no existe: $extPath" }
    Write-Info "Sincronizando archivos de $extPath al pod $pod:/var/www/html/public/ext"

    $rsyncAvailable = Get-Command rsync -ErrorAction SilentlyContinue
    if ($rsyncAvailable) {
        $args = @('rsync', $extPath, "$env/$pod:/var/www/html/public/ext", '-c', 'container', '--progress', '--no-perms')
        if ($deleteExtra) { $args += '--delete' }
        & oc @args
    } else {
        Write-Warn "rsync no disponible. Se usará oc cp (copiado recursivo)."
        # oc cp requiere un destino de carpeta existente; aseguramos que existe
        & oc exec $pod -n $env -c container -- bash -lc "mkdir -p /var/www/html/public/ext"
        # Copiar el contenido del directorio ext al destino
        & oc cp $extPath "$env/$pod:/var/www/html/public/ext" -c container
        if ($deleteExtra) {
            Write-Warn "--delete no soportado con oc cp. Si necesitas espejo exacto, instala rsync."
        }
    }
    Write-Ok "Archivos sincronizados en /var/www/html/public/ext"
}

function Get-SecretValueB64($name, $key) {
    $b64 = & oc get secret $name -n $Env -o jsonpath="{.data.$key}"
    if (-not $b64) { throw "No se encontró la clave '$key' en el secret '$name'" }
    return [System.Text.Encoding]::ASCII.GetString([Convert]::FromBase64String($b64))
}

function Import-Database($env, $sqlPath) {
    if (-not (Test-Path $sqlPath)) { throw "Ruta de SQL no existe: $sqlPath" }
    Write-Info "Localizando pod de base de datos (label app=cadete3)"
    $dbPod = Get-RunningPodByLabel 'app=cadete3'
    Write-Ok "DB pod: $dbPod"

    $rootPwd = Get-SecretValueB64 'mysql-secret' 'MYSQL_ROOT_PASSWORD'
    $dbName  = Get-SecretValueB64 'mysql-secret' 'MYSQL_DATABASE'
    $appUser = Get-SecretValueB64 'mysql-secret' 'MYSQL_USER'
    $appPass = Get-SecretValueB64 'mysql-secret' 'MYSQL_PASSWORD'

    Write-Info "Copiando SQL al pod de DB"
    & oc cp $sqlPath "$env/$dbPod:/tmp/import.sql" -c container

    Write-Info "Creando usuario y aplicando GRANTs necesarios"
    $grantCmd = @(
        "mysql -u root -p'$rootPwd' -e \"CREATE USER IF NOT EXISTS '$appUser'@'%' IDENTIFIED BY '$appPass';\"",
        "mysql -u root -p'$rootPwd' -e \"GRANT SELECT, INSERT, UPDATE, DELETE, FILE ON *.* TO '$appUser'@'%'; FLUSH PRIVILEGES;\"",
        "mysql -u root -p'$rootPwd' -e \"CREATE DATABASE IF NOT EXISTS \`$dbName\`;\""
    ) -join ' && '
    & oc exec $dbPod -n $env -c container -- bash -lc $grantCmd

    Write-Info "Importando SQL en la base '$dbName'"
    & oc exec $dbPod -n $env -c container -- bash -lc "mysql -u root -p'$rootPwd' '$dbName' < /tmp/import.sql"

    Write-Ok "Importación SQL completada"
}

function Export-Database($host,$port,$user,$pass,$db) {
    Ensure-Command 'mysqldump'
    $out = Join-Path $env:TEMP ("cadete_export_{0}.sql" -f (Get-Date -Format "yyyyMMddHHmmss"))
    Write-Info "Exportando MySQL origen $user@$host:$port/$db a $out"
    & mysqldump -h $host -P $port -u $user ("-p{0}" -f $pass) $db --single-transaction --quick --routines --triggers --events --set-gtid-purged=OFF > $out
    if (-not (Test-Path $out)) { throw "No se generó el volcado SQL en $out" }
    Write-Ok "Exportación completada: $out"
    return $out
}

# --- Main ---
Ensure-Command 'oc'
Ensure-Project $Env

# Validar y normalizar rutas locales
$ExtPath = (Resolve-Path $ExtPath).Path
Write-Info "ExtPath: $ExtPath"

if ($SqlPath) {
    $SqlPath = (Resolve-Path $SqlPath).Path
    Write-Info "SqlPath: $SqlPath"
} else {
    if ($SourceMySqlHost -and $SourceMySqlUser -and $SourceMySqlPassword -and $SourceMySqlDatabase) {
        $SqlPath = Export-Database -host $SourceMySqlHost -port $SourceMySqlPort -user $SourceMySqlUser -pass $SourceMySqlPassword -db $SourceMySqlDatabase
        Write-Info "SqlPath (exportado): $SqlPath"
    } else {
        throw "No se especificó -SqlPath ni parámetros de MySQL origen (-SourceMySqlHost/-User/-Password/-Database)."
    }
}

# Asegurar volume mount en el web deployment
Ensure-ExtVolumeMounted $Env

# Localizar pod del frontend y sincronizar archivos
$webPod = Get-RunningPodByLabel 'app=cadetefrt'
Write-Ok "Web pod: $webPod"
Sync-ExtToPod -env $Env -pod $webPod -extPath $ExtPath -deleteExtra:$DeleteExtra

# Importar la base de datos
Import-Database -env $Env -sqlPath $SqlPath

Write-Ok "Sincronización completada para entorno: $Env"