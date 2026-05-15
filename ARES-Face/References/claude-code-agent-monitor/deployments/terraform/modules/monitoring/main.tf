# ─────────────────────────────────────────────────────────────────────────────
# Monitoring module – Observability, alerting, and dashboards
#
# Provisions:
#   - CloudWatch log groups for centralized log aggregation
#   - Metric alarms for error rate, latency, disk, unhealthy hosts
#   - SNS topic for alert notifications
#   - CloudWatch dashboard with key operational metrics
# ─────────────────────────────────────────────────────────────────────────────

locals {
  name_prefix = lower(replace("${var.project_name}-${var.environment}", "_", "-"))

  common_tags = merge(
    {
      module = "monitoring"
    },
    var.tags,
  )

  # Parse ALB ARN suffix for CloudWatch metric dimensions
  alb_arn_suffix = try(
    regex("app/.*$", var.loadbalancer_arn),
    ""
  )
}

# ─────────────────────────────────────────────────────────────────────────────
# SNS topic for alert notifications
# ─────────────────────────────────────────────────────────────────────────────

resource "aws_sns_topic" "alerts" {
  name = "${local.name_prefix}-alerts"

  tags = local.common_tags
}

resource "aws_sns_topic_subscription" "email" {
  count = var.alert_email != "" ? 1 : 0

  topic_arn = aws_sns_topic.alerts.arn
  protocol  = "email"
  endpoint  = var.alert_email
}

# ─────────────────────────────────────────────────────────────────────────────
# CloudWatch log group (application-level)
# ─────────────────────────────────────────────────────────────────────────────

resource "aws_cloudwatch_log_group" "application" {
  name              = "/ccam/${local.name_prefix}"
  retention_in_days = var.log_retention_days

  tags = local.common_tags
}

# ─────────────────────────────────────────────────────────────────────────────
# Metric alarms
# ─────────────────────────────────────────────────────────────────────────────

# High 5xx error rate from ALB
resource "aws_cloudwatch_metric_alarm" "high_5xx_rate" {
  alarm_name          = "${local.name_prefix}-high-5xx-error-rate"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 3
  metric_name         = "HTTPCode_Target_5XX_Count"
  namespace           = "AWS/ApplicationELB"
  period              = 60
  statistic           = "Sum"
  threshold           = 10
  alarm_description   = "High 5XX error rate detected on ${local.name_prefix} ALB"
  treat_missing_data  = "notBreaching"

  dimensions = {
    LoadBalancer = local.alb_arn_suffix
  }

  alarm_actions = [aws_sns_topic.alerts.arn]
  ok_actions    = [aws_sns_topic.alerts.arn]

  tags = local.common_tags
}

# High target response time (latency)
resource "aws_cloudwatch_metric_alarm" "high_latency" {
  alarm_name          = "${local.name_prefix}-high-latency"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 3
  metric_name         = "TargetResponseTime"
  namespace           = "AWS/ApplicationELB"
  period              = 60
  statistic           = "Average"
  threshold           = 2.0 # seconds
  alarm_description   = "High average latency (>2s) on ${local.name_prefix} ALB"
  treat_missing_data  = "notBreaching"

  dimensions = {
    LoadBalancer = local.alb_arn_suffix
  }

  alarm_actions = [aws_sns_topic.alerts.arn]
  ok_actions    = [aws_sns_topic.alerts.arn]

  tags = local.common_tags
}

# Unhealthy host count
resource "aws_cloudwatch_metric_alarm" "unhealthy_hosts" {
  count = length(var.target_group_arns)

  alarm_name          = "${local.name_prefix}-unhealthy-hosts-${count.index}"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "UnHealthyHostCount"
  namespace           = "AWS/ApplicationELB"
  period              = 60
  statistic           = "Maximum"
  threshold           = 0
  alarm_description   = "Unhealthy targets detected in target group ${count.index}"
  treat_missing_data  = "notBreaching"

  dimensions = {
    LoadBalancer = local.alb_arn_suffix
    TargetGroup  = try(regex("targetgroup/.*$", var.target_group_arns[count.index]), "")
  }

  alarm_actions = [aws_sns_topic.alerts.arn]
  ok_actions    = [aws_sns_topic.alerts.arn]

  tags = local.common_tags
}

# EFS burst credit balance (low disk throughput)
resource "aws_cloudwatch_metric_alarm" "efs_burst_credits" {
  alarm_name          = "${local.name_prefix}-efs-low-burst-credits"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = 3
  metric_name         = "BurstCreditBalance"
  namespace           = "AWS/EFS"
  period              = 300
  statistic           = "Average"
  threshold           = 1000000000 # 1 GiB in bytes
  alarm_description   = "EFS burst credits running low for ${local.name_prefix}"
  treat_missing_data  = "notBreaching"

  dimensions = {
    FileSystemId = var.filesystem_id
  }

  alarm_actions = [aws_sns_topic.alerts.arn]

  tags = local.common_tags
}

