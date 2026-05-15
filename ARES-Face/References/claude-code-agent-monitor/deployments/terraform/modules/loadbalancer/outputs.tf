# ─────────────────────────────────────────────────────────────────────────────
# Load Balancer module outputs
# ─────────────────────────────────────────────────────────────────────────────

output "loadbalancer_arn" {
  description = "ARN of the application load balancer"
  value       = aws_lb.main.arn
}

output "loadbalancer_id" {
  description = "ID of the application load balancer"
  value       = aws_lb.main.id
}

output "dns_name" {
  description = "DNS name of the application load balancer"
  value       = aws_lb.main.dns_name
}

output "zone_id" {
  description = "Route53 zone ID for the load balancer (alias records)"
  value       = aws_lb.main.zone_id
}

output "application_url" {
  description = "Full URL to access the application"
  value       = local.has_tls ? "https://${var.domain_name != "" ? var.domain_name : aws_lb.main.dns_name}" : "http://${aws_lb.main.dns_name}"
}

output "https_listener_arn" {
  description = "ARN of the HTTPS listener (empty if TLS not configured)"
  value       = local.has_tls ? aws_lb_listener.https[0].arn : ""
}

output "http_listener_arn" {
  description = "ARN of the HTTP listener"
  value       = local.has_tls ? aws_lb_listener.http_redirect[0].arn : aws_lb_listener.http_forward[0].arn
}

output "mcp_target_group_arn" {
  description = "ARN of the MCP sidecar target group"
  value       = aws_lb_target_group.mcp.arn
}
