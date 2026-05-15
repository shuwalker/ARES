# ─────────────────────────────────────────────────────────────────────────────
# GCP Provider – Full implementation for Claude Code Agent Monitor
#
# Architecture:
#   VPC → Cloud Run (blue/green) → Filestore → Cloud Load Balancer
#        → Cloud Monitoring → Managed SSL Certificate
#
# Cloud Run is chosen over GKE for cost efficiency and operational simplicity
# for this containerised workload.  Filestore provides NFS for SQLite.
# ─────────────────────────────────────────────────────────────────────────────

provider "google" {
  project = var.gcp_project_id
  region  = var.region
}

provider "google-beta" {
  project = var.gcp_project_id
  region  = var.region
}

# ── Locals ──────────────────────────────────────────────────────────────────

locals {
  name_prefix = lower(replace("${var.project_name}-${var.environment}", "_", "-"))

  common_labels = merge(
    {
      project        = replace(var.project_name, "-", "_")
      environment    = var.environment
      managed_by     = "terraform"
      cloud_provider = "gcp"
    },
    { for k, v in var.tags : replace(k, "-", "_") => replace(v, "-", "_") },
  )
}

# ── Enable required APIs ───────────────────────────────────────────────────

resource "google_project_service" "apis" {
  for_each = toset([
    "run.googleapis.com",
    "compute.googleapis.com",
    "file.googleapis.com",
    "vpcaccess.googleapis.com",
    "monitoring.googleapis.com",
    "logging.googleapis.com",
    "certificatemanager.googleapis.com",
  ])

  service            = each.value
  disable_on_destroy = false
}

# ─────────────────────────────────────────────────────────────────────────────
# VPC Network
# ─────────────────────────────────────────────────────────────────────────────

resource "google_compute_network" "main" {
  name                    = "${local.name_prefix}-vpc"
  auto_create_subnetworks = false

  depends_on = [google_project_service.apis]
}

resource "google_compute_subnetwork" "private" {
  name          = "${local.name_prefix}-private"
  ip_cidr_range = var.private_subnet_cidrs[0]
  region        = var.region
  network       = google_compute_network.main.id

  private_ip_google_access = true

  log_config {
    aggregation_interval = "INTERVAL_5_SEC"
    flow_sampling        = 0.5
  }
}

resource "google_compute_subnetwork" "proxy" {
  name          = "${local.name_prefix}-proxy"
  ip_cidr_range = "10.0.100.0/24"
  region        = var.region
  network       = google_compute_network.main.id
  purpose       = "REGIONAL_MANAGED_PROXY"
  role          = "ACTIVE"
}

# Cloud NAT for outbound internet
resource "google_compute_router" "main" {
  name    = "${local.name_prefix}-router"
  region  = var.region
  network = google_compute_network.main.id
}

resource "google_compute_router_nat" "main" {
  name                               = "${local.name_prefix}-nat"
  router                             = google_compute_router.main.name
  region                             = var.region
  nat_ip_allocate_option             = "AUTO_ONLY"
  source_subnetwork_ip_ranges_to_nat = "ALL_SUBNETWORKS_ALL_IP_RANGES"

  log_config {
    enable = true
    filter = "ERRORS_ONLY"
  }
}

# VPC Connector for Cloud Run → Filestore
resource "google_vpc_access_connector" "main" {
  name          = "${local.name_prefix}-conn"
  region        = var.region
  network       = google_compute_network.main.id
  ip_cidr_range = "10.0.200.0/28"
  min_instances = 2
  max_instances = var.environment == "production" ? 10 : 3

  depends_on = [google_project_service.apis]
}

# Firewall rules
resource "google_compute_firewall" "allow_health_checks" {
  name    = "${local.name_prefix}-allow-health-checks"
  network = google_compute_network.main.id

  allow {
    protocol = "tcp"
    ports    = [tostring(var.app_port), tostring(var.mcp_port)]
  }

  source_ranges = ["130.211.0.0/22", "35.191.0.0/16"] # GCP health check ranges
  target_tags   = ["${local.name_prefix}-app"]
}

resource "google_compute_firewall" "allow_internal" {
  name    = "${local.name_prefix}-allow-internal"
  network = google_compute_network.main.id

  allow {
    protocol = "tcp"
    ports    = [tostring(var.app_port), tostring(var.mcp_port), "2049"]
  }

  source_ranges = [var.vpc_cidr]
}

# ─────────────────────────────────────────────────────────────────────────────
# Filestore (NFS for SQLite persistence)
# ─────────────────────────────────────────────────────────────────────────────

