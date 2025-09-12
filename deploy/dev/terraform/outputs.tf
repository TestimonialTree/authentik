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