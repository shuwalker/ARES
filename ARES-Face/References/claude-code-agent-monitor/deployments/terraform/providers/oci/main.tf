# ─────────────────────────────────────────────────────────────────────────────
# OCI Provider – Full implementation for Claude Code Agent Monitor
#
# Architecture:
#   VCN → Container Instances (blue/green) → File Storage Service
#       → Flexible Load Balancer → OCI Monitoring & Notifications
#
# OCI Container Instances provide a serverless container runtime.
# File Storage Service (FSS) delivers NFS for SQLite persistence.
# Flexible Load Balancer supports WebSocket, SSL, and weighted backends.
# ─────────────────────────────────────────────────────────────────────────────

provider "oci" {
  region = var.region
}

# ── Data sources ────────────────────────────────────────────────────────────

data "oci_identity_availability_domains" "ads" {
  compartment_id = var.compartment_id
}

data "oci_identity_tenancy" "current" {
  tenancy_id = var.tenancy_id
}

# ── Locals ──────────────────────────────────────────────────────────────────

locals {
  name_prefix = lower(replace("${var.project_name}-${var.environment}", "_", "-"))
  ad_name     = data.oci_identity_availability_domains.ads.availability_domains[0].name

  common_tags = {
    "project"        = var.project_name
    "environment"    = var.environment
    "managed_by"     = "terraform"
    "cloud_provider" = "oci"
    "repository"     = "Claude-Code-Agent-Monitor"
  }
}

# ─────────────────────────────────────────────────────────────────────────────
# VCN (Virtual Cloud Network)
# ─────────────────────────────────────────────────────────────────────────────

resource "oci_core_vcn" "main" {
  compartment_id = var.compartment_id
  cidr_blocks    = [var.vpc_cidr]
  display_name   = "${local.name_prefix}-vcn"
  dns_label      = replace(substr(local.name_prefix, 0, 15), "-", "")

  freeform_tags = local.common_tags

  lifecycle {
    prevent_destroy = false
  }
}

# Internet Gateway
resource "oci_core_internet_gateway" "main" {
  compartment_id = var.compartment_id
  vcn_id         = oci_core_vcn.main.id
  display_name   = "${local.name_prefix}-igw"
  enabled        = true

  freeform_tags = local.common_tags
}

# NAT Gateway
resource "oci_core_nat_gateway" "main" {
  compartment_id = var.compartment_id
  vcn_id         = oci_core_vcn.main.id
  display_name   = "${local.name_prefix}-nat"

  freeform_tags = local.common_tags
}

# Service Gateway
resource "oci_core_service_gateway" "main" {
  compartment_id = var.compartment_id
  vcn_id         = oci_core_vcn.main.id
  display_name   = "${local.name_prefix}-sgw"

  services {
    service_id = data.oci_core_services.all.services[0].id
  }

  freeform_tags = local.common_tags
}

data "oci_core_services" "all" {
  filter {
    name   = "name"
    values = ["All .* Services In Oracle Services Network"]
    regex  = true
  }
}

# ── Route tables ────────────────────────────────────────────────────────────

resource "oci_core_route_table" "public" {
  compartment_id = var.compartment_id
  vcn_id         = oci_core_vcn.main.id
  display_name   = "${local.name_prefix}-public-rt"

  route_rules {
    network_entity_id = oci_core_internet_gateway.main.id
    destination       = "0.0.0.0/0"
    destination_type  = "CIDR_BLOCK"
  }

  freeform_tags = local.common_tags
}

resource "oci_core_route_table" "private" {
  compartment_id = var.compartment_id
  vcn_id         = oci_core_vcn.main.id
  display_name   = "${local.name_prefix}-private-rt"

  route_rules {
    network_entity_id = oci_core_nat_gateway.main.id
    destination       = "0.0.0.0/0"
    destination_type  = "CIDR_BLOCK"
  }

  route_rules {
    network_entity_id = oci_core_service_gateway.main.id
    destination       = data.oci_core_services.all.services[0].cidr_block
    destination_type  = "SERVICE_CIDR_BLOCK"
  }

  freeform_tags = local.common_tags
}

# ── Security lists ──────────────────────────────────────────────────────────

