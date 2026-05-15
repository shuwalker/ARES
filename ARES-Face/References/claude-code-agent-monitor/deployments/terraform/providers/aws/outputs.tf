# ─────────────────────────────────────────────────────────────────────────────
# AWS provider outputs
# ─────────────────────────────────────────────────────────────────────────────

output "application_url" {
  description = "Public URL of the Claude Code Agent Monitor dashboard"
  value       = module.loadbalancer.application_url
}

output "alb_dns_name" {
  description = "DNS name of the Application Load Balancer"
  value       = module.loadbalancer.dns_name
}

output "vpc_id" {
  description = "ID of the VPC"
  value       = module.networking.vpc_id
}

output "ecs_cluster_name" {
  description = "Name of the ECS cluster"
  value       = module.compute_blue.cluster_name
}

output "blue_service_name" {
  description = "Name of the blue ECS service"
  value       = module.compute_blue.service_name
}

output "green_service_name" {
  description = "Name of the green ECS service"
  value       = module.compute_green.service_name
}

output "efs_filesystem_id" {
  description = "ID of the EFS file system"
  value       = module.database.filesystem_id
}

output "acm_certificate_arn" {
  description = "ARN of the ACM certificate (if auto-created)"
  value       = length(aws_acm_certificate.main) > 0 ? aws_acm_certificate.main[0].arn : var.tls_certificate_arn
}

output "monitoring_dashboard_url" {
  description = "CloudWatch dashboard URL"
  value       = var.enable_monitoring ? module.monitoring[0].dashboard_url : "monitoring disabled"
}

output "account_id" {
  description = "AWS account ID"
  value       = data.aws_caller_identity.current.account_id
}

output "region" {
  description = "AWS region"
  value       = data.aws_region.current.name
}