# ECS CPU utilisation (cluster-level)
resource "aws_cloudwatch_metric_alarm" "ecs_high_cpu" {
  alarm_name          = "${local.name_prefix}-ecs-high-cpu"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 3
  metric_name         = "CPUUtilization"
  namespace           = "AWS/ECS"
  period              = 300
  statistic           = "Average"
  threshold           = 85
  alarm_description   = "High ECS CPU utilisation (>85%) for cluster ${var.compute_cluster_name}"
  treat_missing_data  = "notBreaching"

  dimensions = {
    ClusterName = var.compute_cluster_name
  }

  alarm_actions = [aws_sns_topic.alerts.arn]
  ok_actions    = [aws_sns_topic.alerts.arn]

  tags = local.common_tags
}

# ECS Memory utilisation
resource "aws_cloudwatch_metric_alarm" "ecs_high_memory" {
  alarm_name          = "${local.name_prefix}-ecs-high-memory"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 3
  metric_name         = "MemoryUtilization"
  namespace           = "AWS/ECS"
  period              = 300
  statistic           = "Average"
  threshold           = 85
  alarm_description   = "High ECS memory utilisation (>85%) for cluster ${var.compute_cluster_name}"
  treat_missing_data  = "notBreaching"

  dimensions = {
    ClusterName = var.compute_cluster_name
  }

  alarm_actions = [aws_sns_topic.alerts.arn]
  ok_actions    = [aws_sns_topic.alerts.arn]

  tags = local.common_tags
}

# ─────────────────────────────────────────────────────────────────────────────
# CloudWatch Dashboard
# ─────────────────────────────────────────────────────────────────────────────

resource "aws_cloudwatch_dashboard" "main" {
  dashboard_name = local.name_prefix
  dashboard_body = jsonencode({
    widgets = [
      {
        type   = "metric"
        x      = 0
        y      = 0
        width  = 12
        height = 6
        properties = {
          title   = "ALB Request Count"
          region  = var.region
          metrics = [
            ["AWS/ApplicationELB", "RequestCount", "LoadBalancer", local.alb_arn_suffix, { stat = "Sum", period = 60 }]
          ]
          view   = "timeSeries"
          stacked = false
        }
      },
      {
        type   = "metric"
        x      = 12
        y      = 0
        width  = 12
        height = 6
        properties = {
          title   = "ALB Response Time"
          region  = var.region
          metrics = [
            ["AWS/ApplicationELB", "TargetResponseTime", "LoadBalancer", local.alb_arn_suffix, { stat = "Average", period = 60 }],
            ["AWS/ApplicationELB", "TargetResponseTime", "LoadBalancer", local.alb_arn_suffix, { stat = "p99", period = 60 }],
          ]
          view   = "timeSeries"
          stacked = false
        }
      },
      {
        type   = "metric"
        x      = 0
        y      = 6
        width  = 12
        height = 6
        properties = {
          title   = "HTTP Error Rates"
          region  = var.region
          metrics = [
            ["AWS/ApplicationELB", "HTTPCode_Target_4XX_Count", "LoadBalancer", local.alb_arn_suffix, { stat = "Sum", period = 60 }],
            ["AWS/ApplicationELB", "HTTPCode_Target_5XX_Count", "LoadBalancer", local.alb_arn_suffix, { stat = "Sum", period = 60 }],
          ]
          view   = "timeSeries"
          stacked = false
        }
      },
      {
        type   = "metric"
        x      = 12
        y      = 6
        width  = 12
        height = 6
        properties = {
          title   = "ECS CPU & Memory"
          region  = var.region
          metrics = [
            ["AWS/ECS", "CPUUtilization", "ClusterName", var.compute_cluster_name, { stat = "Average", period = 60 }],
            ["AWS/ECS", "MemoryUtilization", "ClusterName", var.compute_cluster_name, { stat = "Average", period = 60 }],
          ]
          view   = "timeSeries"
          stacked = false
        }
      },
      {
        type   = "metric"
        x      = 0
        y      = 12
        width  = 12
        height = 6
        properties = {
          title   = "EFS I/O"
          region  = var.region
          metrics = [
            ["AWS/EFS", "DataReadIOBytes", "FileSystemId", var.filesystem_id, { stat = "Sum", period = 60 }],
            ["AWS/EFS", "DataWriteIOBytes", "FileSystemId", var.filesystem_id, { stat = "Sum", period = 60 }],
          ]
          view   = "timeSeries"
          stacked = false
        }
      },
      {
        type   = "metric"
        x      = 12
        y      = 12
        width  = 12
        height = 6
        properties = {
          title   = "Healthy vs Unhealthy Hosts"
          region  = var.region
          metrics = [
            ["AWS/ApplicationELB", "HealthyHostCount", "LoadBalancer", local.alb_arn_suffix, { stat = "Average", period = 60 }],
            ["AWS/ApplicationELB", "UnHealthyHostCount", "LoadBalancer", local.alb_arn_suffix, { stat = "Average", period = 60 }],
          ]
          view   = "timeSeries"
          stacked = false
        }
      },
    ]
  })
}
