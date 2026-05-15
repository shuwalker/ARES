# ─────────────────────────────────────────────────────────────────────────────
# OCI provider outputs
# ─────────────────────────────────────────────────────────────────────────────

output "application_url" {
  description = "Public URL of the Claude Code Agent Monitor dashboard"
  value       = "http://${oci_load_balancer_load_balancer.main.ip_address_details[0].ip_address}"
}

output "load_balancer_ip" {
  description = "Public IP address of the load balancer"
  value       = oci_load_balancer_load_balancer.main.ip_address_details[0].ip_address
}

output "vcn_id" {
  description = "OCID of the VCN"
  value       = oci_core_vcn.main.id
}

output "blue_instance_id" {
  description = "OCID of the blue container instance"
  value       = oci_container_instances_container_instance.blue.id
}

output "green_instance_id" {
  description = "OCID of the green container instance (if deployed)"
  value       = length(oci_container_instances_container_instance.green) > 0 ? oci_container_instances_container_instance.green[0].id : ""
}

output "file_system_id" {
  description = "OCID of the File Storage file system"
  value       = oci_file_storage_file_system.main.id
}

output "mount_target_ip" {
  description = "IP address of the FSS mount target"
  value       = oci_file_storage_mount_target.main.ip_address
}

output "load_balancer_id" {
  description = "OCID of the load balancer"
  value       = oci_load_balancer_load_balancer.main.id
}

output "compartment_id" {
  description = "OCI compartment OCID"
  value       = var.compartment_id
}

output "region" {
  description = "OCI region"
  value       = var.region
}
