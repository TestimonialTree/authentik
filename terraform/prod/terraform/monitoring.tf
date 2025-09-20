# SNS Topic for Alerts
resource "aws_sns_topic" "alerts" {
  count = var.notification_email != "" ? 1 : 0

  name              = "${var.environment}-authentik-alerts"
  kms_master_key_id = aws_kms_key.authentik.arn

  tags = {
    Name = "${var.environment}-authentik-alerts"
  }
}

resource "aws_sns_topic_subscription" "email" {
  count = var.notification_email != "" ? 1 : 0

  topic_arn = aws_sns_topic.alerts[0].arn
  protocol  = "email"
  endpoint  = var.notification_email
}

# CloudWatch Dashboard
resource "aws_cloudwatch_dashboard" "authentik" {
  dashboard_name = "${var.environment}-authentik-overview"

  dashboard_body = jsonencode({
    widgets = [
      {
        type   = "metric"
        x      = 0
        y      = 0
        width  = 12
        height = 6

        properties = {
          metrics = [
            ["AWS/ApplicationELB", "RequestCount", "LoadBalancer", aws_lb.main.arn_suffix],
            [".", "TargetResponseTime", ".", "."],
            [".", "HTTPCode_Target_2XX_Count", ".", "."],
            [".", "HTTPCode_Target_4XX_Count", ".", "."],
            [".", "HTTPCode_Target_5XX_Count", ".", "."]
          ]
          view    = "timeSeries"
          stacked = false
          region  = var.aws_region
          title   = "Application Load Balancer Metrics"
          period  = 300
        }
      },
      {
        type   = "metric"
        x      = 12
        y      = 0
        width  = 12
        height = 6

        properties = {
          metrics = [
            ["AWS/ECS", "CPUUtilization", "ServiceName", aws_ecs_service.authentik_server.name, "ClusterName", aws_ecs_cluster.main.name],
            [".", "MemoryUtilization", ".", ".", ".", "."],
            [".", "RunningTaskCount", ".", ".", ".", "."]
          ]
          view    = "timeSeries"
          stacked = false
          region  = var.aws_region
          title   = "ECS Service Metrics"
          period  = 300
        }
      },
      {
        type   = "metric"
        x      = 0
        y      = 6
        width  = 12
        height = 6

        properties = {
          metrics = [
            ["AWS/RDS", "CPUUtilization", "DBInstanceIdentifier", aws_db_instance.postgres.id],
            [".", "DatabaseConnections", ".", "."],
            [".", "FreeStorageSpace", ".", "."],
            [".", "ReadLatency", ".", "."],
            [".", "WriteLatency", ".", "."]
          ]
          view    = "timeSeries"
          stacked = false
          region  = var.aws_region
          title   = "RDS Metrics"
          period  = 300
        }
      },
      {
        type   = "metric"
        x      = 12
        y      = 6
        width  = 12
        height = 6

        properties = {
          metrics = [
            ["AWS/ElastiCache", "CPUUtilization", "CacheClusterId", aws_elasticache_cluster.redis.cluster_id],
            [".", "DatabaseMemoryUsagePercentage", ".", "."],
            [".", "CurrConnections", ".", "."],
            [".", "NetworkBytesIn", ".", "."],
            [".", "NetworkBytesOut", ".", "."]
          ]
          view    = "timeSeries"
          stacked = false
          region  = var.aws_region
          title   = "ElastiCache Redis Metrics"
          period  = 300
        }
      },
      {
        type   = "log"
        x      = 0
        y      = 12
        width  = 24
        height = 6

        properties = {
          query   = "SOURCE '${aws_cloudwatch_log_group.authentik.name}'\n| fields @timestamp, @message\n| sort @timestamp desc\n| limit 100"
          region  = var.aws_region
          title   = "Recent Application Logs"
          view    = "table"
        }
      }
    ]
  })

  # Note: CloudWatch dashboards don't support tags in this AWS provider version
}

# Custom CloudWatch Metrics for Application Health
resource "aws_cloudwatch_log_metric_filter" "error_count" {
  name           = "${var.environment}-authentik-error-count"
  log_group_name = aws_cloudwatch_log_group.authentik.name
  pattern        = "[timestamp, request_id, ERROR]"

  metric_transformation {
    name      = "ErrorCount"
    namespace = "Authentik/${var.environment}"
    value     = "1"
  }
}

resource "aws_cloudwatch_metric_alarm" "application_errors" {
  alarm_name          = "${var.environment}-authentik-application-errors"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "ErrorCount"
  namespace           = "Authentik/${var.environment}"
  period              = "300"
  statistic           = "Sum"
  threshold           = "10"
  alarm_description   = "This metric monitors application error count"
  alarm_actions       = var.notification_email != "" ? [aws_sns_topic.alerts[0].arn] : []

  tags = {
    Name = "${var.environment}-authentik-app-errors-alarm"
  }
}

