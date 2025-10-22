param()
$ErrorActionPreference = "Stop"

Write-Host "== Implementación MySQL Seed vía oc ==" -ForegroundColor Cyan

# 1) Parámetros mínimos
$Namespace      = Read-Host "Namespace destino (p.ej. wcdy-cert-frt, wcdy-inte-frt, produccion-namespace)"
$DeployName     = Read-Host "Nombre del Deployment MySQL (p.ej. cadete-db)"
$SeedPVCName    = Read-Host "Nombre del PVC de semilla [mysql-seed-pvc]"
if ([string]::IsNullOrWhiteSpace($SeedPVCName)) { $SeedPVCName = "mysql-seed-pvc" }
$SeedPVCSize    = Read-Host "Tamaño del PVC [3Gi]"
if ([string]::IsNullOrWhiteSpace($SeedPVCSize)) { $SeedPVCSize = "3Gi" }
$StorageClass   = Read-Host "StorageClassName [apps-csi]"
if ([string]::IsNullOrWhiteSpace($StorageClass)) { $StorageClass = "apps-csi" }
$BusyBoxImage   = Read-Host "Imagen BusyBox [quay.apps.ocgc4tools.mgmt.dc.es.telefonica/wcdy/busybox:1.0]"
if ([string]::IsNullOrWhiteSpace($BusyBoxImage)) { $BusyBoxImage = "quay.apps.ocgc4tools.mgmt.dc.es.telefonica/wcdy/busybox:1.0" }
$ImagePullSecret = Read-Host "ImagePullSecret (opcional, p.ej. quay-wcdy-pullsecret)"

$BackupGzPath   = Read-Host "Ruta del backup .sql.gz (p.ej. backups/cadete-prod-YYYYMMDD.sql.gz o examples/cadete-example-backup.sql.gz)"
$GrantsPath     = Read-Host "Ruta del fichero de grants [templates/00-users-and-grants.sql]"
if ([string]::IsNullOrWhiteSpace($GrantsPath)) { 
  $GrantsPath = Join-Path (Split-Path $PSScriptRoot -Parent) "templates" "00-users-and-grants.sql"
}
$DbListPath     = Read-Host "Ruta del fichero de lista de bases [templates/db_list.txt]"
if ([string]::IsNullOrWhiteSpace($DbListPath)) { 
  $DbListPath = Join-Path (Split-Path $PSScriptRoot -Parent) "templates" "db_list.txt"
}

# Si las rutas no son absolutas, buscar en los directorios correspondientes
if (-not [System.IO.Path]::IsPathRooted($BackupGzPath)) {
  $RepoRoot = Split-Path $PSScriptRoot -Parent
  $BackupsPath = Join-Path $RepoRoot "backups" $BackupGzPath
  $ExamplesPath = Join-Path $RepoRoot "examples" $BackupGzPath
  if (Test-Path $BackupsPath) {
    $BackupGzPath = $BackupsPath
  } elseif (Test-Path $ExamplesPath) {
    $BackupGzPath = $ExamplesPath
  }
}

if (-not [System.IO.Path]::IsPathRooted($GrantsPath)) {
  $TemplateGrantsPath = Join-Path (Split-Path $PSScriptRoot -Parent) "templates" $GrantsPath
  if (Test-Path $TemplateGrantsPath) {
    $GrantsPath = $TemplateGrantsPath
  }
}

if (-not [System.IO.Path]::IsPathRooted($DbListPath)) {
  $TemplateDbListPath = Join-Path (Split-Path $PSScriptRoot -Parent) "templates" $DbListPath
  if (Test-Path $TemplateDbListPath) {
    $DbListPath = $TemplateDbListPath
  }
}

# Validaciones rutas
foreach ($p in @($BackupGzPath,$GrantsPath,$DbListPath)) { if (-not (Test-Path $p)) { throw "No existe: $p" } }