resource "google_filestore_instance" "main" {
  name     = "${local.name_prefix}-data"
  location = "${var.region}-b"
  tier     = var.environment == "production" ? "BASIC_SSD" : "BASIC_HDD"

  file_shares {
    name       = "appdata"
    capacity_gb = var.storage_size_gb
  }

  networks {
    network = google_compute_network.main.name
    modes   = ["MODE_IPV4"]
  }

  labels = local.common_labels

  depends_on = [google_project_service.apis]

  lifecycle {
    prevent_destroy = true
  }
}

# ─────────────────────────────────────────────────────────────────────────────
# Cloud Run services (Blue / Green)
# ─────────────────────────────────────────────────────────────────────────────

resource "google_cloud_run_v2_service" "blue" {
  name     = "${local.name_prefix}-blue"
  location = var.region
  ingress  = "INGRESS_TRAFFIC_INTERNAL_LOAD_BALANCER"

  template {
    scaling {
      min_instance_count = var.active_deployment_slot == "blue" ? var.min_replicas : 0
      max_instance_count = var.active_deployment_slot == "blue" ? var.max_replicas : 1
    }

    vpc_access {
      connector = google_vpc_access_connector.main.id
      egress    = "ALL_TRAFFIC"
    }

    containers {
      image = var.app_container_image
      name  = "app"

      ports {
        container_port = var.app_port
      }

      resources {
        limits = {
          cpu    = "${var.cpu}m"
          memory = "${var.memory}Mi"
        }
      }

      dynamic "env" {
        for_each = var.environment_variables
        content {
          name  = env.key
          value = env.value
        }
      }

      env {
        name  = "FILESTORE_IP"
        value = google_filestore_instance.main.networks[0].ip_addresses[0]
      }

      startup_probe {
        http_get {
          path = var.health_check_path
          port = var.app_port
        }
        initial_delay_seconds = 10
        period_seconds        = 10
        failure_threshold     = 5
      }

      liveness_probe {
        http_get {
          path = var.health_check_path
          port = var.app_port
        }
        period_seconds    = 30
        failure_threshold = 3
      }

      volume_mounts {
        name       = "app-data"
        mount_path = "/app/data"
      }
    }

    dynamic "containers" {
      for_each = var.mcp_container_image != "" ? [1] : []
      content {
        image = var.mcp_container_image
        name  = "mcp-sidecar"

        ports {
          container_port = var.mcp_port
        }

        resources {
          limits = {
            cpu    = "250m"
            memory = "256Mi"
          }
        }

        env {
          name  = "NODE_ENV"
          value = "production"
        }
      }
    }

    volumes {
      name = "app-data"
      nfs {
        server    = google_filestore_instance.main.networks[0].ip_addresses[0]
        path      = "/appdata"
        read_only = false
      }
    }

    session_affinity = true
    timeout          = "300s"
  }

  labels = local.common_labels

  depends_on = [google_project_service.apis]

  lifecycle {
    ignore_changes = [
      client,
      client_version,
    ]
  }
}

resource "google_cloud_run_v2_service" "green" {
  name     = "${local.name_prefix}-green"
  location = var.region
  ingress  = "INGRESS_TRAFFIC_INTERNAL_LOAD_BALANCER"

  template {
    scaling {
      min_instance_count = var.active_deployment_slot == "green" ? var.min_replicas : 0
      max_instance_count = var.active_deployment_slot == "green" ? var.max_replicas : 1
    }

    vpc_access {
      connector = google_vpc_access_connector.main.id
      egress    = "ALL_TRAFFIC"
    }

    containers {
      image = var.app_container_image
      name  = "app"

      ports {
        container_port = var.app_port
      }

      resources {
        limits = {
          cpu    = "${var.cpu}m"
          memory = "${var.memory}Mi"
        }
      }

      dynamic "env" {
        for_each = var.environment_variables
        content {
          name  = env.key
          value = env.value
        }
      }

      env {
        name  = "FILESTORE_IP"
        value = google_filestore_instance.main.networks[0].ip_addresses[0]
      }

      startup_probe {
        http_get {
          path = var.health_check_path
          port = var.app_port
        }
        initial_delay_seconds = 10
        period_seconds        = 10
        failure_threshold     = 5
      }

      liveness_probe {
        http_get {
          path = var.health_check_path
          port = var.app_port
        }
        period_seconds    = 30
        failure_threshold = 3
      }

      volume_mounts {
        name       = "app-data"
        mount_path = "/app/data"
      }
    }

    volumes {
      name = "app-data"
      nfs {
        server    = google_filestore_instance.main.networks[0].ip_addresses[0]
        path      = "/appdata"
        read_only = false
      }
    }

    session_affinity = true
    timeout          = "300s"
  }

  labels = local.common_labels

  depends_on = [google_project_service.apis]

  lifecycle {
    ignore_changes = [
      client,
      client_version,
    ]
  }
}

