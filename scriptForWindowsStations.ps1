Param(
    [string]$AWSAccessKey,
    [string]$AWSSecretKey,
    [string]$AWSRegion,
    [string]$Domain,
    [string]$DomainOwner,
    [string]$EnableDebug = "no" # Valor por defecto
)
 
###############################################################################
# 1) Validar entradas y pedir datos faltantes
###############################################################################
if (-not $AWSAccessKey) {
    $AWSAccessKey = Read-Host "Ingrese su AWS Access Key ID"
}
if (-not $AWSSecretKey) {
    $AWSSecretKey = Read-Host "Ingrese su AWS Secret Access Key (se mostrará en pantalla)"
}
if (-not $AWSRegion) {
    $AWSRegion = Read-Host "Ingrese su región de AWS (por ejemplo, us-east-1)"
}
if (-not $Domain) {
    $Domain = Read-Host "Ingrese el nombre del dominio CodeArtifact (por ejemplo, nuget-domain)"
}
if (-not $DomainOwner) {
    $DomainOwner = Read-Host "Ingrese el ID de la cuenta AWS (Domain Owner)"
}
 
# Validar que no queden variables vacías
if (-not $AWSRegion) {
    Write-Error "La región de AWS es obligatoria (ejemplo: us-east-1)."
    exit 1
}
 
###############################################################################
# 2) Definir carpeta y archivo de credenciales personalizado
###############################################################################
$SharedCredentialsFolder = "D:\MisCredenciales"
$SharedCredentialsFile   = Join-Path $SharedCredentialsFolder "credentials"
 
# Crear carpeta si no existe
if (-not (Test-Path $SharedCredentialsFolder)) {
    Write-Host "Creando carpeta para credenciales en $SharedCredentialsFolder..."
    New-Item -ItemType Directory -Path $SharedCredentialsFolder | Out-Null
}
 
# Establecer la variable de entorno para que AWS CLI use este archivo
$Env:AWS_SHARED_CREDENTIALS_FILE = $SharedCredentialsFile
Write-Host "`nUsando archivo de credenciales personalizado en: $SharedCredentialsFile"
Write-Host "AWS_SHARED_CREDENTIALS_FILE = $Env:AWS_SHARED_CREDENTIALS_FILE"
 
###############################################################################
# 3) Configurar el perfil "temp-profile" en AWS CLI
###############################################################################
$ProfileName = "temp-profile"
Write-Host "`n==> Configurando perfil '$ProfileName'..."
try {
    aws configure set aws_access_key_id     $AWSAccessKey     --profile $ProfileName
    aws configure set aws_secret_access_key $AWSSecretKey     --profile $ProfileName
    aws configure set region                $AWSRegion        --profile $ProfileName
} catch {
    Write-Error "Error al configurar el perfil '$ProfileName': $_"
    exit 1
}
 
###############################################################################
# 4) Validar credenciales
###############################################################################
Write-Host "`nVerificando credenciales con perfil '$ProfileName'..."
try {
    $CallerIdentity = aws sts get-caller-identity --profile $ProfileName --output json | ConvertFrom-Json
    Write-Host "Credenciales válidas. Detalles:"
    Write-Host " - Cuenta: $($CallerIdentity.Account)"
    Write-Host " - Usuario ARN: $($CallerIdentity.Arn)"
} catch {
    Write-Error "Error: credenciales inválidas o problema de firma. Verifica Access Key, Secret Key y Región."
    exit 1
}
 
###############################################################################
# 5) Obtener token de CodeArtifact
###############################################################################
Write-Host "`nObteniendo token de CodeArtifact para el dominio '$Domain'..."
try {
    $Token = aws codeartifact get-authorization-token `
        --profile $ProfileName `
        --domain $Domain `
        --domain-owner $DomainOwner `
        --query authorizationToken `
        --output text
    if (!$Token) {
        throw "El token está vacío."
    }
    Write-Host "Token obtenido exitosamente."
} catch {
    Write-Error "Error al obtener el token de CodeArtifact: $_"
    exit 1
}
 
###############################################################################
# 6) Configurar NuGet con el token
###############################################################################
Write-Host "`n==> Configurando la fuente de NuGet..."
$NuGetSourceName = "$Domain/nuget-repo"
$NuGetSourceUrl  = "https://$($Domain)-$($DomainOwner).d.codeartifact.$($AWSRegion).amazonaws.com/nuget/nuget-repo/v3/index.json"
 
if ($EnableDebug -eq "yes") {
    Write-Host "DEBUG: NuGetSourceName = $NuGetSourceName"
    Write-Host "DEBUG: NuGetSourceUrl = $NuGetSourceUrl"
}
 
try {
    # Eliminar fuente previa si existe
    if (nuget sources list | Select-String -Pattern $NuGetSourceName) {
        Write-Host "Eliminando fuente NuGet existente..."
        nuget sources remove -Name $NuGetSourceName
    }
 
    # Agregar nueva fuente con token
    nuget sources add -Name $NuGetSourceName `
        -Source $NuGetSourceUrl `
        -Username "aws" `
        -Password $Token `
        -StorePasswordInClearText
    Write-Host "Fuente de NuGet '$NuGetSourceName' configurada correctamente."
} catch {
    Write-Error "Error al configurar la fuente de NuGet: $_"
    exit 1
}
 
###############################################################################
# FIN
###############################################################################
Write-Host "`n¡Listo! Configuración completada exitosamente." -ForegroundColor Cyan
