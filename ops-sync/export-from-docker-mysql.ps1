param(
    [string]$ContainerName,
    [string]$DatabaseName,
    [string]$AppUser,
    [string]$AppPassword,
    [string]$OutPath
)

$ErrorActionPreference = 'Stop'

function Write-Info($msg) { Write-Host "[EXPORT] $msg" -ForegroundColor Cyan }
function Write-Ok($msg)   { Write-Host "[EXPORT] $msg" -ForegroundColor Green }
function Write-Warn($msg) { Write-Host "[EXPORT] $msg" -ForegroundColor Yellow }
function Write-Err($msg)  { Write-Host "[EXPORT] $msg" -ForegroundColor Red }

function Ensure-Command($name) {
    if (-not (Get-Command $name -ErrorAction SilentlyContinue)) {
        throw "Comando requerido no encontrado: $name"
    }
}

function Detect-MySqlContainer([string]$preferred) {
    if ($preferred) {
        $exists = & docker ps --format "{{.Names}}" | Where-Object { $_ -eq $preferred }
        if (-not $exists) { throw "No se encontró el contenedor especificado: $preferred" }
        return $preferred
    }
    $candidates = & docker ps --format "{{.Names}} {{.Image}}" | Where-Object { $_ -match 'mysql' }
    if (-not $candidates) { throw "No se encontró ningún contenedor MySQL en ejecución" }
    $first = ($candidates | Select-Object -First 1).Split(' ')[0]
    Write-Warn "Seleccionado contenedor MySQL por heurística: $first"
    return $first
}

function Get-ContainerEnv($container) {
    $envLines = & docker inspect -f '{{range .Config.Env}}{{println .}}{{end}}' $container
    $env = @{}
    foreach ($line in $envLines) {
        if ($line -match '^(.*?)=(.*)$') { $env[$matches[1]] = $matches[2] }
    }
    return $env
}

function Get-NonSystemDatabases($container, $rootPwd) {
    $cmd = "mysql -u root -p'$rootPwd' -e \"SHOW DATABASES;\" | tail -n +2"
    $out = & docker exec $container sh -lc $cmd
    $system = @('information_schema','performance_schema','mysql','sys')
    return $out | Where-Object { $system -notcontains $_ }
}

function Ensure-OutputPath([string]$path) {
    if (-not $path) {
        $ts = Get-Date -Format "yyyyMMddHHmmss"
        $defaultDir = Join-Path (Split-Path $PSScriptRoot -Parent) 'backups'
        if (-not (Test-Path $defaultDir)) { New-Item -ItemType Directory -Path $defaultDir | Out-Null }
        $path = Join-Path $defaultDir ("docker-prod-export-$ts.sql")
    } else {
        $dir = Split-Path $path -Parent
        if ($dir -and -not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir | Out-Null }
    }
    return $path
}

# --- Main ---
Ensure-Command 'docker'

$container = Detect-MySqlContainer -preferred $ContainerName
Write-Ok "Contenedor MySQL: $container"

$secureRoot = Read-Host -AsSecureString -Prompt "Introduce la contraseña de root MySQL (no se guarda)"
$rootPwd = (New-Object System.Net.NetworkCredential('', $secureRoot)).Password

$env = Get-ContainerEnv $container
if (-not $AppUser) { $AppUser = $env['MYSQL_USER']; if (-not $AppUser) { $AppUser = 'user'; Write-Warn "MYSQL_USER no encontrado; usando 'user'" } }
if (-not $AppPassword) { $AppPassword = $env['MYSQL_PASSWORD']; if (-not $AppPassword) { Write-Warn "MYSQL_PASSWORD no encontrado; se solicitará"; $AppPassword = Read-Host -Prompt "Introduce la contraseña del usuario de aplicación ($AppUser)" } }

# Sin menú: por defecto exporta la base 'user' si no se pasa -DatabaseName
$databasesToExport = @()
if ($DatabaseName) {
    $databasesToExport = @($DatabaseName)
} else {
    $databasesToExport = @('user')
}

# Validar que existen y no son sistema
$availableNonSystem = Get-NonSystemDatabases -container $container -rootPwd $rootPwd
foreach ($db in $databasesToExport) {
    if ($availableNonSystem -notcontains $db) { throw "La base '$db' no existe o es una base de sistema" }
}
Write-Info "Bases a exportar: $($databasesToExport -join ', ')"

$OutPath = Ensure-OutputPath $OutPath
Write-Info "Exportando bases '$($databasesToExport -join ', ')' del contenedor $container"

# Inicializar fichero de volcado dentro del contenedor
& docker exec $container sh -lc "rm -f /tmp/export.sql && touch /tmp/export.sql"

# Volcar cada base y anexar al fichero
foreach ($db in $databasesToExport) {
    $cmd = "mysqldump -u root -p'$rootPwd' '$db' --single-transaction --quick --routines --triggers --events >> /tmp/export.sql"
    & docker exec $container sh -lc $cmd
}

# Añadir usuario y GRANTs al final
$grants = @(
    "printf '%s\\n' \"SET sql_log_bin=0;\" \"CREATE USER IF NOT EXISTS '$AppUser'@'%' IDENTIFIED BY '$AppPassword';\" \"GRANT SELECT, INSERT, UPDATE, DELETE, FILE ON *.* TO '$AppUser'@'%';\" \"FLUSH PRIVILEGES;\" >> /tmp/export.sql"
)
& docker exec $container sh -lc ($grants -join ' && ')

# Copiar al host y limpiar
& docker cp "$container:/tmp/export.sql" "$OutPath"
& docker exec $container sh -lc "rm -f /tmp/export.sql"

Write-Ok "Volcado generado: $OutPath"
Write-Info "Puedes usar este SQL con ops-sync/sync-to-openshift.ps1: -SqlPath \"$OutPath\""