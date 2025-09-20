# VPC outputs
output "vpc_id" {
  description = "ID of the VPC"
  value       = aws_vpc.main.id
}

output "vpc_cidr_block" {
  description = "CIDR block of the VPC"
  value       = aws_vpc.main.cidr_block
}

output "public_subnet_ids" {
  description = "IDs of the public subnets"
  value       = aws_subnet.public[*].id
}

output "private_subnet_ids" {
  description = "IDs of the private subnets"
  value       = aws_subnet.private[*].id
}

# Load Balancer outputs
output "alb_dns_name" {
  description = "DNS name of the Application Load Balancer"
  value       = aws_lb.main.dns_name
}

output "alb_zone_id" {
  description = "Zone ID of the Application Load Balancer"
  value       = aws_lb.main.zone_id
}

output "alb_arn" {
  description = "ARN of the Application Load Balancer"
  value       = aws_lb.main.arn
}

# ECS outputs
output "ecs_cluster_id" {
  description = "ID of the ECS cluster"
  value       = aws_ecs_cluster.main.id
}

output "ecs_cluster_name" {
  description = "Name of the ECS cluster"
  value       = aws_ecs_cluster.main.name
}

output "ecs_service_name" {
  description = "Name of the ECS service"
  value       = aws_ecs_service.authentik_server.name
}

output "ecs_task_definition_arn" {
  description = "ARN of the ECS task definition"
  value       = aws_ecs_task_definition.authentik_server.arn
}

# Database outputs
output "rds_endpoint" {
  description = "RDS instance endpoint"
  value       = aws_db_instance.postgres.endpoint
}

output "rds_port" {
  description = "RDS instance port"
  value       = aws_db_instance.postgres.port
}

output "rds_db_name" {
  description = "RDS database name"
  value       = aws_db_instance.postgres.db_name
}

# Redis outputs
output "redis_endpoint" {
  description = "Redis cluster endpoint"
  value       = aws_elasticache_cluster.redis.cache_nodes[0].address
}

output "redis_port" {
  description = "Redis cluster port"
  value       = aws_elasticache_cluster.redis.cache_nodes[0].port
}

# ECR outputs
output "ecr_repository_url" {
  description = "URL of the ECR repository"
  value       = aws_ecr_repository.authentik.repository_url
}

output "ecr_repository_arn" {
  description = "ARN of the ECR repository"
  value       = aws_ecr_repository.authentik.arn
}

# S3 outputs
output "s3_media_bucket_name" {
  description = "Name of the S3 media bucket"
  value       = aws_s3_bucket.media.bucket
}

output "s3_media_bucket_arn" {
  description = "ARN of the S3 media bucket"
  value       = aws_s3_bucket.media.arn
}

# KMS outputs
output "kms_key_id" {
  description = "ID of the KMS key"
  value       = aws_kms_key.authentik.key_id
}

output "kms_key_arn" {
  description = "ARN of the KMS key"
  value       = aws_kms_key.authentik.arn
}

# Security Group outputs
output "alb_security_group_id" {
  description = "ID of the ALB security group"
  value       = aws_security_group.alb.id
}

output "ecs_security_group_id" {
  description = "ID of the ECS security group"
  value       = aws_security_group.ecs.id
}

output "rds_security_group_id" {
  description = "ID of the RDS security group"
  value       = aws_security_group.rds.id
}

output "redis_security_group_id" {
  description = "ID of the Redis security group"
  value       = aws_security_group.redis.id
}

# IAM outputs
output "ecs_task_role_arn" {
  description = "ARN of the ECS task role"
  value       = aws_iam_role.ecs_task.arn
}

output "ecs_execution_role_arn" {
  description = "ARN of the ECS execution role"
  value       = aws_iam_role.ecs_execution.arn
}

# Secrets Manager outputs
output "database_secret_arn" {
  description = "ARN of the database secret"
  value       = aws_secretsmanager_secret.database.arn
}

output "authentik_secret_arn" {
  description = "ARN of the Authentik secret"
  value       = aws_secretsmanager_secret.authentik.arn
}

# CloudWatch outputs
output "cloudwatch_log_group_name" {
  description = "Name of the CloudWatch log group"
  value       = aws_cloudwatch_log_group.authentik.name
}

# Connection information
output "application_url" {
  description = "URL to access the Authentik application"
  value       = "https://${var.domain_name}"
}

output "health_check_url" {
  description = "URL for application health check"
  value       = "https://${var.domain_name}/-/health/live/"
}

# Infrastructure summary
output "infrastructure_summary" {
  description = "Summary of deployed infrastructure"
  value = {
    environment = var.environment
    region      = var.aws_region
    vpc_cidr    = var.vpc_cidr
    domain      = var.domain_name

    compute = {
      ecs_cluster    = aws_ecs_cluster.main.name
      task_cpu       = var.ecs_task_cpu
      task_memory    = var.ecs_task_memory
      desired_count  = var.ecs_desired_count
    }

    database = {
      engine         = aws_db_instance.postgres.engine
      engine_version = aws_db_instance.postgres.engine_version
      instance_class = aws_db_instance.postgres.instance_class
      allocated_storage = aws_db_instance.postgres.allocated_storage
      multi_az       = aws_db_instance.postgres.multi_az
    }

    cache = {
      engine         = aws_elasticache_cluster.redis.engine
      engine_version = aws_elasticache_cluster.redis.engine_version
      node_type      = aws_elasticache_cluster.redis.node_type
      num_cache_nodes = aws_elasticache_cluster.redis.num_cache_nodes
    }
  }
}