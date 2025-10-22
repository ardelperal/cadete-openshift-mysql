# Script para crear repositorio GitHub y subir archivos
# Ejecutar desde: C:\Proyectos\cadete_oc

Write-Host "=== Creación de Repositorio GitHub: cadete-openshift-mysql ===" -ForegroundColor Green

# Paso 1: Crear repositorio en GitHub (manual)
Write-Host "`n1. Crear repositorio en GitHub:" -ForegroundColor Yellow
Write-Host "   - Ve a: https://github.com/new"
Write-Host "   - Repository name: cadete-openshift-mysql"
Write-Host "   - Description: Automatización de backup y despliegue MySQL para aplicación Cadete en entornos OpenShift corporativos"
Write-Host "   - Public repository"
Write-Host "   - ✓ Add a README file"
Write-Host "   - Click 'Create repository'"

# Paso 2: Clonar y configurar localmente
Write-Host "`n2. Comandos para ejecutar después de crear el repo:" -ForegroundColor Yellow

$commands = @"
# Clonar el repositorio recién creado
git clone https://github.com/TU_USUARIO/cadete-openshift-mysql.git

# Navegar al directorio clonado
cd cadete-openshift-mysql

# Copiar archivos del proyecto actual
Copy-Item -Path "C:\Proyectos\cadete_oc\scripts" -Destination "." -Recurse -Force
Copy-Item -Path "C:\Proyectos\cadete_oc\templates" -Destination "." -Recurse -Force
Copy-Item -Path "C:\Proyectos\cadete_oc\examples" -Destination "." -Recurse -Force
Copy-Item -Path "C:\Proyectos\cadete_oc\backups" -Destination "." -Recurse -Force
Copy-Item -Path "C:\Proyectos\cadete_oc\docs" -Destination "." -Recurse -Force
Copy-Item -Path "C:\Proyectos\cadete_oc\README.md" -Destination "." -Force

# Crear .gitignore
@'
# Archivos de backup con datos reales
*-prod-*.sql.gz
*-prod-*.sql
*.log

# Archivos temporales de PowerShell
*.tmp
*.temp

# Archivos de configuración con credenciales
config.local.*
secrets.*

# Directorios de trabajo temporal
temp/
tmp/
'@ | Out-File -FilePath ".gitignore" -Encoding UTF8

# Agregar archivos al repositorio
git add .

# Commit inicial
git commit -m "feat: Automatización MySQL backup y despliegue para OpenShift

- Scripts PowerShell para backup y restore de MySQL
- Documentación completa con ejemplos
- Soporte para entornos CERT, INTE y PROD
- Validación automática y limpieza de recursos
- Troubleshooting y comandos de verificación"

# Subir al repositorio
git push origin main

Write-Host "✓ Repositorio creado y archivos subidos exitosamente" -ForegroundColor Green
"@

Write-Host $commands

# Paso 3: Crear estructura adicional recomendada
Write-Host "`n3. Estructura adicional recomendada (opcional):" -ForegroundColor Yellow

$additionalStructure = @"
# Crear directorios adicionales en el repo
mkdir docs
mkdir templates
mkdir examples

# Crear archivos adicionales útiles
echo "# Documentación Técnica" > docs\technical.md
echo "# Templates OpenShift" > templates\README.md
echo "# Ejemplos de Uso" > examples\README.md

# Crear template de configuración
@'
# Configuración de entornos
# Copiar como config.local.ps1 y personalizar

`$Environments = @{
    "CERT" = @{
        Namespace = "wcdy-cert-frt"
        StorageClass = "apps-csi"
        ImagePullSecret = "quay-wcdy-pullsecret"
    }
    "INTE" = @{
        Namespace = "wcdy-inte-frt" 
        StorageClass = "apps-csi"
        ImagePullSecret = "quay-wcdy-pullsecret"
    }
    "PROD" = @{
        Namespace = "wcdy-prod-frt"
        StorageClass = "apps-csi"
        ImagePullSecret = "quay-wcdy-pullsecret"
    }
}
'@ | Out-File -FilePath "templates\config.template.ps1" -Encoding UTF8
"@

Write-Host $additionalStructure

Write-Host "`n=== Instrucciones Completas ===" -ForegroundColor Cyan
Write-Host "1. Ejecuta los comandos del Paso 2 después de crear el repo en GitHub"
Write-Host "2. Reemplaza 'TU_USUARIO' con tu nombre de usuario de GitHub"
Write-Host "3. El repositorio quedará listo para usar y compartir con el equipo"
Write-Host "4. Los archivos sensibles están excluidos en .gitignore"