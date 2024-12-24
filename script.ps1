# Solicitar credenciales de AWS al usuario
$AWSAccessKey = Read-Host "Ingrese su AWS Access Key ID"
$AWSSecretKey = Read-Host "Ingrese su AWS Secret Access Key" -AsSecureString
$AWSRegion = Read-Host "Ingrese su región de AWS (por ejemplo, us-east-1)"
$Domain = Read-Host "Ingrese el nombre del dominio CodeArtifact (por ejemplo, nuget-domain)"
$DomainOwner = Read-Host "Ingrese el ID de la cuenta AWS (Domain Owner)"

# Convertir la AWS Secret Key a texto para usarla como variable de entorno
$PlainSecretKey = [Runtime.InteropServices.Marshal]::PtrToStringAuto(
    [Runtime.InteropServices.Marshal]::SecureStringToBSTR($AWSSecretKey)
)

# Configurar variables principales
$NuGetSourceName = "$Domain/nuget-repo"
$NuGetSourceUrl = "https://$Domain-$DomainOwner.d.codeartifact.$AWSRegion.amazonaws.com/nuget/nuget-repo/v3/index.json"

# Configurar credenciales de AWS usando variables de entorno
Write-Host "Configurando las credenciales de AWS..." -ForegroundColor Cyan
$env:AWS_ACCESS_KEY_ID = $AWSAccessKey
$env:AWS_SECRET_ACCESS_KEY = $PlainSecretKey
$env:AWS_REGION = $AWSRegion

# Obtener el token de CodeArtifact
Write-Host "Obteniendo el token de AWS CodeArtifact..." -ForegroundColor Cyan
try {
    $Token = aws codeartifact get-authorization-token `
        --domain $Domain `
        --domain-owner $DomainOwner `
        --query authorizationToken `
        --output text
} catch {
    Write-Host "Error al obtener el token de CodeArtifact:" -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Yellow
    exit 1
}

# Validar el token
if (!$Token) {
    Write-Error "No se pudo obtener el token de AWS CodeArtifact. El token está vacío."
    exit 1
}

Write-Host "Token obtenido exitosamente." -ForegroundColor Green

# Verificar si la fuente de NuGet ya existe
Write-Host "Verificando si la fuente de NuGet ya está configurada..." -ForegroundColor Cyan
$ExistingSource = nuget sources list | Where-Object { $_ -match $NuGetSourceName }

if ($ExistingSource) {
    Write-Host "La fuente de NuGet ya está configurada. Actualizando el token..." -ForegroundColor Yellow
    
    # Actualizar la fuente con el nuevo token
    try {
        nuget sources update -Name $NuGetSourceName `
            -Source $NuGetSourceUrl `
            -Username "aws" `
            -Password $Token `
            -StorePasswordInClearText
    } catch {
        Write-Host "Error al actualizar la fuente de NuGet:" -ForegroundColor Red
        Write-Host $_.Exception.Message -ForegroundColor Yellow
        exit 1
    }
} else {
    Write-Host "La fuente de NuGet no está configurada. Agregándola ahora..." -ForegroundColor Cyan
    
    try {
        # Agregar la nueva fuente con el token
        nuget sources add -Name $NuGetSourceName `
            -Source $NuGetSourceUrl `
            -Username "aws" `
            -Password $Token `
            -StorePasswordInClearText
    } catch {
        Write-Host "Error al configurar la fuente de NuGet:" -ForegroundColor Red
        Write-Host $_.Exception.Message -ForegroundColor Yellow
        exit 1
    }
}

Write-Host "Fuente de NuGet configurada correctamente." -ForegroundColor Green
