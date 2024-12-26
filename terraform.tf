variable "users" {
  description = "Lista de usuarios para CodeArtifact"
  type        = list(string)
  default     = ["user1", "user2", "user3"] # Define los nombres de los usuarios aquí
}
 
 
provider "aws" {
  profile = "yourprofile-dev"
  region  = "us-east-x"
}
 
# Obtener información de la cuenta AWS actual
data "aws_caller_identity" "current" {}
 
# Crear una clave KMS para cifrar secretos
resource "aws_kms_key" "codeartifact_key" {
  description               = "Clave KMS para cifrar las credenciales de CodeArtifact"
  key_usage                 = "ENCRYPT_DECRYPT"
  customer_master_key_spec  = "SYMMETRIC_DEFAULT"
 
  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Sid       = "Enable IAM User Permissions",
        Effect    = "Allow",
        Principal = {
          AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"
        },
        Action    = "kms:*",
        Resource  = "*"
      }
    ]
  })
}
 
# Crear una política IAM para publicar paquetes en CodeArtifact
resource "aws_iam_policy" "codeartifact_publish_policy" {
  name        = "CodeArtifactPublishPolicy"
  description = "Permisos para publicar nuevas versiones de paquetes en CodeArtifact"
 
  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Sid    = "AllowPublishPackageVersion",
        Effect = "Allow",
        Action = [
          "codeartifact:GetAuthorizationToken",
          "codeartifact:GetRepositoryEndpoint",
          "codeartifact:PublishPackageVersion",
          "codeartifact:DescribePackageVersion",
          "codeartifact:WriteFromRepository",
          "codeartifact:ListPackageVersions",
          "codeartifact:ReadFromRepository",
          #Accion requerida
          "sts:GetServiceBearerToken"
        ],
        Resource = "*"
      }
    ]
  })
}
 
# Crear usuarios dinámicamente
resource "aws_iam_user" "codeartifact_users" {
  for_each = toset(var.users)
  name     = each.key
}
 
# Adjuntar políticas dinámicamente
resource "aws_iam_user_policy_attachment" "attach_codeartifact_policy" {
  for_each  = toset(var.users)
  user      = aws_iam_user.codeartifact_users[each.key].name
  policy_arn = aws_iam_policy.codeartifact_publish_policy.arn
}
 
# Crear credenciales para cada usuario
resource "aws_iam_access_key" "codeartifact_user_keys" {
  for_each = toset(var.users)
  user     = aws_iam_user.codeartifact_users[each.key].name
}
 
# Crear secretos para cada usuario
resource "aws_secretsmanager_secret" "codeartifact_secrets" {
  for_each    = toset(var.users)
  name        = "codeartifact/credentials/${each.key}"
  description = "Credenciales para CodeArtifact (Access Key y Secret Key) para ${each.key}"
  kms_key_id  = aws_kms_key.codeartifact_key.arn
}
 
resource "aws_secretsmanager_secret_version" "codeartifact_secret_versions" {
  for_each     = toset(var.users)
  secret_id    = aws_secretsmanager_secret.codeartifact_secrets[each.key].id
  secret_string = jsonencode({
    AccessKeyId     = aws_iam_access_key.codeartifact_user_keys[each.key].id,
    SecretAccessKey = aws_iam_access_key.codeartifact_user_keys[each.key].secret
  })
}
 
# Outputs dinámicos
output "user_credentials" {
  description = "Credenciales para cada usuario de CodeArtifact"
  value = {
    for key, value in aws_iam_access_key.codeartifact_user_keys :
    key => {
      access_key_id     = value.id
      secret_access_key = value.secret
    }
  }
  sensitive = true
}
 