# 2) Detectar container del deployment
$ContainerName = oc get deploy $DeployName -n $Namespace -o jsonpath='{.spec.template.spec.containers[0].name}'
if (-not $ContainerName) { throw "No se pudo obtener el nombre del contenedor del deployment $DeployName en $Namespace" }
Write-Host "Contenedor MySQL: $ContainerName" -ForegroundColor Yellow

# 3) Crear PVC de semilla si no existe
$seedExists = oc get pvc $SeedPVCName -n $Namespace --ignore-not-found
if ([string]::IsNullOrWhiteSpace($seedExists)) {
  Write-Host "Creando PVC $SeedPVCName ($SeedPVCSize, sc=$StorageClass)" -ForegroundColor Cyan
  $pvcYaml = @"
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: $SeedPVCName
spec:
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: $SeedPVCSize
  storageClassName: $StorageClass
"@
  $pvcYaml | oc apply -n $Namespace -f - | Out-Null
} else { Write-Host "PVC $SeedPVCName ya existe, se reutiliza" -ForegroundColor Yellow }

# 4) Crear pod uploader con BusyBox y montar /seed
Write-Host "Creando pod uploader-seed" -ForegroundColor Cyan
$podYaml = @"
apiVersion: v1
kind: Pod
metadata:
  name: uploader-seed
spec:
  containers:
  - name: uploader
    image: $BusyBoxImage
    command: ['sh','-c','sleep infinity']
    imagePullPolicy: Always
    volumeMounts:
    - name: seed
      mountPath: /seed
  volumes:
  - name: seed
    persistentVolumeClaim:
      claimName: $SeedPVCName
"@
if (-not [string]::IsNullOrWhiteSpace($ImagePullSecret)) {
  $podYaml = $podYaml + @"
  imagePullSecrets:
  - name: $ImagePullSecret
"@
}
$podYaml | oc apply -n $Namespace -f - | Out-Null

# 5) Esperar pod uploader ready
oc wait -n $Namespace --for=condition=Ready pod/uploader-seed --timeout=120s | Out-Null

# 6) Copiar ficheros al pod
Write-Host "Copiando backup y ficheros al pod uploader-seed:/seed" -ForegroundColor Cyan
oc cp -n $Namespace "$BackupGzPath" uploader-seed:/seed/ | Out-Null
oc cp -n $Namespace "$GrantsPath" uploader-seed:/seed/00-users-and-grants.sql | Out-Null
oc cp -n $Namespace "$DbListPath" uploader-seed:/seed/db_list.txt | Out-Null

# 7) Escalar MySQL a 0
Write-Host "Escalando $DeployName a 0" -ForegroundColor Cyan
oc scale deploy/$DeployName -n $Namespace --replicas=0 | Out-Null
oc rollout status deploy/$DeployName -n $Namespace --watch | Out-Null

# 8) Montar seed en el deployment y añadir initContainer de limpieza
Write-Host "Montando seed PVC y añadiendo initContainer de limpieza" -ForegroundColor Cyan
oc set volume deploy/$DeployName -n $Namespace --add --name=seed --type=pvc --claim-name=$SeedPVCName --mount-path=/docker-entrypoint-initdb.d | Out-Null

# Añadir/actualizar initContainers por patch (JSON)
$init = @{ 
  name = "wipe-mysql-data"; image = $BusyBoxImage; imagePullPolicy = "Always";
  command = @("sh","-c","set -euxo pipefail; echo Wiping /var/lib/mysql; ls -la /var/lib/mysql; rm -rf /var/lib/mysql/* /var/lib/mysql/.[!.]* /var/lib/mysql/..?* || true; ls -la /var/lib/mysql");
  volumeMounts = @(@{ name = "mysql-data"; mountPath = "/var/lib/mysql" })
}
$patchObj = @{ spec = @{ template = @{ spec = @{ initContainers = @($init) } } } }
$patchJson = $patchObj | ConvertTo-Json -Depth 10
oc patch deploy/$DeployName -n $Namespace --type merge -p $patchJson | Out-Null

