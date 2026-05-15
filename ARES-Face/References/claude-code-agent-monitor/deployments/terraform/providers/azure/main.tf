# ─────────────────────────────────────────────────────────────────────────────
# Azure Provider – Full implementation for Claude Code Agent Monitor
#
# Architecture:
#   VNet → ACI (Container Instances) or AKS → Azure Files → Application
#   Gateway → Azure Monitor → Key Vault
#
# Azure Container Instances is chosen for simplicity; for production at
# scale, AKS is recommended.  Application Gateway provides L7 LB with
# WebSocket support and SSL termination.
# ─────────────────────────────────────────────────────────────────────────────

provider "azurerm" {
  features {
    resource_group {
      prevent_deletion_if_contains_resources = true
    }
    key_vault {
      purge_soft_delete_on_destroy = false
    }
  }
}

# ── Data sources ────────────────────────────────────────────────────────────

data "azurerm_client_config" "current" {}

# ── Locals ──────────────────────────────────────────────────────────────────

locals {
  name_prefix = lower(replace("${var.project_name}-${var.environment}", "_", "-"))

  # Azure resource names (alphanumeric for storage accounts)
  storage_account_name = lower(replace(substr("ccam${var.environment}${substr(md5(var.project_name), 0, 8)}", 0, 24), "-", ""))

  common_tags = merge(
    {
      project        = var.project_name
      environment    = var.environment
      managed_by     = "terraform"
      cloud_provider = "azure"
      repository     = "Claude-Code-Agent-Monitor"
    },
    var.tags,
  )
}

# ─────────────────────────────────────────────────────────────────────────────
# Resource Group
# ─────────────────────────────────────────────────────────────────────────────

resource "azurerm_resource_group" "main" {
  name     = "${local.name_prefix}-rg"
  location = var.region

  tags = local.common_tags

  lifecycle {
    prevent_destroy = false
  }
}

# ─────────────────────────────────────────────────────────────────────────────
# Virtual Network
# ─────────────────────────────────────────────────────────────────────────────

resource "azurerm_virtual_network" "main" {
  name                = "${local.name_prefix}-vnet"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  address_space       = [var.vpc_cidr]

  tags = local.common_tags
}

resource "azurerm_subnet" "public" {
  name                 = "${local.name_prefix}-public"
  resource_group_name  = azurerm_resource_group.main.name
  virtual_network_name = azurerm_virtual_network.main.name
  address_prefixes     = [var.public_subnet_cidrs[0]]
}

resource "azurerm_subnet" "private" {
  name                 = "${local.name_prefix}-private"
  resource_group_name  = azurerm_resource_group.main.name
  virtual_network_name = azurerm_virtual_network.main.name
  address_prefixes     = [var.private_subnet_cidrs[0]]

  delegation {
    name = "aci-delegation"
    service_delegation {
      name    = "Microsoft.ContainerInstance/containerGroups"
      actions = ["Microsoft.Network/virtualNetworks/subnets/action"]
    }
  }
}

resource "azurerm_subnet" "appgw" {
  name                 = "${local.name_prefix}-appgw"
  resource_group_name  = azurerm_resource_group.main.name
  virtual_network_name = azurerm_virtual_network.main.name
  address_prefixes     = ["10.0.100.0/24"]
}

# NSG for private subnet
resource "azurerm_network_security_group" "private" {
  name                = "${local.name_prefix}-private-nsg"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name

  security_rule {
    name                       = "allow-app-port"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = tostring(var.app_port)
    source_address_prefix      = var.vpc_cidr
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "allow-mcp-port"
    priority                   = 110
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = tostring(var.mcp_port)
    source_address_prefix      = var.vpc_cidr
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "allow-smb"
    priority                   = 120
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "445"
    source_address_prefix      = var.vpc_cidr
    destination_address_prefix = "*"
  }

  tags = local.common_tags
}

resource "azurerm_subnet_network_security_group_association" "private" {
  subnet_id                 = azurerm_subnet.private.id
  network_security_group_id = azurerm_network_security_group.private.id
}

