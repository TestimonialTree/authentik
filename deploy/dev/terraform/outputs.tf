output "vpc_id" {
  description = "VPC ID"
  value       = data.aws_vpc.existing.id
}

output "private_subnet_ids" {
  description = "Private subnet IDs"
  value       = [data.aws_subnet.private_1.id, data.aws_subnet.private_2.id]
}

output "ecs_security_group_id" {
  description = "ECS Security Group ID"
  value       = aws_security_group.ecs.id
}

output "ecs_cluster_name" {
  description = "ECS Cluster Name"
  value       = aws_ecs_cluster.main.name
}

output "target_group_arn" {
  description = "Target Group ARN"
  value       = aws_lb_target_group.main.arn
}

output "ecr_repository_url" {
  description = "ECR Repository URL"
  value       = aws_ecr_repository.main.repository_url
}

output "load_balancer_dns" {
  description = "Application Load Balancer DNS Name"
  value       = aws_lb.main.dns_name
}

output "rds_endpoint" {
  description = "RDS PostgreSQL Endpoint"
  value       = aws_db_instance.postgres.endpoint
}

output "rds_password" {
  description = "RDS PostgreSQL Password (sensitive)"
  value       = random_password.rds_password.result
  sensitive   = true
}

output "authentik_secret_key" {
  description = "Authentik Secret Key (sensitive)"
  value       = random_password.authentik_secret_key.result
  sensitive   = true
}

# CodePipeline outputs
output "codepipeline_name" {
  description = "Name of the CodePipeline"
  value       = aws_codepipeline.authentik_pipeline.name
}

output "codebuild_project_name" {
  description = "Name of the CodeBuild project"
  value       = aws_codebuild_project.authentik_build.name
}

output "source_bucket_name" {
  description = "Name of the S3 bucket for source artifacts"
  value       = aws_s3_bucket.source_artifacts.bucket
}

output "github_secret_arn" {
  description = "ARN of the GitHub token secret"
  value       = aws_secretsmanager_secret.github_token.arn
}

# SSL Certificate and DNS configuration
output "ssl_certificate_arn" {
  description = "ARN of the SSL certificate (needs manual DNS validation)"
  value       = aws_acm_certificate.main.arn
}

output "dns_configuration_notes" {
  description = "Manual DNS configuration required"
  value = <<EOF
MANUAL DNS CONFIGURATION REQUIRED:

1. SSL Certificate Validation:
   - Go to AWS Certificate Manager console
   - Find certificate: ${aws_acm_certificate.main.arn}
   - Add the CNAME validation records to your DNS (managed in different account)

2. Main DNS Record:
   - Create an A record for: ${var.domain_name}
   - Point to ALB DNS name: ${aws_lb.main.dns_name}
   - This should be done in your main DNS management account
EOF
}