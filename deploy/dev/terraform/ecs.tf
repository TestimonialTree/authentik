# ECS Cluster
resource "aws_ecs_cluster" "main" {
  name = var.project_name

  setting {
    name  = "containerInsights"
    value = "enabled"
  }

  tags = {
    Name = var.project_name
  }
}

# ECS Task Execution Role
resource "aws_iam_role" "ecs_execution_role" {
  name = "${var.project_name}-ecs-execution-role"

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
    Name = "${var.project_name}-ecs-execution-role"
  }
}

resource "aws_iam_role_policy_attachment" "ecs_execution_role_policy" {
  role       = aws_iam_role.ecs_execution_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

# Policy for accessing Secrets Manager
resource "aws_iam_role_policy" "ecs_secrets_policy" {
  name = "${var.project_name}-ecs-secrets-policy"
  role = aws_iam_role.ecs_execution_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "secretsmanager:GetSecretValue"
        ]
        Resource = [data.aws_secretsmanager_secret.app_config.arn]
      }
    ]
  })
}

# CloudWatch Log Group
resource "aws_cloudwatch_log_group" "main" {
  name              = "/ecs/${var.project_name}"
  retention_in_days = 7

  tags = {
    Name = "${var.project_name}-logs"
  }
}

# ECS Task Definition
resource "aws_ecs_task_definition" "main" {
  family                   = var.project_name
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = "1024"
  memory                   = "2048"
  execution_role_arn       = aws_iam_role.ecs_execution_role.arn
  task_role_arn           = aws_iam_role.ecs_execution_role.arn

  container_definitions = jsonencode([
    {
      name    = "authentik-server"
      image   = var.image_uri
      command = ["server"]

      portMappings = [
        {
          containerPort = 9000
          hostPort      = 9000
          protocol      = "tcp"
        },
        {
          containerPort = 9443
          hostPort      = 9443
          protocol      = "tcp"
        }
      ]

      environment = [
        {
          name  = "AUTHENTIK_REDIS__HOST"
          value = "localhost"
        },
        {
          name  = "AUTHENTIK_LOG_LEVEL"
          value = "info"
        }
      ]

      secrets = [
        { name = "AUTHENTIK_SECRET_KEY",          valueFrom = "${data.aws_secretsmanager_secret.app_config.arn}:AUTHENTIK_SECRET_KEY::" },
        { name = "AUTHENTIK_POSTGRESQL__HOST",    valueFrom = "${data.aws_secretsmanager_secret.app_config.arn}:AUTHENTIK_POSTGRESQL__HOST::" },
        { name = "AUTHENTIK_POSTGRESQL__PASSWORD", valueFrom = "${data.aws_secretsmanager_secret.app_config.arn}:AUTHENTIK_POSTGRESQL__PASSWORD::" },
        { name = "AUTHENTIK_POSTGRESQL__USER",    valueFrom = "${data.aws_secretsmanager_secret.app_config.arn}:AUTHENTIK_POSTGRESQL__USER::" },
        { name = "AUTHENTIK_POSTGRESQL__NAME",    valueFrom = "${data.aws_secretsmanager_secret.app_config.arn}:AUTHENTIK_POSTGRESQL__NAME::" }
      ]

      dependsOn = [{ containerName = "redis", condition = "START" }]

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.main.name
          "awslogs-region"        = var.aws_region
          "awslogs-stream-prefix" = "ecs"
        }
      }

      essential = true
    },
    {
      name    = "authentik-worker"
      image   = var.image_uri
      command = ["worker"]

      environment = [
        {
          name  = "AUTHENTIK_REDIS__HOST"
          value = "localhost"
        },
        {
          name  = "AUTHENTIK_LOG_LEVEL"
          value = "info"
        }
      ]

      secrets = [
        { name = "AUTHENTIK_SECRET_KEY",          valueFrom = "${data.aws_secretsmanager_secret.app_config.arn}:AUTHENTIK_SECRET_KEY::" },
        { name = "AUTHENTIK_POSTGRESQL__HOST",    valueFrom = "${data.aws_secretsmanager_secret.app_config.arn}:AUTHENTIK_POSTGRESQL__HOST::" },
        { name = "AUTHENTIK_POSTGRESQL__PASSWORD", valueFrom = "${data.aws_secretsmanager_secret.app_config.arn}:AUTHENTIK_POSTGRESQL__PASSWORD::" },
        { name = "AUTHENTIK_POSTGRESQL__USER",    valueFrom = "${data.aws_secretsmanager_secret.app_config.arn}:AUTHENTIK_POSTGRESQL__USER::" },
        { name = "AUTHENTIK_POSTGRESQL__NAME",    valueFrom = "${data.aws_secretsmanager_secret.app_config.arn}:AUTHENTIK_POSTGRESQL__NAME::" }
      ]

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.main.name
          "awslogs-region"        = var.aws_region
          "awslogs-stream-prefix" = "ecs"
        }
      }

      essential = true
    },
    {
      name  = "redis"
      image = "redis:7-alpine"
      
      portMappings = [
        {
          containerPort = 6379
          hostPort      = 6379
          protocol      = "tcp"
        }
      ]

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.main.name
          "awslogs-region"        = var.aws_region
          "awslogs-stream-prefix" = "ecs"
        }
      }

      essential = true
    }
  ])

  tags = {
    Name = "${var.project_name}-task-definition"
  }
}

# ECS Service
resource "aws_ecs_service" "main" {
  name            = var.project_name
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.main.arn
  desired_count   = 1
  launch_type     = "FARGATE"

  # Deployment configuration with error handling
  deployment_maximum_percent         = 200
  deployment_minimum_healthy_percent = 50

  # Circuit breaker temporarily disabled for testing
  deployment_circuit_breaker {
    enable   = false
    rollback = false
  }

  network_configuration {
    security_groups  = [aws_security_group.ecs.id]
    subnets          = [data.aws_subnet.private_1.id, data.aws_subnet.private_2.id]
    assign_public_ip = false
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.main.arn
    container_name   = "authentik-server"
    container_port   = 9000
  }

  depends_on = [aws_lb_listener.https]

  tags = {
    Name = "${var.project_name}-service"
  }

  lifecycle {
    ignore_changes = [task_definition, desired_count]
  }
}
