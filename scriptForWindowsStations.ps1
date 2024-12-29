Param(
    [string]$EncryptionKey, # Clave para encriptar/desencriptar
    [string]$ConfigFilePath = "C:\MisCredenciales\aws_config.json", # Ruta del archivo de configuración
    [string]$EnableSchedule = "no" # Programar la renovación automática del token
)

###############################################################################
# Funciones auxiliares
###############################################################################
function Encrypt-Data {
    param (
        [string]$Data,
        [string]$Key
    )
    $Bytes   = [System.Text.Encoding]::UTF8.GetBytes($Data)
    $KeyBytes = [System.Text.Encoding]::UTF8.GetBytes($Key.PadRight(32).Substring(0, 32))
    $AES     = [System.Security.Cryptography.Aes]::Create()
    $AES.Key = $KeyBytes
    $AES.IV  = $KeyBytes[0..15]
    $Encryptor = $AES.CreateEncryptor()
    [System.Convert]::ToBase64String($Encryptor.TransformFinalBlock($Bytes, 0, $Bytes.Length))
}

function Decrypt-Data {
    param (
        [string]$Data,
        [string]$Key
    )
    $EncryptedBytes = [System.Convert]::FromBase64String($Data)
    $KeyBytes       = [System.Text.Encoding]::UTF8.GetBytes($Key.PadRight(32).Substring(0, 32))
    $AES            = [System.Security.Cryptography.Aes]::Create()
    $AES.Key        = $KeyBytes
    $AES.IV         = $KeyBytes[0..15]
    $Decryptor      = $AES.CreateDecryptor()
    [System.Text.Encoding]::UTF8.GetString($Decryptor.TransformFinalBlock($EncryptedBytes, 0, $EncryptedBytes.Length))
}

function Save-Config {
    param (
        [hashtable]$Config,
        [string]$FilePath,
        [string]$Key
    )
    $JsonData      = $Config | ConvertTo-Json -Depth 10
    $EncryptedData = Encrypt-Data -Data $JsonData -Key $Key
    Set-Content -Path $FilePath -Value $EncryptedData -Force
}

function Load-Config {
    param (
        [string]$FilePath,
        [string]$Key
    )
    if (-not (Test-Path $FilePath)) {
        throw "El archivo de configuración no existe en $FilePath."
    }
    $EncryptedData = Get-Content -Path $FilePath
    $JsonData      = Decrypt-Data -Data $EncryptedData -Key $Key
    ConvertFrom-Json $JsonData # Elimina -AsHashtable para compatibilidad con versiones antiguas
}

###############################################################################
# Variables de configuración
###############################################################################
$Config = @{}
if (-not (Test-Path $ConfigFilePath)) {
    Write-Host "Archivo de configuración no encontrado. Solicitando valores iniciales..."
    $Config["AWSAccessKey"]  = Read-Host "Ingrese su AWS Access Key ID"
    $Config["AWSSecretKey"]  = Read-Host "Ingrese su AWS Secret Access Key (se mostrará en pantalla)"
    $Config["AWSRegion"]     = Read-Host "Ingrese su región de AWS (por ejemplo, us-east-1)"
    $Config["Domain"]        = Read-Host "Ingrese el nombre del dominio CodeArtifact (por ejemplo, nuget-domain)"
    $Config["DomainOwner"]   = Read-Host "Ingrese el ID de la cuenta AWS (Domain Owner)"
    Save-Config -Config $Config -FilePath $ConfigFilePath -Key $EncryptionKey
    Write-Host "Archivo de configuración creado y guardado en $ConfigFilePath"
} else {
    Write-Host "Cargando configuración desde $ConfigFilePath..."
    $Config = Load-Config -FilePath $ConfigFilePath -Key $EncryptionKey
}

###############################################################################
# Configuración del perfil temporal
###############################################################################
$ProfileName             = "temp-profile"
$SharedCredentialsFolder = "C:\MisCredenciales"
$SharedCredentialsFile   = Join-Path $SharedCredentialsFolder "credentials"

if (-not (Test-Path $SharedCredentialsFolder)) {
    Write-Host "Creando carpeta para credenciales en $SharedCredentialsFolder..."
    New-Item -ItemType Directory -Path $SharedCredentialsFolder | Out-Null
}
$Env:AWS_SHARED_CREDENTIALS_FILE = $SharedCredentialsFile

aws configure set aws_access_key_id     $Config.AWSAccessKey     --profile $ProfileName
aws configure set aws_secret_access_key $Config.AWSSecretKey     --profile $ProfileName
aws configure set region                $Config.AWSRegion        --profile $ProfileName

###############################################################################
# Renovar el token
###############################################################################
$Token = aws codeartifact get-authorization-token `
    --profile $ProfileName `
    --domain $Config.Domain `
    --domain-owner $Config.DomainOwner `
    --query authorizationToken `
    --output text

if ($Token) {
    Write-Host "Token renovado exitosamente."
} else {
    Write-Error "Error al renovar el token."
    exit 1
}

###############################################################################
# Configurar NuGet
###############################################################################
$NuGetSourceName = "$($Config.Domain)/nuget-repo"
$NuGetSourceUrl  = "https://$($Config.Domain)-$($Config.DomainOwner.Trim()).d.codeartifact.$($Config.AWSRegion.Trim()).amazonaws.com/nuget/nuget-repo/v3/index.json"

if (nuget sources list | Select-String -Pattern $NuGetSourceName) {
    nuget sources remove -Name $NuGetSourceName
}
nuget sources add -Name $NuGetSourceName `
    -Source $NuGetSourceUrl `
    -Username "aws" `
    -Password $Token `
    -StorePasswordInClearText

Write-Host "Fuente de NuGet configurada exitosamente."

###############################################################################
# Programar la ejecución cada 12 horas
###############################################################################
if ($EnableSchedule -eq "yes") {
    $Action = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-File `"$PSCommandPath`" -EncryptionKey $EncryptionKey"
    $Trigger = New-ScheduledTaskTrigger -Daily -At (Get-Date).AddHours(12)
    Register-ScheduledTask -TaskName "RenovarTokenCodeArtifact" -Action $Action -Trigger $Trigger -Force
    Write-Host "Tarea programada creada para renovar el token cada 12 horas."
}