# CloudWatch Metric Filter for Login Attempts
resource "aws_cloudwatch_log_metric_filter" "login_attempts" {
  name           = "${var.environment}-authentik-login-attempts"
  log_group_name = aws_cloudwatch_log_group.authentik.name
  pattern        = "[timestamp, request_id, level, logger=\"authentik.flows.planner\", action=\"login\"]"

  metric_transformation {
    name      = "LoginAttempts"
    namespace = "Authentik/${var.environment}"
    value     = "1"
  }
}

# CloudWatch Metric Filter for Failed Logins
resource "aws_cloudwatch_log_metric_filter" "failed_logins" {
  name           = "${var.environment}-authentik-failed-logins"
  log_group_name = aws_cloudwatch_log_group.authentik.name
  pattern        = "[timestamp, request_id, level, logger=\"authentik.events.models\", action=\"login_failed\"]"

  metric_transformation {
    name      = "FailedLogins"
    namespace = "Authentik/${var.environment}"
    value     = "1"
  }
}

resource "aws_cloudwatch_metric_alarm" "failed_login_rate" {
  alarm_name          = "${var.environment}-authentik-failed-login-rate"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "FailedLogins"
  namespace           = "Authentik/${var.environment}"
  period              = "300"
  statistic           = "Sum"
  threshold           = "50"  # More than 50 failed logins in 5 minutes
  alarm_description   = "This metric monitors failed login attempts"
  alarm_actions       = var.notification_email != "" ? [aws_sns_topic.alerts[0].arn] : []

  tags = {
    Name = "${var.environment}-authentik-failed-logins-alarm"
  }
}

# CloudWatch Composite Alarm for Overall Application Health
resource "aws_cloudwatch_composite_alarm" "application_health" {
  alarm_name        = "${var.environment}-authentik-application-health"
  alarm_description = "Composite alarm for Authentik application health"

  alarm_rule = join(" OR ", [
    "ALARM(${aws_cloudwatch_metric_alarm.alb_healthy_hosts.alarm_name})",
    "ALARM(${aws_cloudwatch_metric_alarm.ecs_cpu_server.alarm_name})",
    "ALARM(${aws_cloudwatch_metric_alarm.ecs_memory_server.alarm_name})",
    "ALARM(${aws_cloudwatch_metric_alarm.rds_cpu.alarm_name})",
    "ALARM(${aws_cloudwatch_metric_alarm.redis_cpu.alarm_name})",
    "ALARM(${aws_cloudwatch_metric_alarm.application_errors.alarm_name})"
  ])

  alarm_actions = var.notification_email != "" ? [aws_sns_topic.alerts[0].arn] : []
  ok_actions    = var.notification_email != "" ? [aws_sns_topic.alerts[0].arn] : []

  tags = {
    Name = "${var.environment}-authentik-composite-health-alarm"
  }
}

# CloudWatch Insights Queries (for manual analysis)
resource "aws_cloudwatch_query_definition" "error_analysis" {
  name = "${var.environment}-authentik-error-analysis"

  log_group_names = [
    aws_cloudwatch_log_group.authentik.name
  ]

  query_string = <<EOF
fields @timestamp, @message
| filter @message like /ERROR/
| sort @timestamp desc
| limit 50
EOF
}

resource "aws_cloudwatch_query_definition" "performance_analysis" {
  name = "${var.environment}-authentik-performance-analysis"

  log_group_names = [
    aws_cloudwatch_log_group.authentik.name
  ]

  query_string = <<EOF
fields @timestamp, @message
| filter @message like /slow/
| sort @timestamp desc
| limit 50
EOF
}

resource "aws_cloudwatch_query_definition" "authentication_analysis" {
  name = "${var.environment}-authentik-authentication-analysis"

  log_group_names = [
    aws_cloudwatch_log_group.authentik.name
  ]

  query_string = <<EOF
fields @timestamp, @message
| filter @message like /login/ or @message like /auth/
| sort @timestamp desc
| limit 100
EOF
}

# CloudWatch Log Stream for application health checks
resource "aws_cloudwatch_log_stream" "health_checks" {
  name           = "health-checks"
  log_group_name = aws_cloudwatch_log_group.authentik.name
}

# Export logs to S3 for long-term storage (optional)
# resource "aws_cloudwatch_log_destination" "s3_export" {
#   name       = "${var.environment}-authentik-log-export"
#   role_arn   = aws_iam_role.log_export.arn
#   target_arn = aws_s3_bucket.log_archive.arn
# }

# Data sources for monitoring
# Note: This data source is commented out to avoid count issues during deployment
# data "aws_cloudwatch_log_group" "existing" {
#   count = length(aws_cloudwatch_log_group.authentik.name) > 0 ? 1 : 0
#   name  = aws_cloudwatch_log_group.authentik.name
# }