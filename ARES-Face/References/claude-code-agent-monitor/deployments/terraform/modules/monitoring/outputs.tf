# ─────────────────────────────────────────────────────────────────────────────
# Monitoring module outputs
# ─────────────────────────────────────────────────────────────────────────────

output "sns_topic_arn" {
  description = "ARN of the SNS alert topic"
  value       = aws_sns_topic.alerts.arn
}

output "log_group_name" {
  description = "Name of the CloudWatch log group"
  value       = aws_cloudwatch_log_group.application.name
}

output "log_group_arn" {
  description = "ARN of the CloudWatch log group"
  value       = aws_cloudwatch_log_group.application.arn
}

output "dashboard_name" {
  description = "Name of the CloudWatch dashboard"
  value       = aws_cloudwatch_dashboard.main.dashboard_name
}

output "dashboard_url" {
  description = "URL to the CloudWatch dashboard in the AWS console"
  value       = "https://${var.region}.console.aws.amazon.com/cloudwatch/home?region=${var.region}#dashboards:name=${aws_cloudwatch_dashboard.main.dashboard_name}"
}

output "alarm_arns" {
  description = "ARNs of all configured CloudWatch alarms"
  value = concat(
    [aws_cloudwatch_metric_alarm.high_5xx_rate.arn],
    [aws_cloudwatch_metric_alarm.high_latency.arn],
    [aws_cloudwatch_metric_alarm.efs_burst_credits.arn],
    [aws_cloudwatch_metric_alarm.ecs_high_cpu.arn],
    [aws_cloudwatch_metric_alarm.ecs_high_memory.arn],
    aws_cloudwatch_metric_alarm.unhealthy_hosts[*].arn,
  )
}
