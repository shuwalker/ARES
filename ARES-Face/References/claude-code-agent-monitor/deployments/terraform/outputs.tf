# ─────────────────────────────────────────────────────────────────────────────
# Root module outputs – Claude Code Agent Monitor
# ─────────────────────────────────────────────────────────────────────────────

output "application_url" {
  description = "Public URL of the Claude Code Agent Monitor dashboard"
  value       = module.loadbalancer.application_url
}

output "loadbalancer_dns" {
  description = "DNS name of the application load balancer"
  value       = module.loadbalancer.dns_name
}

output "vpc_id" {
  description = "ID of the provisioned VPC / VNet / VCN"
  value       = module.networking.vpc_id
}

output "private_subnet_ids" {
  description = "IDs of the private subnets hosting compute workloads"
  value       = module.networking.private_subnet_ids
}

output "public_subnet_ids" {
  description = "IDs of the public subnets hosting the load balancer"
  value       = module.networking.public_subnet_ids
}

output "filesystem_id" {
  description = "ID of the persistent file system for SQLite storage"
  value       = module.database.filesystem_id
}

output "blue_service_name" {
  description = "Name of the blue deployment compute service"
  value       = module.compute_blue.service_name
}

output "green_service_name" {
  description = "Name of the green deployment compute service"
  value       = module.compute_green.service_name
}

output "active_slot" {
  description = "Currently active deployment slot"
  value       = var.active_deployment_slot
}

output "monitoring_dashboard_url" {
  description = "URL of the monitoring dashboard (if enabled)"
  value       = var.enable_monitoring ? module.monitoring[0].dashboard_url : "monitoring disabled"
}
