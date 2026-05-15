# ─────────────────────────────────────────────────────────────────────────────
# Staging environment – terraform.tfvars
#
# Production-like configuration with moderate resources.  Two replicas,
# medium compute, monitoring enabled with relaxed thresholds.
# ─────────────────────────────────────────────────────────────────────────────

# ── Provider ────────────────────────────────────────────────────────────────
cloud_provider = "aws"
region         = "us-east-1"

# ── Project ─────────────────────────────────────────────────────────────────
project_name = "claude-agent-monitor"
environment  = "staging"

tags = {
  team        = "platform"
  cost_center = "engineering"
}

# ── Networking ──────────────────────────────────────────────────────────────
vpc_cidr             = "10.1.0.0/16"
public_subnet_cidrs  = ["10.1.1.0/24", "10.1.2.0/24", "10.1.3.0/24"]
private_subnet_cidrs = ["10.1.11.0/24", "10.1.12.0/24", "10.1.13.0/24"]

# ── Compute (medium) ───────────────────────────────────────────────────────
app_container_image = "ghcr.io/anthropics/claude-agent-monitor:staging"
mcp_container_image = "ghcr.io/anthropics/claude-agent-monitor-mcp:staging"
cpu                 = 512  # 0.5 vCPU
memory              = 1024 # 1 GiB

min_replicas     = 1
max_replicas     = 3
desired_replicas = 2

environment_variables = {
  NODE_ENV       = "production"
  DASHBOARD_PORT = "4820"
  LOG_LEVEL      = "info"
}

# ── Deployment (blue-green ready) ──────────────────────────────────────────
deployment_strategy    = "blue-green"
active_deployment_slot = "blue"
blue_weight            = 100
green_weight           = 0

# ── TLS ─────────────────────────────────────────────────────────────────────
domain_name         = ""  # Set to staging FQDN when available
tls_certificate_arn = ""  # Auto-created if domain_name is set

# ── Storage ─────────────────────────────────────────────────────────────────
storage_size_gb       = 20
enable_storage_backup = true

# ── Health check ────────────────────────────────────────────────────────────
health_check_path              = "/api/health"
health_check_interval          = 30
health_check_timeout           = 5
health_check_healthy_threshold = 2
health_check_unhealthy_threshold = 3

# ── Auto-scaling ────────────────────────────────────────────────────────────
autoscaling_cpu_target    = 70
autoscaling_memory_target = 80

# ── Monitoring ──────────────────────────────────────────────────────────────
enable_monitoring  = true
alert_email        = ""  # Set to team email for staging alerts
log_retention_days = 14
