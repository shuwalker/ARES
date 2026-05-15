# ─────────────────────────────────────────────────────────────────────────────
# Database module outputs
# ─────────────────────────────────────────────────────────────────────────────

output "filesystem_id" {
  description = "ID of the EFS file system"
  value       = aws_efs_file_system.main.id
}

output "filesystem_arn" {
  description = "ARN of the EFS file system"
  value       = aws_efs_file_system.main.arn
}

output "filesystem_dns_name" {
  description = "DNS name of the EFS file system"
  value       = aws_efs_file_system.main.dns_name
}

output "mount_target_ids" {
  description = "IDs of the EFS mount targets"
  value       = aws_efs_mount_target.main[*].id
}

output "mount_target_ips" {
  description = "IP addresses of the EFS mount targets"
  value       = aws_efs_mount_target.main[*].ip_address
}

output "access_point_id" {
  description = "ID of the EFS access point for /app/data"
  value       = aws_efs_access_point.app_data.id
}

output "access_point_arn" {
  description = "ARN of the EFS access point"
  value       = aws_efs_access_point.app_data.arn
}
