param(
    [string]$ContainerName,
    [string]$RootPassword
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
    $cmd = "mysql -u root -p'$rootPwd' -e 'SHOW DATABASES;' | tail -n +2"
    $out = & docker exec $container sh -lc $cmd
    $system = @('information_schema','performance_schema','mysql','sys')
    return $out | Where-Object { $system -notcontains $_ }
}

function Get-OutputPath() {
    $ts = Get-Date -Format "yyyyMMddHHmmss"
    return (Join-Path $PSScriptRoot ("docker-export-$ts.sql"))
}

# --- Main ---
Ensure-Command 'docker'

if (-not $RootPassword) { throw "Debe proporcionar -RootPassword" }

$container = Detect-MySqlContainer -preferred $ContainerName
Write-Ok "Contenedor MySQL: $container"

$env = Get-ContainerEnv $container
$AppUser = 'user'
$AppPassword = $env['MYSQL_PASSWORD']
if (-not $AppPassword) { Write-Warn "MYSQL_PASSWORD no encontrado en el contenedor; se usará 'user' como contraseña"; $AppPassword = 'user' }

$databasesToExport = Get-NonSystemDatabases -container $container -rootPwd $RootPassword
if (-not $databasesToExport -or $databasesToExport.Count -eq 0) { throw "No se encontraron bases no-sistema para exportar" }
Write-Info "Bases a exportar: $($databasesToExport -join ', ')"

$OutPath = Get-OutputPath
Write-Info "Exportando bases '$($databasesToExport -join ', ')' del contenedor $container"

# Inicializar fichero de volcado dentro del contenedor
& docker exec $container sh -lc "rm -f /tmp/export.sql && touch /tmp/export.sql"

# Volcar cada base y anexar al fichero
foreach ($db in $databasesToExport) {
    $cmd = "mysqldump -u root -p'$RootPassword' '$db' --single-transaction --quick --routines --triggers --events >> /tmp/export.sql"
    & docker exec $container sh -lc $cmd
}

# Añadir usuario y GRANTs al final (usuario fijo 'user')
$grants = @(
    "printf '%s\\n' `"SET sql_log_bin=0;`" `"CREATE USER IF NOT EXISTS '$AppUser'@'%' IDENTIFIED BY '$AppPassword';`" `"GRANT SELECT, INSERT, UPDATE, DELETE, FILE ON *.* TO '$AppUser'@'%';`" `"FLUSH PRIVILEGES;`" >> /tmp/export.sql"
)
& docker exec $container sh -lc ($grants -join ' && ')

# Copiar al host y limpiar
& docker cp "${container}:/tmp/export.sql" "$OutPath"
& docker exec $container sh -lc "rm -f /tmp/export.sql"

Write-Ok "Volcado generado: $OutPath"
Write-Info "Puedes usar este SQL con ops-sync/sync-to-openshift.ps1: -SqlPath \"$OutPath\""