resource "oci_core_security_list" "public" {
  compartment_id = var.compartment_id
  vcn_id         = oci_core_vcn.main.id
  display_name   = "${local.name_prefix}-public-sl"

  ingress_security_rules {
    protocol    = "6" # TCP
    source      = "0.0.0.0/0"
    source_type = "CIDR_BLOCK"
    tcp_options {
      min = 443
      max = 443
    }
  }

  ingress_security_rules {
    protocol    = "6"
    source      = "0.0.0.0/0"
    source_type = "CIDR_BLOCK"
    tcp_options {
      min = 80
      max = 80
    }
  }

  egress_security_rules {
    protocol         = "all"
    destination      = "0.0.0.0/0"
    destination_type = "CIDR_BLOCK"
  }

  freeform_tags = local.common_tags
}

resource "oci_core_security_list" "private" {
  compartment_id = var.compartment_id
  vcn_id         = oci_core_vcn.main.id
  display_name   = "${local.name_prefix}-private-sl"

  ingress_security_rules {
    protocol    = "6"
    source      = var.vpc_cidr
    source_type = "CIDR_BLOCK"
    tcp_options {
      min = var.app_port
      max = var.app_port
    }
  }

  ingress_security_rules {
    protocol    = "6"
    source      = var.vpc_cidr
    source_type = "CIDR_BLOCK"
    tcp_options {
      min = var.mcp_port
      max = var.mcp_port
    }
  }

  # NFS (FSS)
  ingress_security_rules {
    protocol    = "6"
    source      = var.vpc_cidr
    source_type = "CIDR_BLOCK"
    tcp_options {
      min = 2048
      max = 2050
    }
  }

  ingress_security_rules {
    protocol    = "6"
    source      = var.vpc_cidr
    source_type = "CIDR_BLOCK"
    tcp_options {
      min = 111
      max = 111
    }
  }

  ingress_security_rules {
    protocol    = "17" # UDP
    source      = var.vpc_cidr
    source_type = "CIDR_BLOCK"
    udp_options {
      min = 111
      max = 111
    }
  }

  egress_security_rules {
    protocol         = "all"
    destination      = "0.0.0.0/0"
    destination_type = "CIDR_BLOCK"
  }

  freeform_tags = local.common_tags
}

# ── Subnets ─────────────────────────────────────────────────────────────────

resource "oci_core_subnet" "public" {
  compartment_id    = var.compartment_id
  vcn_id            = oci_core_vcn.main.id
  cidr_block        = var.public_subnet_cidrs[0]
  display_name      = "${local.name_prefix}-public"
  dns_label         = "pub"
  route_table_id    = oci_core_route_table.public.id
  security_list_ids = [oci_core_security_list.public.id]

  freeform_tags = local.common_tags
}

resource "oci_core_subnet" "private" {
  compartment_id             = var.compartment_id
  vcn_id                     = oci_core_vcn.main.id
  cidr_block                 = var.private_subnet_cidrs[0]
  display_name               = "${local.name_prefix}-private"
  dns_label                  = "priv"
  route_table_id             = oci_core_route_table.private.id
  security_list_ids          = [oci_core_security_list.private.id]
  prohibit_public_ip_on_vnic = true

  freeform_tags = local.common_tags
}

# ─────────────────────────────────────────────────────────────────────────────
# File Storage Service (FSS) – NFS for SQLite
# ─────────────────────────────────────────────────────────────────────────────

resource "oci_file_storage_file_system" "main" {
  compartment_id      = var.compartment_id
  availability_domain = local.ad_name
  display_name        = "${local.name_prefix}-data"

  freeform_tags = local.common_tags

  lifecycle {
    prevent_destroy = true
  }
}

resource "oci_file_storage_mount_target" "main" {
  compartment_id      = var.compartment_id
  availability_domain = local.ad_name
  subnet_id           = oci_core_subnet.private.id
  display_name        = "${local.name_prefix}-mt"

  freeform_tags = local.common_tags
}

resource "oci_file_storage_export_set" "main" {
  mount_target_id = oci_file_storage_mount_target.main.id
  display_name    = "${local.name_prefix}-exports"
  max_fs_stat_bytes = var.storage_size_gb * 1073741824 # GiB → bytes
}

resource "oci_file_storage_export" "main" {
  export_set_id  = oci_file_storage_export_set.main.id
  file_system_id = oci_file_storage_file_system.main.id
  path           = "/appdata"

  export_options {
    source                         = var.private_subnet_cidrs[0]
    access                         = "READ_WRITE"
    identity_squash                = "NONE"
    require_privileged_source_port = false
  }
}

# ─────────────────────────────────────────────────────────────────────────────
# Container Instances (Blue / Green)
# ─────────────────────────────────────────────────────────────────────────────

