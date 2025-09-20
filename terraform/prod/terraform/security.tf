# Security Group for Application Load Balancer
resource "aws_security_group" "alb" {
  name_prefix = "${var.environment}-authentik-alb-"
  vpc_id      = aws_vpc.main.id

  description = "Security group for Authentik ALB"

  tags = {
    Name = "${var.environment}-authentik-alb-sg"
  }

  lifecycle {
    create_before_destroy = true
  }
}

# Security Group for ECS Tasks
resource "aws_security_group" "ecs" {
  name_prefix = "${var.environment}-authentik-ecs-"
  vpc_id      = aws_vpc.main.id

  description = "Security group for Authentik ECS tasks"

  tags = {
    Name = "${var.environment}-authentik-ecs-sg"
  }

  lifecycle {
    create_before_destroy = true
  }
}

# Security Group for RDS
resource "aws_security_group" "rds" {
  name_prefix = "${var.environment}-authentik-rds-"
  vpc_id      = aws_vpc.main.id

  description = "Security group for Authentik RDS instance"

  tags = {
    Name = "${var.environment}-authentik-rds-sg"
  }

  lifecycle {
    create_before_destroy = true
  }
}

# Security Group for Redis
resource "aws_security_group" "redis" {
  name_prefix = "${var.environment}-authentik-redis-"
  vpc_id      = aws_vpc.main.id

  description = "Security group for Authentik Redis cluster"

  tags = {
    Name = "${var.environment}-authentik-redis-sg"
  }

  lifecycle {
    create_before_destroy = true
  }
}

# Security Group Rules
resource "aws_security_group_rule" "alb_http_ingress" {
  type              = "ingress"
  from_port         = 80
  to_port           = 80
  protocol          = "tcp"
  cidr_blocks       = var.allowed_cidr_blocks
  security_group_id = aws_security_group.alb.id
  description       = "HTTP"
}

resource "aws_security_group_rule" "alb_https_ingress" {
  type              = "ingress"
  from_port         = 443
  to_port           = 443
  protocol          = "tcp"
  cidr_blocks       = var.allowed_cidr_blocks
  security_group_id = aws_security_group.alb.id
  description       = "HTTPS"
}

resource "aws_security_group_rule" "alb_to_ecs_egress" {
  type                     = "egress"
  from_port                = 9000
  to_port                  = 9000
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.ecs.id
  security_group_id        = aws_security_group.alb.id
  description              = "HTTP to ECS"
}

resource "aws_security_group_rule" "alb_all_egress" {
  type              = "egress"
  from_port         = 0
  to_port           = 0
  protocol          = "-1"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.alb.id
  description       = "All outbound traffic"
}

resource "aws_security_group_rule" "ecs_from_alb_ingress" {
  type                     = "ingress"
  from_port                = 9000
  to_port                  = 9000
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.alb.id
  security_group_id        = aws_security_group.ecs.id
  description              = "HTTP from ALB"
}

resource "aws_security_group_rule" "ecs_to_rds_egress" {
  type                     = "egress"
  from_port                = 5432
  to_port                  = 5432
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.rds.id
  security_group_id        = aws_security_group.ecs.id
  description              = "PostgreSQL to RDS"
}

resource "aws_security_group_rule" "ecs_to_redis_egress" {
  type                     = "egress"
  from_port                = 6379
  to_port                  = 6379
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.redis.id
  security_group_id        = aws_security_group.ecs.id
  description              = "Redis to ElastiCache"
}

# Additional ECS egress rules for external services
resource "aws_security_group_rule" "ecs_https_egress" {
  type              = "egress"
  from_port         = 443
  to_port           = 443
  protocol          = "tcp"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.ecs.id
  description       = "HTTPS outbound"
}

resource "aws_security_group_rule" "ecs_http_egress" {
  type              = "egress"
  from_port         = 80
  to_port           = 80
  protocol          = "tcp"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.ecs.id
  description       = "HTTP outbound"
}

resource "aws_security_group_rule" "ecs_dns_egress" {
  type              = "egress"
  from_port         = 53
  to_port           = 53
  protocol          = "udp"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.ecs.id
  description       = "DNS outbound"
}

resource "aws_security_group_rule" "ecs_ntp_egress" {
  type              = "egress"
  from_port         = 123
  to_port           = 123
  protocol          = "udp"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.ecs.id
  description       = "NTP outbound"
}

