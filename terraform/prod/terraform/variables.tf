# Environment configuration
variable "environment" {
  description = "Environment name (e.g., prod, staging)"
  type        = string
  default     = "prod"
}

variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

# Network configuration
variable "vpc_cidr" {
  description = "CIDR block for VPC"
  type        = string
  default     = "10.1.0.0/16"
}

# Domain and SSL
variable "domain_name" {
  description = "Domain name for Authentik (e.g., auth.testimonialtree.com)"
  type        = string
}

variable "certificate_arn" {
  description = "ACM certificate ARN for HTTPS"
  type        = string
}

# Database configuration
variable "db_instance_class" {
  description = "RDS instance class"
  type        = string
  default     = "db.t3.small"
}

variable "db_engine_version" {
  description = "PostgreSQL engine version"
  type        = string
  default     = "15.7"
}

variable "db_allocated_storage" {
  description = "Allocated storage for RDS (GB)"
  type        = number
  default     = 20
}

variable "db_max_allocated_storage" {
  description = "Maximum allocated storage for RDS auto-scaling (GB)"
  type        = number
  default     = 100
}

variable "db_backup_retention_period" {
  description = "Database backup retention period (days)"
  type        = number
  default     = 7
}

variable "db_backup_window" {
  description = "Database backup window"
  type        = string
  default     = "03:00-04:00"
}

variable "db_maintenance_window" {
  description = "Database maintenance window"
  type        = string
  default     = "Sun:04:00-Sun:05:00"
}

# Redis configuration
variable "redis_node_type" {
  description = "ElastiCache Redis node type"
  type        = string
  default     = "cache.t3.micro"
}

variable "redis_engine_version" {
  description = "Redis engine version"
  type        = string
  default     = "7.0"
}

variable "redis_parameter_group_name" {
  description = "Redis parameter group name"
  type        = string
  default     = "default.redis7"
}

# ECS configuration
variable "ecs_task_cpu" {
  description = "CPU units for ECS tasks"
  type        = number
  default     = 512
}

variable "ecs_task_memory" {
  description = "Memory (MB) for ECS tasks"
  type        = number
  default     = 1024
}

variable "ecs_desired_count" {
  description = "Desired number of ECS tasks"
  type        = number
  default     = 2
}

variable "container_image" {
  description = "Docker image for Authentik (will be overridden by CI/CD)"
  type        = string
  default     = "ghcr.io/goauthentik/server:2024.8.3"
}

# Application configuration
variable "authentik_secret_key" {
  description = "Authentik secret key (sensitive)"
  type        = string
  sensitive   = true
}

variable "authentik_error_reporting" {
  description = "Enable error reporting"
  type        = bool
  default     = true
}

variable "authentik_log_level" {
  description = "Log level for Authentik"
  type        = string
  default     = "info"
  validation {
    condition     = contains(["debug", "info", "warning", "error"], var.authentik_log_level)
    error_message = "Log level must be one of: debug, info, warning, error."
  }
}

# Monitoring configuration
variable "cloudwatch_log_retention_days" {
  description = "CloudWatch log retention period (days)"
  type        = number
  default     = 14
}

variable "enable_detailed_monitoring" {
  description = "Enable detailed CloudWatch monitoring"
  type        = bool
  default     = true
}

# Notification configuration
variable "notification_email" {
  description = "Email address for alerts and notifications"
  type        = string
  default     = ""
}

# Security configuration
variable "allowed_cidr_blocks" {
  description = "CIDR blocks allowed to access ALB"
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "enable_deletion_protection" {
  description = "Enable deletion protection for critical resources"
  type        = bool
  default     = true
}

# Backup configuration
variable "enable_automated_backups" {
  description = "Enable automated database backups"
  type        = bool
  default     = true
}

# Cost optimization
variable "enable_nat_instance" {
  description = "Use NAT instance instead of NAT Gateway for cost savings"
  type        = bool
  default     = false
}

# Feature flags for future upgrades
variable "enable_auto_scaling" {
  description = "Enable ECS auto-scaling (upgrade feature)"
  type        = bool
  default     = false
}

variable "enable_cloudfront" {
  description = "Enable CloudFront CDN (upgrade feature)"
  type        = bool
  default     = false
}

variable "enable_waf" {
  description = "Enable WAF protection (upgrade feature)"
  type        = bool
  default     = false
}

variable "enable_read_replica" {
  description = "Enable RDS read replica (upgrade feature)"
  type        = bool
  default     = false
}

variable "enable_redis_cluster" {
  description = "Enable Redis cluster mode (upgrade feature)"
  type        = bool
  default     = false
}