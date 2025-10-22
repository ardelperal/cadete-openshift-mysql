param()
$ErrorActionPreference = "Stop"

Write-Host "== MySQL Backup via oc ==" -ForegroundColor Cyan

# 1) Parameters
$Namespace = Read-Host "Namespace (e.g., wcdy-cert-frt, wcdy-inte-frt, Producción)"
$DeployName = Read-Host "MySQL Deployment name (e.g., cadete-db)"

# Detect container name from deployment
$ContainerName = oc get deploy $DeployName -n $Namespace -o jsonpath='{.spec.template.spec.containers[0].name}'
if (-not $ContainerName) { throw "No se pudo obtener el nombre del contenedor del deployment $DeployName en $Namespace" }
Write-Host "Contenedor detectado: $ContainerName" -ForegroundColor Yellow

# Pick pod belonging to deployment
$Pod = (oc get pods -n $Namespace -o name | Select-String -Pattern "^pod/$DeployName-" | ForEach-Object { $_.Line.Split('/')[-1] } | Select-Object -First 1)
if (-not $Pod) { throw "No hay pods activos para $DeployName en $Namespace" }
Write-Host "Pod: $Pod" -ForegroundColor Yellow

# Root password detection
try {
  $RootPwd = oc rsh -n $Namespace -c $ContainerName $Pod printenv MYSQL_ROOT_PASSWORD
} catch { $RootPwd = $null }
if ([string]::IsNullOrWhiteSpace($RootPwd)) {
  $RootPwd = Read-Host -AsSecureString "Introduce MYSQL_ROOT_PASSWORD (no se mostrará)"
  $RootPwdPlain = [Runtime.InteropServices.Marshal]::PtrToStringAuto([Runtime.InteropServices.Marshal]::SecureStringToBSTR($RootPwd))
} else {
  $RootPwdPlain = $RootPwd.Trim()
}

# DB selection
$DbChoice = Read-Host "¿Base de datos? Escribe 'ALL' para todas (excluye sistema) o ruta de archivo con lista (por ejemplo templates/db_list.txt)"
$DbList = @()
if ($DbChoice -eq 'ALL') {
  $dbs = oc exec -n $Namespace $Pod -c $ContainerName -- sh -lc "mysql -h 127.0.0.1 -uroot -p$RootPwdPlain -e 'SHOW DATABASES;' | tail -n +2" | ForEach-Object { $_.Trim() }
  $DbList = $dbs | Where-Object { $_ -and $_ -notin @('information_schema','performance_schema','mysql','sys') }
} else {
  # Si no es ruta absoluta, buscar en templates/ primero
  if (-not [System.IO.Path]::IsPathRooted($DbChoice)) {
    $TemplateDbPath = Join-Path (Split-Path $PSScriptRoot -Parent) "templates" $DbChoice
    if (Test-Path $TemplateDbPath) {
      $DbChoice = $TemplateDbPath
    }
  }
  if (-not (Test-Path $DbChoice)) { throw "No existe el archivo de lista: $DbChoice" }
  $DbList = Get-Content -Path $DbChoice | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | ForEach-Object { $_.Trim() }
}
if (-not $DbList -or $DbList.Count -eq 0) { throw "La lista de bases de datos está vacía" }
Write-Host ("Se van a exportar {0} bases: {1}" -f $DbList.Count, ($DbList -join ', ')) -ForegroundColor Yellow

# Output files - generar en directorio backups/
$DateTag = Get-Date -Format 'yyyyMMdd'
$BackupsDir = Join-Path (Split-Path $PSScriptRoot -Parent) "backups"
if (-not (Test-Path $BackupsDir)) { New-Item -ItemType Directory -Path $BackupsDir -Force | Out-Null }
$SqlPath = Join-Path $BackupsDir ("{0}-{1}.sql" -f $DeployName, $DateTag)
$GzPath  = "${SqlPath}.gz"

# 2) Dump
Write-Host "Ejecutando mysqldump dentro del contenedor..." -ForegroundColor Cyan
$DbArgs = ($DbList | ForEach-Object { "`"$_`"" }) -join ' '
oc exec -n $Namespace $Pod -c $ContainerName -- sh -lc "mysqldump -h 127.0.0.1 -uroot -p$RootPwdPlain --single-transaction --quick --lock-tables=false --databases $DbArgs" | Set-Content -Path $SqlPath -Encoding UTF8

# 3) Compress to .gz (PowerShell/.NET)
Write-Host "Comprimiendo a GZip: $GzPath" -ForegroundColor Cyan
$fsIn = [System.IO.File]::OpenRead($SqlPath)
$fsOut = [System.IO.File]::Create($GzPath)
$gzip = New-Object System.IO.Compression.GzipStream($fsOut, [System.IO.Compression.CompressionLevel]::Optimal)
$fsIn.CopyTo($gzip)
$gzip.Close(); $fsIn.Close(); $fsOut.Close()

# 4) Summary
$size = (Get-Item $GzPath).Length
Write-Host ("Backup generado: {0} ({1} bytes)" -f $GzPath, $size) -ForegroundColor Green
Write-Host "Listo. Puedes usar este .gz en el script de implementación." -ForegroundColor Green