# 9) Eliminar pod uploader para liberar el PVC RWO
Write-Host "Eliminando pod uploader-seed para liberar PVC" -ForegroundColor Cyan
oc delete pod/uploader-seed -n $Namespace --ignore-not-found | Out-Null

# 10) Escalar MySQL a 1 y esperar rollout
Write-Host "Escalando $DeployName a 1 y esperando importación inicial" -ForegroundColor Cyan
oc scale deploy/$DeployName -n $Namespace --replicas=1 | Out-Null
oc rollout status deploy/$DeployName -n $Namespace --watch | Out-Null

# 11) Detectar pod y password root
$Pod = (oc get pods -n $Namespace -o name | Select-String -Pattern "^pod/$DeployName-" | ForEach-Object { $_.Line.Split('/')[-1] } | Select-Object -First 1)
if (-not $Pod) { throw "No hay pods activos para $DeployName en $Namespace" }
Write-Host "Pod activo: $Pod" -ForegroundColor Yellow
try { $RootPwd = oc rsh -n $Namespace -c $ContainerName $Pod printenv MYSQL_ROOT_PASSWORD } catch { $RootPwd = $null }
if ([string]::IsNullOrWhiteSpace($RootPwd)) {
  $RootPwdSec = Read-Host -AsSecureString "Introduce MYSQL_ROOT_PASSWORD (no se mostrará)"
  $RootPwd = [Runtime.InteropServices.Marshal]::PtrToStringAuto([Runtime.InteropServices.Marshal]::SecureStringToBSTR($RootPwdSec))
}
$RootPwd = $RootPwd.Trim()

# 12) Aplicar grants (fix automático de 'ON .' a 'ON *.*')
$grantsContent = Get-Content -Raw -Path $GrantsPath
$grantsContent = [regex]::Replace($grantsContent, "ON\s+\.", "ON *.*")
$grantsTmp = Join-Path ([System.IO.Path]::GetDirectoryName($GrantsPath)) "00-users-and-grants.fixed.sql"
$grantsContent | Set-Content -Path $grantsTmp -Encoding UTF8
oc cp -n $Namespace "$grantsTmp" "$Pod:/docker-entrypoint-initdb.d/00-users-and-grants.sql" | Out-Null

Write-Host "Aplicando grants dentro del contenedor" -ForegroundColor Cyan
oc exec -n $Namespace $Pod -c $ContainerName -- sh -lc "mysql -h 127.0.0.1 -uroot -p$RootPwd < /docker-entrypoint-initdb.d/00-users-and-grants.sql" | Out-Null

# 13) Validaciones básicas
Write-Host "Validando bases de datos y grants" -ForegroundColor Cyan
oc exec -n $Namespace $Pod -c $ContainerName -- sh -lc "mysql -h 127.0.0.1 -uroot -p$RootPwd -e 'SHOW DATABASES;'" 
oc exec -n $Namespace $Pod -c $ContainerName -- sh -lc "mysql -h 127.0.0.1 -uroot -p$RootPwd -e 'SELECT Host,User FROM mysql.user;'" 

# 14) Limpieza opcional (retirar initContainer y seed)
$doClean = Read-Host "¿Retirar initContainer y desmontar seed PVC? [s/N]"
if ($doClean -match '^[sS]$') {
  Write-Host "Retirando volumen seed y initContainers" -ForegroundColor Cyan
  oc set volume deploy/$DeployName -n $Namespace --remove --name=seed | Out-Null
  oc patch deploy/$DeployName -n $Namespace --type=json -p '[{"op":"remove","path":"/spec/template/spec/initContainers"}]' | Out-Null
  oc rollout restart deploy/$DeployName -n $Namespace | Out-Null
  oc rollout status deploy/$DeployName -n $Namespace --watch | Out-Null
  Write-Host "Limpieza completada" -ForegroundColor Green
}

Write-Host "Proceso finalizado correctamente" -ForegroundColor Green