resource "oci_container_instances_container_instance" "blue" {
  compartment_id      = var.compartment_id
  availability_domain = local.ad_name
  display_name        = "${local.name_prefix}-blue"

  shape = "CI.Standard.E4.Flex"
  shape_config {
    ocpus         = var.cpu / 1000.0
    memory_in_gbs = var.memory / 1024.0
  }

  vnics {
    subnet_id  = oci_core_subnet.private.id
    is_public_ip_assigned = false
  }

  containers {
    display_name = "app"
    image_url    = var.app_container_image

    environment_variables = var.environment_variables

    health_checks {
      health_check_type = "HTTP"
      port              = var.app_port
      path              = var.health_check_path
      interval_in_seconds = 30
      timeout_in_seconds  = 5
    }

    resource_config {
      vcpus_limit   = var.cpu / 1000.0
      memory_limit_in_gbs = var.memory / 1024.0
    }

    volume_mounts {
      mount_path = "/app/data"
      volume_name = "app-data"
      is_read_only = false
    }
  }

  dynamic "containers" {
    for_each = var.mcp_container_image != "" ? [1] : []
    content {
      display_name = "mcp-sidecar"
      image_url    = var.mcp_container_image

      environment_variables = {
        NODE_ENV = "production"
        MCP_PORT = tostring(var.mcp_port)
      }

      resource_config {
        vcpus_limit         = 0.25
        memory_limit_in_gbs = 0.25
      }
    }
  }

  # NOTE: OCI Container Instances only support EMPTYDIR and CONFIGFILE volume
  # types.  For persistent NFS (FSS) storage, mount via the container entrypoint
  # using the mount target IP from oci_file_storage_mount_target.main, or
  # migrate to OCI Kubernetes Engine (OKE) which supports NFS PersistentVolumes.
  volumes {
    name          = "app-data"
    volume_type   = "EMPTYDIR"
    backing_store = "EPHEMERAL_STORAGE"
  }

  freeform_tags = merge(local.common_tags, {
    deployment_slot = "blue"
  })

  lifecycle {
    ignore_changes = [
      freeform_tags["last_deployed"],
    ]
  }
}

resource "oci_container_instances_container_instance" "green" {
  count = var.active_deployment_slot == "green" || var.green_weight > 0 ? 1 : 0

  compartment_id      = var.compartment_id
  availability_domain = local.ad_name
  display_name        = "${local.name_prefix}-green"

  shape = "CI.Standard.E4.Flex"
  shape_config {
    ocpus         = var.cpu / 1000.0
    memory_in_gbs = var.memory / 1024.0
  }

  vnics {
    subnet_id  = oci_core_subnet.private.id
    is_public_ip_assigned = false
  }

  containers {
    display_name = "app"
    image_url    = var.app_container_image

    environment_variables = var.environment_variables

    health_checks {
      health_check_type = "HTTP"
      port              = var.app_port
      path              = var.health_check_path
      interval_in_seconds = 30
      timeout_in_seconds  = 5
    }

    resource_config {
      vcpus_limit         = var.cpu / 1000.0
      memory_limit_in_gbs = var.memory / 1024.0
    }

    volume_mounts {
      mount_path  = "/app/data"
      volume_name = "app-data"
      is_read_only = false
    }
  }

  # NOTE: OCI Container Instances only support EMPTYDIR and CONFIGFILE volume
  # types.  See blue instance comment for FSS mounting guidance.
  volumes {
    name          = "app-data"
    volume_type   = "EMPTYDIR"
    backing_store = "EPHEMERAL_STORAGE"
  }

  freeform_tags = merge(local.common_tags, {
    deployment_slot = "green"
  })
}

# ─────────────────────────────────────────────────────────────────────────────
# Flexible Load Balancer
# ─────────────────────────────────────────────────────────────────────────────

resource "oci_load_balancer_load_balancer" "main" {
  compartment_id = var.compartment_id
  display_name   = "${local.name_prefix}-lb"
  shape          = "flexible"

  shape_details {
    minimum_bandwidth_in_mbps = var.environment == "production" ? 100 : 10
    maximum_bandwidth_in_mbps = var.environment == "production" ? 1000 : 100
  }

  subnet_ids = [oci_core_subnet.public.id]

  is_private = false

  freeform_tags = local.common_tags

  lifecycle {
    prevent_destroy = false
  }
}

