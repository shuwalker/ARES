# ─────────────────────────────────────────────────────────────────────────────
# Compute module outputs
# ─────────────────────────────────────────────────────────────────────────────

output "cluster_name" {
  description = "Name of the ECS cluster"
  value       = aws_ecs_cluster.main.name
}

output "cluster_arn" {
  description = "ARN of the ECS cluster"
  value       = aws_ecs_cluster.main.arn
}

output "service_name" {
  description = "Name of the ECS service for this slot"
  value       = aws_ecs_service.app.name
}

output "service_arn" {
  description = "ARN of the ECS service for this slot"
  value       = aws_ecs_service.app.id
}

output "task_definition_arn" {
  description = "ARN of the current task definition"
  value       = aws_ecs_task_definition.app.arn
}

output "target_group_arn" {
  description = "ARN of the target group for LB registration"
  value       = aws_lb_target_group.app.arn
}

output "target_group_name" {
  description = "Name of the target group"
  value       = aws_lb_target_group.app.name
}

output "log_group_name" {
  description = "CloudWatch log group name"
  value       = aws_cloudwatch_log_group.app.name
}

output "task_execution_role_arn" {
  description = "ARN of the task execution IAM role"
  value       = aws_iam_role.task_execution.arn
}

output "task_role_arn" {
  description = "ARN of the task IAM role"
  value       = aws_iam_role.task.arn
}