# ─────────────────────────────────────────────────────────────────────────────
# Azure Files (persistent storage for SQLite)
# ─────────────────────────────────────────────────────────────────────────────

resource "azurerm_storage_account" "main" {
  name                     = local.storage_account_name
  resource_group_name      = azurerm_resource_group.main.name
  location                 = azurerm_resource_group.main.location
  account_tier             = var.environment == "production" ? "Premium" : "Standard"
  account_replication_type = var.environment == "production" ? "ZRS" : "LRS"
  account_kind             = var.environment == "production" ? "FileStorage" : "StorageV2"

  min_tls_version = "TLS1_2"

  network_rules {
    default_action             = "Deny"
    virtual_network_subnet_ids = [azurerm_subnet.private.id]
  }

  tags = local.common_tags

  lifecycle {
    prevent_destroy = true
  }
}

resource "azurerm_storage_share" "appdata" {
  name                 = "appdata"
  storage_account_name = azurerm_storage_account.main.name
  quota                = var.storage_size_gb
  access_tier          = var.environment == "production" ? "Premium" : "Hot"
}

# ─────────────────────────────────────────────────────────────────────────────
# Key Vault (for secrets management)
# ─────────────────────────────────────────────────────────────────────────────

resource "azurerm_key_vault" "main" {
  name                     = substr("${local.name_prefix}-kv", 0, 24)
  location                 = azurerm_resource_group.main.location
  resource_group_name      = azurerm_resource_group.main.name
  tenant_id                = data.azurerm_client_config.current.tenant_id
  sku_name                 = "standard"
  purge_protection_enabled = var.environment == "production"

  access_policy {
    tenant_id = data.azurerm_client_config.current.tenant_id
    object_id = data.azurerm_client_config.current.object_id

    secret_permissions = [
      "Get", "List", "Set", "Delete", "Purge",
    ]
  }

  tags = local.common_tags
}

# ─────────────────────────────────────────────────────────────────────────────
# Container Instances (Blue / Green)
# ─────────────────────────────────────────────────────────────────────────────

resource "azurerm_container_group" "blue" {
  name                = "${local.name_prefix}-blue"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  os_type             = "Linux"
  ip_address_type     = "Private"
  subnet_ids          = [azurerm_subnet.private.id]
  restart_policy      = "Always"

  container {
    name   = "app"
    image  = var.app_container_image
    cpu    = var.cpu / 1000.0
    memory = var.memory / 1024.0

    ports {
      port     = var.app_port
      protocol = "TCP"
    }

    dynamic "environment_variables" {
      for_each = var.environment_variables
      content {
        name  = environment_variables.key
        value = environment_variables.value
      }
    }

    volume {
      name                 = "app-data"
      mount_path           = "/app/data"
      read_only            = false
      storage_account_name = azurerm_storage_account.main.name
      storage_account_key  = azurerm_storage_account.main.primary_access_key
      share_name           = azurerm_storage_share.appdata.name
    }

    liveness_probe {
      http_get {
        path   = var.health_check_path
        port   = var.app_port
        scheme = "Http"
      }
      initial_delay_seconds = 30
      period_seconds        = 30
      failure_threshold     = 3
    }

    readiness_probe {
      http_get {
        path   = var.health_check_path
        port   = var.app_port
        scheme = "Http"
      }
      initial_delay_seconds = 10
      period_seconds        = 10
      failure_threshold     = 3
    }
  }

  dynamic "container" {
    for_each = var.mcp_container_image != "" ? [1] : []
    content {
      name   = "mcp-sidecar"
      image  = var.mcp_container_image
      cpu    = 0.25
      memory = 0.25

      ports {
        port     = var.mcp_port
        protocol = "TCP"
      }

      environment_variables = {
        NODE_ENV = "production"
        MCP_PORT = tostring(var.mcp_port)
      }
    }
  }

  tags = merge(local.common_tags, {
    deployment_slot = "blue"
  })

  lifecycle {
    ignore_changes = [
      tags["last_deployed"],
    ]
  }
}

