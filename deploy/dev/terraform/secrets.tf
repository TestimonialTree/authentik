# Generate Authentik secret key
resource "random_password" "authentik_secret_key" {
  length  = 64
  special = true
}

# Secrets Manager Secrets
resource "aws_secretsmanager_secret" "authentik_secret_key" {
  name                    = "${var.project_name}/secret-key"
  description             = "Authentik secret key"
  recovery_window_in_days = 0
}

resource "aws_secretsmanager_secret_version" "authentik_secret_key" {
  secret_id     = aws_secretsmanager_secret.authentik_secret_key.id
  secret_string = jsonencode({
    key = random_password.authentik_secret_key.result
  })
}

resource "aws_secretsmanager_secret" "rds_password" {
  name                    = "${var.project_name}/rds-password"
  description             = "RDS PostgreSQL password"
  recovery_window_in_days = 0
}

resource "aws_secretsmanager_secret_version" "rds_password" {
  secret_id     = aws_secretsmanager_secret.rds_password.id
  secret_string = jsonencode({
    password = random_password.rds_password.result
  })
}

resource "aws_secretsmanager_secret" "rds_host" {
  name                    = "${var.project_name}/rds-host"
  description             = "RDS PostgreSQL host"
  recovery_window_in_days = 0
}

resource "aws_secretsmanager_secret_version" "rds_host" {
  secret_id     = aws_secretsmanager_secret.rds_host.id
  secret_string = jsonencode({
    host = aws_db_instance.postgres.endpoint
  })
}

resource "aws_secretsmanager_secret" "rds_user" {
  name                    = "${var.project_name}/rds-user"
  description             = "RDS PostgreSQL username"
  recovery_window_in_days = 0
}

resource "aws_secretsmanager_secret_version" "rds_user" {
  secret_id     = aws_secretsmanager_secret.rds_user.id
  secret_string = jsonencode({
    username = "authentik"
  })
}

resource "aws_secretsmanager_secret" "rds_database" {
  name                    = "${var.project_name}/rds-database"
  description             = "RDS PostgreSQL database name"
  recovery_window_in_days = 0
}

resource "aws_secretsmanager_secret_version" "rds_database" {
  secret_id     = aws_secretsmanager_secret.rds_database.id
  secret_string = jsonencode({
    database = "authentik_dev"
  })
}