# ─────────────────────────────────────────────────────────────────────────────
# Azure provider outputs
# ─────────────────────────────────────────────────────────────────────────────

output "application_url" {
  description = "Public URL of the Claude Code Agent Monitor dashboard"
  value       = "http://${azurerm_public_ip.appgw.ip_address}"
}

output "public_ip" {
  description = "Public IP address of the Application Gateway"
  value       = azurerm_public_ip.appgw.ip_address
}

output "resource_group_name" {
  description = "Name of the Azure resource group"
  value       = azurerm_resource_group.main.name
}

output "vnet_id" {
  description = "ID of the Virtual Network"
  value       = azurerm_virtual_network.main.id
}

output "blue_container_group_id" {
  description = "ID of the blue container group"
  value       = azurerm_container_group.blue.id
}

output "green_container_group_id" {
  description = "ID of the green container group (if deployed)"
  value       = length(azurerm_container_group.green) > 0 ? azurerm_container_group.green[0].id : ""
}

output "storage_account_name" {
  description = "Name of the Azure Storage Account"
  value       = azurerm_storage_account.main.name
}

output "key_vault_uri" {
  description = "URI of the Azure Key Vault"
  value       = azurerm_key_vault.main.vault_uri
}

output "app_gateway_id" {
  description = "ID of the Application Gateway"
  value       = azurerm_application_gateway.main.id
}

output "log_analytics_workspace_id" {
  description = "ID of the Log Analytics workspace (if monitoring enabled)"
  value       = var.enable_monitoring ? azurerm_log_analytics_workspace.main[0].id : ""
}

output "region" {
  description = "Azure region"
  value       = var.region
}
