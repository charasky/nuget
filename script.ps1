param()

# 1) Solicitar credenciales y configuración al usuario
$AWSAccessKey  = Read-Host "Ingrese su AWS Access Key ID"
# ¡OJO! Esto pedirá la clave en texto plano:
$AWSSecretKey  = Read-Host "Ingrese su AWS Secret Access Key (texto plano, se mostrará en pantalla)"
$AWSRegion     = Read-Host "Ingrese su región de AWS (por ejemplo, us-east-1)"
$Domain        = Read-Host "Ingrese el nombre del dominio CodeArtifact (por ejemplo, nuget-domain)"
$DomainOwner   = Read-Host "Ingrese el ID de la cuenta AWS (Domain Owner)"
$EnableDebug   = Read-Host "¿Habilitar modo debug? (yes/no)"

# 2) Validar que la región exista
if (-not $AWSRegion) {
    Write-Error "La región de AWS es obligatoria. Ejemplo: us-east-1"
    exit 1
}

# 3) Definir variables para el perfil
$ProfileName = "temp-profile"
$CredentialFilePath = "$HOME/.aws/credentials"

# 4) Crear la carpeta .aws si no existe
if (-not (Test-Path "$HOME/.aws")) {
    New-Item -ItemType Directory -Path "$HOME/.aws" | Out-Null
}

Write-Host "=== Eliminando el archivo de credenciales para empezar limpio ==="
if (Test-Path $CredentialFilePath) {
    Remove-Item $CredentialFilePath -Force
}

Write-Host "Configurando un perfil temporal en AWS CLI..." -ForegroundColor Cyan

# 5) Crear contenido para el perfil
$profileContent = @"
[$ProfileName]
aws_access_key_id = $AWSAccessKey
aws_secret_access_key = $AWSSecretKey
region = $AWSRegion
"@

# 6) Escribir el archivo con codificación controlada (UTF-8 sin BOM)
Set-Content -LiteralPath $CredentialFilePath -Value $profileContent -Encoding utf8NoBOM

Write-Host "DEBUG: Perfil temporal configurado -> $ProfileName" -ForegroundColor Yellow
Write-Host "DEBUG: Archivo de configuración -> $CredentialFilePath" -ForegroundColor Yellow

# 7) Mostrar el contenido del archivo final
Write-Host "`nContenido del archivo de credenciales recién escrito:" -ForegroundColor DarkCyan
Get-Content $CredentialFilePath | ForEach-Object { "  $_" }
Write-Host "`n==================================="

# 8) Verificar credenciales con sts get-caller-identity
Write-Host "Verificando las credenciales configuradas en el perfil temporal..." -ForegroundColor Cyan
try {
    $CallerIdentity = aws sts get-caller-identity --profile $ProfileName --output json | ConvertFrom-Json
    Write-Host "Credenciales válidas. Detalles:" -ForegroundColor Green
    Write-Host " - Cuenta: $($CallerIdentity.Account)" -ForegroundColor Green
    Write-Host " - Usuario ARN: $($CallerIdentity.Arn)" -ForegroundColor Green
} catch {
    Write-Error "Las credenciales configuradas son inválidas o hay un problema con la firma. Verifica la Access Key, Secret Key y Región."
    exit 1
}

# 9) Obtener el token de CodeArtifact
Write-Host "Obteniendo el token de AWS CodeArtifact..." -ForegroundColor Cyan
if ($EnableDebug -eq "yes") {
    Write-Host "DEBUG: aws codeartifact get-authorization-token --profile $ProfileName --domain $Domain --domain-owner $DomainOwner --query authorizationToken --output text"
}

try {
    $Token = aws codeartifact get-authorization-token `
        --profile $ProfileName `
        --domain $Domain `
        --domain-owner $DomainOwner `
        --query authorizationToken `
        --output text
} catch {
    Write-Error "Error al obtener el token de AWS CodeArtifact: $_"
    exit 1
}

if (!$Token) {
    Write-Error "No se pudo obtener el token de AWS CodeArtifact. El token está vacío."
    exit 1
}

Write-Host "Token obtenido exitosamente: $Token" -ForegroundColor Green
