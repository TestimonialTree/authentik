# ECS Cluster
resource "aws_ecs_cluster" "main" {
  name = "${var.environment}-authentik"

  configuration {
    execute_command_configuration {
      kms_key_id = aws_kms_key.authentik.arn
      logging    = "OVERRIDE"

      log_configuration {
        cloud_watch_encryption_enabled = true
        cloud_watch_log_group_name     = aws_cloudwatch_log_group.ecs_exec.name
      }
    }
  }

  setting {
    name  = "containerInsights"
    value = var.enable_detailed_monitoring ? "enabled" : "disabled"
  }

  tags = {
    Name = "${var.environment}-authentik-cluster"
  }
}

# CloudWatch Log Group for ECS Exec
resource "aws_cloudwatch_log_group" "ecs_exec" {
  name              = "/ecs/${var.environment}-authentik-exec"
  retention_in_days = var.cloudwatch_log_retention_days
  # kms_key_id       = aws_kms_key.authentik.arn # Temporarily removed due to permissions

  tags = {
    Name = "${var.environment}-authentik-ecs-exec-logs"
  }
}

# CloudWatch Log Group for Authentik Application
resource "aws_cloudwatch_log_group" "authentik" {
  name              = "/ecs/${var.environment}-authentik"
  retention_in_days = var.cloudwatch_log_retention_days
  # kms_key_id       = aws_kms_key.authentik.arn # Temporarily removed due to permissions

  tags = {
    Name = "${var.environment}-authentik-logs"
  }
}

# ECS Task Definition for Authentik Server
resource "aws_ecs_task_definition" "authentik_server" {
  family                   = "${var.environment}-authentik-server"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = var.ecs_task_cpu
  memory                   = var.ecs_task_memory
  execution_role_arn       = aws_iam_role.ecs_execution.arn
  task_role_arn           = aws_iam_role.ecs_task.arn

  container_definitions = jsonencode([
    {
      name      = "authentik-server"
      image     = "${aws_ecr_repository.authentik.repository_url}:latest"
      essential = true
      command   = ["server"]

      portMappings = [
        {
          containerPort = 9000
          hostPort      = 9000
          protocol      = "tcp"
        }
      ]

      environment = [
        {
          name  = "AUTHENTIK_REDIS__HOST"
          value = aws_elasticache_cluster.redis.cache_nodes[0].address
        },
        {
          name  = "AUTHENTIK_REDIS__PORT"
          value = tostring(aws_elasticache_cluster.redis.cache_nodes[0].port)
        },
        {
          name  = "AUTHENTIK_POSTGRESQL__HOST"
          value = split(":", aws_db_instance.postgres.endpoint)[0]
        },
        {
          name  = "AUTHENTIK_POSTGRESQL__PORT"
          value = tostring(aws_db_instance.postgres.port)
        },
        {
          name  = "AUTHENTIK_POSTGRESQL__NAME"
          value = aws_db_instance.postgres.db_name
        },
        {
          name  = "AUTHENTIK_POSTGRESQL__USER"
          value = aws_db_instance.postgres.username
        },
        {
          name  = "AUTHENTIK_ERROR_REPORTING__ENABLED"
          value = tostring(var.authentik_error_reporting)
        },
        {
          name  = "AUTHENTIK_LOG_LEVEL"
          value = var.authentik_log_level
        },
        {
          name  = "AUTHENTIK_COOKIE_DOMAIN"
          value = var.domain_name
        },
        {
          name  = "AUTHENTIK_DISABLE_UPDATE_CHECK"
          value = "true"
        }
      ]

      secrets = [
        {
          name      = "AUTHENTIK_SECRET_KEY"
          valueFrom = "${aws_secretsmanager_secret.authentik.arn}:secret_key::"
        },
        {
          name      = "AUTHENTIK_POSTGRESQL__PASSWORD"
          valueFrom = "${aws_secretsmanager_secret.database.arn}:password::"
        }
      ]

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.authentik.name
          "awslogs-region"        = var.aws_region
          "awslogs-stream-prefix" = "server"
        }
      }

      healthCheck = {
        command = [
          "CMD-SHELL",
          "curl -f http://localhost:9000/-/health/live/ || exit 1"
        ]
        interval    = 30
        timeout     = 5
        retries     = 3
        startPeriod = 60
      }

      # Resource limits
      memory      = var.ecs_task_memory
      memoryReservation = floor(var.ecs_task_memory * 0.8)

      # Enable execute command for debugging
      linuxParameters = {
        initProcessEnabled = true
      }
    }
  ])

  tags = {
    Name = "${var.environment}-authentik-server-task"
  }
}