resource "azurerm_container_group" "green" {
  count = var.active_deployment_slot == "green" || var.green_weight > 0 ? 1 : 0

  name                = "${local.name_prefix}-green"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  os_type             = "Linux"
  ip_address_type     = "Private"
  subnet_ids          = [azurerm_subnet.private.id]
  restart_policy      = "Always"

  container {
    name   = "app"
    image  = var.app_container_image
    cpu    = var.cpu / 1000.0
    memory = var.memory / 1024.0

    ports {
      port     = var.app_port
      protocol = "TCP"
    }

    dynamic "environment_variables" {
      for_each = var.environment_variables
      content {
        name  = environment_variables.key
        value = environment_variables.value
      }
    }

    volume {
      name                 = "app-data"
      mount_path           = "/app/data"
      read_only            = false
      storage_account_name = azurerm_storage_account.main.name
      storage_account_key  = azurerm_storage_account.main.primary_access_key
      share_name           = azurerm_storage_share.appdata.name
    }

    liveness_probe {
      http_get {
        path   = var.health_check_path
        port   = var.app_port
        scheme = "Http"
      }
      initial_delay_seconds = 30
      period_seconds        = 30
      failure_threshold     = 3
    }
  }

  tags = merge(local.common_tags, {
    deployment_slot = "green"
  })
}

# ─────────────────────────────────────────────────────────────────────────────
# Application Gateway (L7 load balancer with WebSocket + SSL)
# ─────────────────────────────────────────────────────────────────────────────

resource "azurerm_public_ip" "appgw" {
  name                = "${local.name_prefix}-appgw-pip"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  allocation_method   = "Static"
  sku                 = "Standard"

  tags = local.common_tags
}

resource "azurerm_application_gateway" "main" {
  name                = "${local.name_prefix}-appgw"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  enable_http2        = true

  sku {
    name     = var.environment == "production" ? "WAF_v2" : "Standard_v2"
    tier     = var.environment == "production" ? "WAF_v2" : "Standard_v2"
    capacity = var.environment == "production" ? 2 : 1
  }

  gateway_ip_configuration {
    name      = "gateway-ip"
    subnet_id = azurerm_subnet.appgw.id
  }

  frontend_ip_configuration {
    name                 = "frontend-ip"
    public_ip_address_id = azurerm_public_ip.appgw.id
  }

  frontend_port {
    name = "http"
    port = 80
  }

  frontend_port {
    name = "https"
    port = 443
  }

  # Blue backend pool
  backend_address_pool {
    name         = "blue-pool"
    ip_addresses = [azurerm_container_group.blue.ip_address]
  }

  # Green backend pool
  dynamic "backend_address_pool" {
    for_each = length(azurerm_container_group.green) > 0 ? [1] : []
    content {
      name         = "green-pool"
      ip_addresses = [azurerm_container_group.green[0].ip_address]
    }
  }

  backend_http_settings {
    name                                = "app-settings"
    cookie_based_affinity               = "Enabled"
    port                                = var.app_port
    protocol                            = "Http"
    request_timeout                     = 300 # WebSocket support
    pick_host_name_from_backend_address = false

    connection_draining {
      enabled           = true
      drain_timeout_sec = 60
    }

    probe_name = "app-health"
  }

  probe {
    name                = "app-health"
    protocol            = "Http"
    path                = var.health_check_path
    host                = "127.0.0.1"
    interval            = var.health_check_interval
    timeout             = var.health_check_timeout
    unhealthy_threshold = var.health_check_unhealthy_threshold

    match {
      status_code = ["200"]
    }
  }

  # HTTP listener
  http_listener {
    name                           = "http-listener"
    frontend_ip_configuration_name = "frontend-ip"
    frontend_port_name             = "http"
    protocol                       = "Http"
  }

  # Routing rule – HTTP to blue pool
  request_routing_rule {
    name                       = "http-routing"
    priority                   = 100
    rule_type                  = "Basic"
    http_listener_name         = "http-listener"
    backend_address_pool_name  = var.active_deployment_slot == "blue" ? "blue-pool" : "green-pool"
    backend_http_settings_name = "app-settings"
  }

  tags = local.common_tags

  lifecycle {
    prevent_destroy = false
    ignore_changes = [
      tags["last_deployed"],
    ]
  }
}

