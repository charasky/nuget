Param(
    [string]$AWSAccessKey,
    [string]$AWSSecretKey,
    [string]$AWSRegion,
    [string]$Domain,
    [string]$DomainOwner,
    [string]$EnableDebug
)

###############################################################################
# 1) Si las variables no vienen por parámetro, pedirlas al usuario
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
if (-not $EnableDebug) {
    $EnableDebug = Read-Host "¿Habilitar modo debug? (yes/no)"
}

if (-not $AWSRegion) {
    Write-Error "La región de AWS es obligatoria. Ejemplo: us-east-1"
    exit 1
}

###############################################################################
# 2) Definir carpeta y archivo donde guardaremos las credenciales
###############################################################################
$SharedCredentialsFolder = "D:\MisCredenciales"
$SharedCredentialsFile   = Join-Path $SharedCredentialsFolder "credentials"

# Creamos la carpeta si no existe
if (-not (Test-Path $SharedCredentialsFolder)) {
    Write-Host "Creando carpeta para credenciales en $SharedCredentialsFolder..."
    New-Item -ItemType Directory -Path $SharedCredentialsFolder | Out-Null
}

###############################################################################
# 3) Establecer la variable de entorno para que AWS CLI use este archivo
###############################################################################
$Env:AWS_SHARED_CREDENTIALS_FILE = $SharedCredentialsFile

Write-Host "Usando archivo de credenciales personalizado en: $SharedCredentialsFile"
Write-Host "Variable de entorno AWS_SHARED_CREDENTIALS_FILE = $Env:AWS_SHARED_CREDENTIALS_FILE"

###############################################################################
# 4) Crear/Configurar el perfil "temp-profile" usando 'aws configure set'
###############################################################################
$ProfileName = "temp-profile"

Write-Host "`nConfigurando el perfil '$ProfileName' en AWS CLI..."
aws configure set aws_access_key_id     $AWSAccessKey     --profile $ProfileName
aws configure set aws_secret_access_key $AWSSecretKey     --profile $ProfileName
aws configure set region                $AWSRegion        --profile $ProfileName

###############################################################################
# 5) Validar credenciales con sts get-caller-identity
###############################################################################
Write-Host "`nVerificando credenciales con sts get-caller-identity..."
try {
    $CallerIdentity = aws sts get-caller-identity --profile $ProfileName --output json | ConvertFrom-Json
    Write-Host "Credenciales válidas. Detalles:" -ForegroundColor Green
    Write-Host " - Cuenta: $($CallerIdentity.Account)" -ForegroundColor Green
    Write-Host " - Usuario ARN: $($CallerIdentity.Arn)" -ForegroundColor Green
} catch {
    Write-Error "Error: Las credenciales son inválidas o hay un problema de firma. Revisa Access Key, Secret Key y Región."
    exit 1
}

###############################################################################
# 6) Obtener token de CodeArtifact
###############################################################################
Write-Host "`nObteniendo el token de AWS CodeArtifact para el dominio '$Domain'..."
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

Write-Host "`nToken obtenido exitosamente: $Token" -ForegroundColor Green
Write-Host "`n¡Listo! Se configuró el perfil '$ProfileName' en el archivo '$SharedCredentialsFile' y obtuvimos el token de CodeArtifact."