# ECS Task Definition for Authentik Worker
resource "aws_ecs_task_definition" "authentik_worker" {
  family                   = "${var.environment}-authentik-worker"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = var.ecs_task_cpu
  memory                   = var.ecs_task_memory
  execution_role_arn       = aws_iam_role.ecs_execution.arn
  task_role_arn           = aws_iam_role.ecs_task.arn

  container_definitions = jsonencode([
    {
      name      = "authentik-worker"
      image     = "ghcr.io/goauthentik/server:2024.8.3"
      essential = true
      command   = ["worker"]

      environment = [
        {
          name  = "AUTHENTIK_REDIS__HOST"
          value = aws_elasticache_cluster.redis.cache_nodes[0].address
        },
        {
          name  = "AUTHENTIK_REDIS__PORT"
          value = tostring(aws_elasticache_cluster.redis.cache_nodes[0].port)
        },
        {
          name  = "AUTHENTIK_POSTGRESQL__HOST"
          value = split(":", aws_db_instance.postgres.endpoint)[0]
        },
        {
          name  = "AUTHENTIK_POSTGRESQL__PORT"
          value = tostring(aws_db_instance.postgres.port)
        },
        {
          name  = "AUTHENTIK_POSTGRESQL__NAME"
          value = aws_db_instance.postgres.db_name
        },
        {
          name  = "AUTHENTIK_POSTGRESQL__USER"
          value = aws_db_instance.postgres.username
        },
        {
          name  = "AUTHENTIK_ERROR_REPORTING__ENABLED"
          value = tostring(var.authentik_error_reporting)
        },
        {
          name  = "AUTHENTIK_LOG_LEVEL"
          value = var.authentik_log_level
        },
        {
          name  = "AUTHENTIK_DISABLE_UPDATE_CHECK"
          value = "true"
        }
      ]

      secrets = [
        {
          name      = "AUTHENTIK_SECRET_KEY"
          valueFrom = "${aws_secretsmanager_secret.authentik.arn}:secret_key::"
        },
        {
          name      = "AUTHENTIK_POSTGRESQL__PASSWORD"
          valueFrom = "${aws_secretsmanager_secret.database.arn}:password::"
        }
      ]

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.authentik.name
          "awslogs-region"        = var.aws_region
          "awslogs-stream-prefix" = "worker"
        }
      }

      # Resource limits
      memory      = var.ecs_task_memory
      memoryReservation = floor(var.ecs_task_memory * 0.8)

      # Enable execute command for debugging
      linuxParameters = {
        initProcessEnabled = true
      }
    }
  ])

  tags = {
    Name = "${var.environment}-authentik-worker-task"
  }
}

# ECS Service for Authentik Server
resource "aws_ecs_service" "authentik_server" {
  name            = "${var.environment}-authentik-server"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.authentik_server.arn
  desired_count   = var.ecs_desired_count
  launch_type     = "FARGATE"

  platform_version = "1.4.0"

  # Enable execute command for debugging
  enable_execute_command = true

  network_configuration {
    subnets          = aws_subnet.private[*].id
    security_groups  = [aws_security_group.ecs.id]
    assign_public_ip = false
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.authentik_server.arn
    container_name   = "authentik-server"
    container_port   = 9000
  }

  # Deployment configuration
  deployment_maximum_percent         = 200
  deployment_minimum_healthy_percent = 100

  # Service discovery (optional)
  # service_registries {
  #   registry_arn = aws_service_discovery_service.authentik_server.arn
  # }

  depends_on = [
    aws_lb_listener.https,
    aws_iam_role_policy.ecs_execution_secrets,
    aws_iam_role_policy.ecs_task_s3
  ]

  tags = {
    Name = "${var.environment}-authentik-server-service"
  }

  lifecycle {
    ignore_changes = [task_definition]
  }
}

# ECS Service for Authentik Worker
resource "aws_ecs_service" "authentik_worker" {
  name            = "${var.environment}-authentik-worker"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.authentik_worker.arn
  desired_count   = 1
  launch_type     = "FARGATE"

  platform_version = "1.4.0"

  # Enable execute command for debugging
  enable_execute_command = true

  network_configuration {
    subnets          = aws_subnet.private[*].id
    security_groups  = [aws_security_group.ecs.id]
    assign_public_ip = false
  }

  # Deployment configuration
  deployment_maximum_percent         = 200
  deployment_minimum_healthy_percent = 50

  depends_on = [
    aws_iam_role_policy.ecs_execution_secrets,
    aws_iam_role_policy.ecs_task_s3
  ]

  tags = {
    Name = "${var.environment}-authentik-worker-service"
  }

  lifecycle {
    ignore_changes = [task_definition]
  }
}

# CloudWatch Alarms for ECS Services
resource "aws_cloudwatch_metric_alarm" "ecs_cpu_server" {
  alarm_name          = "${var.environment}-authentik-server-cpu-utilization"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "CPUUtilization"
  namespace           = "AWS/ECS"
  period              = "300"
  statistic           = "Average"
  threshold           = "80"
  alarm_description   = "This metric monitors ECS server CPU utilization"
  alarm_actions       = var.notification_email != "" ? [aws_sns_topic.alerts[0].arn] : []

  dimensions = {
    ServiceName = aws_ecs_service.authentik_server.name
    ClusterName = aws_ecs_cluster.main.name
  }

  tags = {
    Name = "${var.environment}-authentik-server-cpu-alarm"
  }
}

resource "aws_cloudwatch_metric_alarm" "ecs_memory_server" {
  alarm_name          = "${var.environment}-authentik-server-memory-utilization"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "MemoryUtilization"
  namespace           = "AWS/ECS"
  period              = "300"
  statistic           = "Average"
  threshold           = "85"
  alarm_description   = "This metric monitors ECS server memory utilization"
  alarm_actions       = var.notification_email != "" ? [aws_sns_topic.alerts[0].arn] : []

  dimensions = {
    ServiceName = aws_ecs_service.authentik_server.name
    ClusterName = aws_ecs_cluster.main.name
  }

  tags = {
    Name = "${var.environment}-authentik-server-memory-alarm"
  }
}