# Backend set with health check
resource "oci_load_balancer_backend_set" "app" {
  load_balancer_id = oci_load_balancer_load_balancer.main.id
  name             = "${local.name_prefix}-app-bs"
  policy           = "ROUND_ROBIN"

  session_persistence_configuration {
    cookie_name      = "CCAM_SESSION"
    is_secure        = true
  }

  health_checker {
    protocol          = "HTTP"
    port              = var.app_port
    url_path          = var.health_check_path
    return_code       = 200
    interval_ms       = var.health_check_interval * 1000
    timeout_in_millis = var.health_check_timeout * 1000
    retries           = var.health_check_unhealthy_threshold
  }
}

# Blue backend
resource "oci_load_balancer_backend" "blue" {
  load_balancer_id = oci_load_balancer_load_balancer.main.id
  backendset_name  = oci_load_balancer_backend_set.app.name
  ip_address       = oci_container_instances_container_instance.blue.vnics[0].private_ip
  port             = var.app_port
  weight           = var.blue_weight
}

# Green backend
resource "oci_load_balancer_backend" "green" {
  count = length(oci_container_instances_container_instance.green) > 0 ? 1 : 0

  load_balancer_id = oci_load_balancer_load_balancer.main.id
  backendset_name  = oci_load_balancer_backend_set.app.name
  ip_address       = oci_container_instances_container_instance.green[0].vnics[0].private_ip
  port             = var.app_port
  weight           = var.green_weight
}

# HTTP listener
resource "oci_load_balancer_listener" "http" {
  load_balancer_id         = oci_load_balancer_load_balancer.main.id
  name                     = "${local.name_prefix}-http"
  default_backend_set_name = oci_load_balancer_backend_set.app.name
  port                     = 80
  protocol                 = "HTTP"

  connection_configuration {
    idle_timeout_in_seconds = 300 # WebSocket support
  }
}

# ─────────────────────────────────────────────────────────────────────────────
# OCI Monitoring – Alarms and Notifications
# ─────────────────────────────────────────────────────────────────────────────

resource "oci_ons_notification_topic" "alerts" {
  count = var.enable_monitoring ? 1 : 0

  compartment_id = var.compartment_id
  name           = "${local.name_prefix}-alerts"

  freeform_tags = local.common_tags
}

resource "oci_ons_subscription" "email" {
  count = var.enable_monitoring && var.alert_email != "" ? 1 : 0

  compartment_id = var.compartment_id
  topic_id       = oci_ons_notification_topic.alerts[0].id
  protocol       = "EMAIL"
  endpoint       = var.alert_email

  freeform_tags = local.common_tags
}

resource "oci_monitoring_alarm" "lb_unhealthy" {
  count = var.enable_monitoring ? 1 : 0

  compartment_id = var.compartment_id
  display_name   = "${local.name_prefix}-unhealthy-backends"
  namespace      = "oci_lbaas"
  query          = "UnHealthyBackendCount[1m]{resourceId = \"${oci_load_balancer_load_balancer.main.id}\"}.max() > 0"
  severity       = "CRITICAL"
  is_enabled     = true
  pending_duration = "PT5M"

  destinations = var.alert_email != "" ? [oci_ons_notification_topic.alerts[0].id] : []

  message_format = "ONS_OPTIMIZED"
  body           = "Unhealthy backends detected for ${local.name_prefix} load balancer"

  freeform_tags = local.common_tags
}

resource "oci_monitoring_alarm" "lb_5xx" {
  count = var.enable_monitoring ? 1 : 0

  compartment_id = var.compartment_id
  display_name   = "${local.name_prefix}-high-5xx"
  namespace      = "oci_lbaas"
  query          = "HttpResponses5xx[1m]{resourceId = \"${oci_load_balancer_load_balancer.main.id}\"}.sum() > 10"
  severity       = "WARNING"
  is_enabled     = true
  pending_duration = "PT5M"

  destinations = var.alert_email != "" ? [oci_ons_notification_topic.alerts[0].id] : []

  freeform_tags = local.common_tags
}

resource "oci_monitoring_alarm" "high_latency" {
  count = var.enable_monitoring ? 1 : 0

  compartment_id = var.compartment_id
  display_name   = "${local.name_prefix}-high-latency"
  namespace      = "oci_lbaas"
  query          = "BackendTimeFirstByte[1m]{resourceId = \"${oci_load_balancer_load_balancer.main.id}\"}.percentile(0.99) > 2000"
  severity       = "WARNING"
  is_enabled     = true
  pending_duration = "PT5M"

  destinations = var.alert_email != "" ? [oci_ons_notification_topic.alerts[0].id] : []

  freeform_tags = local.common_tags
}
