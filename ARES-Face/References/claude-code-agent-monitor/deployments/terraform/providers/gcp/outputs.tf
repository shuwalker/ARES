# ─────────────────────────────────────────────────────────────────────────────
# GCP provider outputs
# ─────────────────────────────────────────────────────────────────────────────

output "application_url" {
  description = "Public URL of the Claude Code Agent Monitor dashboard"
  value       = var.domain_name != "" ? "https://${var.domain_name}" : "http://${google_compute_global_forwarding_rule.http.ip_address}"
}

output "load_balancer_ip" {
  description = "External IP address of the load balancer"
  value       = google_compute_global_forwarding_rule.http.ip_address
}

output "blue_service_url" {
  description = "URL of the blue Cloud Run service"
  value       = google_cloud_run_v2_service.blue.uri
}

output "green_service_url" {
  description = "URL of the green Cloud Run service"
  value       = google_cloud_run_v2_service.green.uri
}

output "vpc_id" {
  description = "Self-link of the VPC network"
  value       = google_compute_network.main.self_link
}

output "filestore_ip" {
  description = "IP address of the Filestore instance"
  value       = google_filestore_instance.main.networks[0].ip_addresses[0]
}

output "filestore_share" {
  description = "Filestore share name"
  value       = google_filestore_instance.main.file_shares[0].name
}

output "monitoring_dashboard_url" {
  description = "Cloud Monitoring dashboard URL"
  value       = var.enable_monitoring ? "https://console.cloud.google.com/monitoring/dashboards?project=${var.gcp_project_id}" : "monitoring disabled"
}

output "project_id" {
  description = "GCP project ID"
  value       = var.gcp_project_id
}

output "region" {
  description = "GCP region"
  value       = var.region
}
