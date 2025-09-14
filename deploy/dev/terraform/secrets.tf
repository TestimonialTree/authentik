// Lookup unified JSON secret created out-of-band
data "aws_secretsmanager_secret" "app_config" {
  name = "${var.project_name}/app-config"
}
