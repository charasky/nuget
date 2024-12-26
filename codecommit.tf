variable "users" {
  description = "Lista de usuarios"
  type        = list(string)
  default     = ["user1", "user2", "user3"]
}

variable "repository_name" {
  description = "Nombre del repositorio de CodeCommit"
  type        = string
  default     = "mi-repositorio"
}

variable "domain_name" {
  description = "Nombre del dominio CodeArtifact"
  type        = string
  default     = "mi-dominio"
}

variable "repository_codeartifact_name" {
  description = "Nombre del repositorio CodeArtifact"
  type        = string
  default     = "mi-repositorio-nuget"
}

provider "aws" {
  profile = "yourprofile-dev" # Reemplaza con tu perfil
  region  = "us-east-x"       # Reemplaza con tu región
}

data "aws_caller_identity" "current" {}

# Recursos CodeCommit
resource "aws_codecommit_repository" "repo" {
  repository_name = var.repository_name
  description     = "Repositorio para proyectos NuGet"
}

resource "aws_iam_policy" "codecommit_policy" {
  name = "CodeCommitPolicy"
  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Action = [
          "codecommit:GitPull",
          "codecommit:GitPush",
          "codecommit:Get*",
          "codecommit:List*",
        ],
        Effect   = "Allow",
        Resource = aws_codecommit_repository.repo.arn,
      },
    ],
  })
}

# Recursos CodeArtifact
resource "aws_codeartifact_domain" "domain" {
  domain = var.domain_name
}

resource "aws_codeartifact_repository" "repository" {
  domain                 = aws_codeartifact_domain.domain.domain
  repository             = var.repository_codeartifact_name
  external_connections {
    package_format = "nuget"
  }
}

resource "aws_iam_policy" "codeartifact_policy" {
  name = "CodeArtifactPolicy"
  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Action = [
          "codeartifact:GetAuthorizationToken",
          "codeartifact:GetRepositoryEndpoint",
          "codeartifact:PublishPackageVersion",
          "codeartifact:DescribePackageVersion",
          "codeartifact:WriteFromRepository",
          "codeartifact:ListPackageVersions",
          "codeartifact:ReadFromRepository",
          "sts:GetServiceBearerToken",
        ],
        Effect   = "Allow",
        Resource = "*", # Limitar esto en un entorno real
      },
    ],
  })
}

# Usuarios y adjuntos de políticas (para ambos CodeCommit y CodeArtifact)
resource "aws_iam_user" "users" {
  for_each = toset(var.users)
  name     = each.key
}

resource "aws_iam_user_policy_attachment" "codecommit_attachment" {
  for_each = toset(var.users)
  user       = aws_iam_user.users[each.key].name
  policy_arn = aws_iam_policy.codecommit_policy.arn
}

resource "aws_iam_user_policy_attachment" "codeartifact_attachment" {
  for_each = toset(var.users)
  user       = aws_iam_user.users[each.key].name
  policy_arn = aws_iam_policy.codeartifact_policy.arn
}

# Outputs (solo nombres de usuario por seguridad)
output "codecommit_repository_url" {
  value = aws_codecommit_repository.repo.clone_url_http
}

output "codeartifact_repository_endpoint" {
  value = aws_codeartifact_repository.repository.repository_endpoint
}

output "created_users" {
  value = aws_iam_user.users.*.name
}