# IAM – restrict access to load balancer service account only
# Cloud Run ingress is set to INGRESS_TRAFFIC_INTERNAL_LOAD_BALANCER,
# so public IAM bindings are not needed. The LB routes traffic internally.
# To grant specific service account access, replace with:
#   member = "serviceAccount:<your-lb-service-account>@<project>.iam.gserviceaccount.com"
#
# resource "google_cloud_run_v2_service_iam_member" "blue_invoker" {
#   name     = google_cloud_run_v2_service.blue.name
#   location = var.region
#   role     = "roles/run.invoker"
#   member   = "serviceAccount:${var.project_id}-compute@developer.gserviceaccount.com"
# }
#
# resource "google_cloud_run_v2_service_iam_member" "green_invoker" {
#   name     = google_cloud_run_v2_service.green.name
#   location = var.region
#   role     = "roles/run.invoker"
#   member   = "serviceAccount:${var.project_id}-compute@developer.gserviceaccount.com"
# }

# ─────────────────────────────────────────────────────────────────────────────
# External Application Load Balancer
# ─────────────────────────────────────────────────────────────────────────────

# Serverless NEGs for Cloud Run
resource "google_compute_region_network_endpoint_group" "blue" {
  name                  = "${local.name_prefix}-blue-neg"
  region                = var.region
  network_endpoint_type = "SERVERLESS"

  cloud_run {
    service = google_cloud_run_v2_service.blue.name
  }
}

resource "google_compute_region_network_endpoint_group" "green" {
  name                  = "${local.name_prefix}-green-neg"
  region                = var.region
  network_endpoint_type = "SERVERLESS"

  cloud_run {
    service = google_cloud_run_v2_service.green.name
  }
}

# Backend service with weighted backends for blue/green
resource "google_compute_backend_service" "main" {
  name                  = "${local.name_prefix}-backend"
  protocol              = "HTTP"
  load_balancing_scheme = "EXTERNAL_MANAGED"
  timeout_sec           = 300 # WebSocket support

  session_affinity = "GENERATED_COOKIE"

  backend {
    group = google_compute_region_network_endpoint_group.blue.id
    capacity_scaler = var.blue_weight / 100
  }

  backend {
    group = google_compute_region_network_endpoint_group.green.id
    capacity_scaler = var.green_weight / 100
  }

  health_checks = [google_compute_health_check.main.id]

  log_config {
    enable      = true
    sample_rate = 1.0
  }
}

resource "google_compute_health_check" "main" {
  name = "${local.name_prefix}-hc"

  http_health_check {
    port         = var.app_port
    request_path = var.health_check_path
  }

  check_interval_sec  = var.health_check_interval
  timeout_sec         = var.health_check_timeout
  healthy_threshold   = var.health_check_healthy_threshold
  unhealthy_threshold = var.health_check_unhealthy_threshold
}

# URL map
resource "google_compute_url_map" "main" {
  name            = "${local.name_prefix}-urlmap"
  default_service = google_compute_backend_service.main.id
}

# Managed SSL certificate (optional)
resource "google_compute_managed_ssl_certificate" "main" {
  count = var.domain_name != "" ? 1 : 0

  name = "${local.name_prefix}-cert"

  managed {
    domains = [var.domain_name]
  }
}

# HTTPS proxy
resource "google_compute_target_https_proxy" "main" {
  count = var.domain_name != "" ? 1 : 0

  name             = "${local.name_prefix}-https-proxy"
  url_map          = google_compute_url_map.main.id
  ssl_certificates = [google_compute_managed_ssl_certificate.main[0].id]
}

# HTTP proxy (for redirect or direct access)
resource "google_compute_target_http_proxy" "main" {
  name    = "${local.name_prefix}-http-proxy"
  url_map = google_compute_url_map.main.id
}

# Global forwarding rules
resource "google_compute_global_forwarding_rule" "https" {
  count = var.domain_name != "" ? 1 : 0

  name                  = "${local.name_prefix}-https"
  target                = google_compute_target_https_proxy.main[0].id
  port_range            = "443"
  ip_protocol           = "TCP"
  load_balancing_scheme = "EXTERNAL_MANAGED"
}