# ─────────────────────────────────────────────────────────────────────────────
# Azure Monitor (alerts and diagnostics)
# ─────────────────────────────────────────────────────────────────────────────

resource "azurerm_monitor_action_group" "main" {
  count = var.enable_monitoring ? 1 : 0

  name                = "${local.name_prefix}-alerts"
  resource_group_name = azurerm_resource_group.main.name
  short_name          = substr(local.name_prefix, 0, 12)

  dynamic "email_receiver" {
    for_each = var.alert_email != "" ? [1] : []
    content {
      name          = "email-alert"
      email_address = var.alert_email
    }
  }

  tags = local.common_tags
}

resource "azurerm_monitor_metric_alert" "appgw_unhealthy" {
  count = var.enable_monitoring ? 1 : 0

  name                = "${local.name_prefix}-unhealthy-backend"
  resource_group_name = azurerm_resource_group.main.name
  scopes              = [azurerm_application_gateway.main.id]
  description         = "Alert when backend health drops below threshold"
  severity            = 1

  criteria {
    metric_namespace = "Microsoft.Network/applicationGateways"
    metric_name      = "UnhealthyHostCount"
    aggregation      = "Average"
    operator         = "GreaterThan"
    threshold        = 0
  }

  action {
    action_group_id = azurerm_monitor_action_group.main[0].id
  }

  tags = local.common_tags
}

resource "azurerm_monitor_metric_alert" "appgw_5xx" {
  count = var.enable_monitoring ? 1 : 0

  name                = "${local.name_prefix}-high-5xx"
  resource_group_name = azurerm_resource_group.main.name
  scopes              = [azurerm_application_gateway.main.id]
  description         = "High 5xx error rate on Application Gateway"
  severity            = 2

  criteria {
    metric_namespace = "Microsoft.Network/applicationGateways"
    metric_name      = "ResponseStatus"
    aggregation      = "Count"
    operator         = "GreaterThan"
    threshold        = 10

    dimension {
      name     = "HttpStatusGroup"
      operator = "Include"
      values   = ["5xx"]
    }
  }

  action {
    action_group_id = azurerm_monitor_action_group.main[0].id
  }

  tags = local.common_tags
}

resource "azurerm_monitor_metric_alert" "appgw_latency" {
  count = var.enable_monitoring ? 1 : 0

  name                = "${local.name_prefix}-high-latency"
  resource_group_name = azurerm_resource_group.main.name
  scopes              = [azurerm_application_gateway.main.id]
  description         = "High backend response latency"
  severity            = 2

  criteria {
    metric_namespace = "Microsoft.Network/applicationGateways"
    metric_name      = "BackendLastByteResponseTime"
    aggregation      = "Average"
    operator         = "GreaterThan"
    threshold        = 2000 # ms
  }

  action {
    action_group_id = azurerm_monitor_action_group.main[0].id
  }

  tags = local.common_tags
}

# Log Analytics Workspace
resource "azurerm_log_analytics_workspace" "main" {
  count = var.enable_monitoring ? 1 : 0

  name                = "${local.name_prefix}-logs"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  sku                 = "PerGB2018"
  retention_in_days   = var.log_retention_days

  tags = local.common_tags
}

# Diagnostic settings for App Gateway
resource "azurerm_monitor_diagnostic_setting" "appgw" {
  count = var.enable_monitoring ? 1 : 0

  name                       = "${local.name_prefix}-appgw-diag"
  target_resource_id         = azurerm_application_gateway.main.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.main[0].id

  enabled_log {
    category = "ApplicationGatewayAccessLog"
  }

  enabled_log {
    category = "ApplicationGatewayPerformanceLog"
  }

  metric {
    category = "AllMetrics"
    enabled  = true
  }
}