resource "aws_security_group_rule" "ecs_ldap_egress" {
  type              = "egress"
  from_port         = 389
  to_port           = 389
  protocol          = "tcp"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.ecs.id
  description       = "LDAP outbound"
}

resource "aws_security_group_rule" "ecs_ldaps_egress" {
  type              = "egress"
  from_port         = 636
  to_port           = 636
  protocol          = "tcp"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.ecs.id
  description       = "LDAPS outbound"
}

resource "aws_security_group_rule" "ecs_smtp_egress" {
  type              = "egress"
  from_port         = 587
  to_port           = 587
  protocol          = "tcp"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.ecs.id
  description       = "SMTP outbound"
}

resource "aws_security_group_rule" "ecs_smtp_ssl_egress" {
  type              = "egress"
  from_port         = 465
  to_port           = 465
  protocol          = "tcp"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.ecs.id
  description       = "SMTP SSL outbound"
}

resource "aws_security_group_rule" "rds_from_ecs_ingress" {
  type                     = "ingress"
  from_port                = 5432
  to_port                  = 5432
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.ecs.id
  security_group_id        = aws_security_group.rds.id
  description              = "PostgreSQL from ECS"
}

resource "aws_security_group_rule" "redis_from_ecs_ingress" {
  type                     = "ingress"
  from_port                = 6379
  to_port                  = 6379
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.ecs.id
  security_group_id        = aws_security_group.redis.id
  description              = "Redis from ECS"
}

# IAM Role for ECS Task Execution
resource "aws_iam_role" "ecs_execution" {
  name = "${var.environment}-authentik-ecs-execution-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ecs-tasks.amazonaws.com"
        }
      }
    ]
  })

  tags = {
    Name = "${var.environment}-authentik-ecs-execution-role"
  }
}

resource "aws_iam_role_policy_attachment" "ecs_execution" {
  role       = aws_iam_role.ecs_execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

# Additional policy for ECR and Secrets Manager access
resource "aws_iam_role_policy" "ecs_execution_secrets" {
  name = "${var.environment}-authentik-ecs-execution-secrets"
  role = aws_iam_role.ecs_execution.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "secretsmanager:GetSecretValue"
        ]
        Resource = [
          aws_secretsmanager_secret.database.arn,
          aws_secretsmanager_secret.authentik.arn,
          aws_secretsmanager_secret.redis.arn
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "kms:Decrypt"
        ]
        Resource = [aws_kms_key.authentik.arn]
      },
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "arn:aws:logs:${var.aws_region}:${data.aws_caller_identity.current.account_id}:*"
      }
    ]
  })
}

# IAM Role for ECS Task
resource "aws_iam_role" "ecs_task" {
  name = "${var.environment}-authentik-ecs-task-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ecs-tasks.amazonaws.com"
        }
      }
    ]
  })

  tags = {
    Name = "${var.environment}-authentik-ecs-task-role"
  }
}

# Task role policy for S3 access (media files)
resource "aws_iam_role_policy" "ecs_task_s3" {
  name = "${var.environment}-authentik-ecs-task-s3"
  role = aws_iam_role.ecs_task.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject",
          "s3:ListBucket"
        ]
        Resource = [
          aws_s3_bucket.media.arn,
          "${aws_s3_bucket.media.arn}/*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "kms:Decrypt",
          "kms:GenerateDataKey"
        ]
        Resource = [aws_kms_key.authentik.arn]
      }
    ]
  })
}

# Store Authentik secrets in Secrets Manager
resource "aws_secretsmanager_secret" "authentik" {
  name                    = "${var.environment}-authentik-config"
  description             = "Authentik application configuration"
  kms_key_id             = aws_kms_key.authentik.arn
  recovery_window_in_days = 7

  tags = {
    Name = "${var.environment}-authentik-config-secret"
  }
}

resource "aws_secretsmanager_secret_version" "authentik" {
  secret_id = aws_secretsmanager_secret.authentik.id
  secret_string = jsonencode({
    secret_key = var.authentik_secret_key
    log_level  = var.authentik_log_level
    error_reporting_enabled = var.authentik_error_reporting
  })

  lifecycle {
    ignore_changes = [secret_string]
  }
}