resource "google_compute_global_forwarding_rule" "http" {
  name                  = "${local.name_prefix}-http"
  target                = google_compute_target_http_proxy.main.id
  port_range            = "80"
  ip_protocol           = "TCP"
  load_balancing_scheme = "EXTERNAL_MANAGED"
}

# ─────────────────────────────────────────────────────────────────────────────
# Cloud Monitoring – Alert policies
# ─────────────────────────────────────────────────────────────────────────────

resource "google_monitoring_notification_channel" "email" {
  count = var.alert_email != "" ? 1 : 0

  display_name = "${local.name_prefix}-email"
  type         = "email"

  labels = {
    email_address = var.alert_email
  }
}

resource "google_monitoring_alert_policy" "high_latency" {
  count = var.enable_monitoring ? 1 : 0

  display_name = "${local.name_prefix}-high-latency"
  combiner     = "OR"

  conditions {
    display_name = "Cloud Run request latency > 2s"

    condition_threshold {
      filter     = "resource.type=\"cloud_run_revision\" AND metric.type=\"run.googleapis.com/request_latencies\""
      comparison = "COMPARISON_GT"
      duration   = "300s"

      threshold_value = 2000 # ms

      aggregations {
        alignment_period   = "60s"
        per_series_aligner = "ALIGN_PERCENTILE_99"
      }
    }
  }

  notification_channels = var.alert_email != "" ? [google_monitoring_notification_channel.email[0].id] : []

  alert_strategy {
    auto_close = "604800s"
  }
}

resource "google_monitoring_alert_policy" "high_error_rate" {
  count = var.enable_monitoring ? 1 : 0

  display_name = "${local.name_prefix}-high-error-rate"
  combiner     = "OR"

  conditions {
    display_name = "Cloud Run 5xx error rate"

    condition_threshold {
      filter     = "resource.type=\"cloud_run_revision\" AND metric.type=\"run.googleapis.com/request_count\" AND metric.labels.response_code_class=\"5xx\""
      comparison = "COMPARISON_GT"
      duration   = "300s"

      threshold_value = 10

      aggregations {
        alignment_period   = "60s"
        per_series_aligner = "ALIGN_RATE"
      }
    }
  }

  notification_channels = var.alert_email != "" ? [google_monitoring_notification_channel.email[0].id] : []
}

# ─────────────────────────────────────────────────────────────────────────────
# Cloud Monitoring Dashboard
# ─────────────────────────────────────────────────────────────────────────────

resource "google_monitoring_dashboard" "main" {
  count = var.enable_monitoring ? 1 : 0

  dashboard_json = jsonencode({
    displayName = "${local.name_prefix} Dashboard"
    gridLayout = {
      columns = 2
      widgets = [
        {
          title = "Request Count"
          xyChart = {
            dataSets = [{
              timeSeriesQuery = {
                timeSeriesFilter = {
                  filter = "resource.type=\"cloud_run_revision\" AND metric.type=\"run.googleapis.com/request_count\""
                  aggregation = {
                    alignmentPeriod  = "60s"
                    perSeriesAligner = "ALIGN_RATE"
                  }
                }
              }
            }]
          }
        },
        {
          title = "Request Latency (p99)"
          xyChart = {
            dataSets = [{
              timeSeriesQuery = {
                timeSeriesFilter = {
                  filter = "resource.type=\"cloud_run_revision\" AND metric.type=\"run.googleapis.com/request_latencies\""
                  aggregation = {
                    alignmentPeriod  = "60s"
                    perSeriesAligner = "ALIGN_PERCENTILE_99"
                  }
                }
              }
            }]
          }
        },
        {
          title = "Instance Count"
          xyChart = {
            dataSets = [{
              timeSeriesQuery = {
                timeSeriesFilter = {
                  filter = "resource.type=\"cloud_run_revision\" AND metric.type=\"run.googleapis.com/container/instance_count\""
                  aggregation = {
                    alignmentPeriod  = "60s"
                    perSeriesAligner = "ALIGN_MEAN"
                  }
                }
              }
            }]
          }
        },
        {
          title = "CPU Utilization"
          xyChart = {
            dataSets = [{
              timeSeriesQuery = {
                timeSeriesFilter = {
                  filter = "resource.type=\"cloud_run_revision\" AND metric.type=\"run.googleapis.com/container/cpu/utilizations\""
                  aggregation = {
                    alignmentPeriod  = "60s"
                    perSeriesAligner = "ALIGN_PERCENTILE_99"
                  }
                }
              }
            }]
          }
        },
      ]
    }
  })
}
