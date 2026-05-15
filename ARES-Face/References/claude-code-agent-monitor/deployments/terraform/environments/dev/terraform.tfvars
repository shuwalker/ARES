# ─────────────────────────────────────────────────────────────────────────────
# Development environment – terraform.tfvars
#
# Minimal resources for development/testing.  Single replica, small compute,
# monitoring disabled to reduce cost.
# ─────────────────────────────────────────────────────────────────────────────

# ── Provider ────────────────────────────────────────────────────────────────
cloud_provider = "aws"
region         = "us-east-1"

# ── Project ─────────────────────────────────────────────────────────────────
project_name = "claude-agent-monitor"
environment  = "dev"

tags = {
  team     = "platform"
  cost_center = "engineering"
}

# ── Networking ──────────────────────────────────────────────────────────────
vpc_cidr             = "10.0.0.0/16"
public_subnet_cidrs  = ["10.0.1.0/24", "10.0.2.0/24"]
private_subnet_cidrs = ["10.0.11.0/24", "10.0.12.0/24"]

# ── Compute (small) ────────────────────────────────────────────────────────
app_container_image = "ghcr.io/anthropics/claude-agent-monitor:latest"
mcp_container_image = ""  # MCP sidecar disabled in dev
cpu                 = 256 # 0.25 vCPU
memory              = 512 # 512 MiB

min_replicas     = 1
max_replicas     = 1
desired_replicas = 1

environment_variables = {
  NODE_ENV       = "development"
  DASHBOARD_PORT = "4820"
  LOG_LEVEL      = "debug"
}

# ── Deployment ──────────────────────────────────────────────────────────────
deployment_strategy    = "rolling"
active_deployment_slot = "blue"
blue_weight            = 100
green_weight           = 0

# ── TLS (disabled in dev) ──────────────────────────────────────────────────
domain_name         = ""
tls_certificate_arn = ""

# ── Storage ─────────────────────────────────────────────────────────────────
storage_size_gb       = 10
enable_storage_backup = false

# ── Health check ────────────────────────────────────────────────────────────
health_check_path     = "/api/health"
health_check_interval = 60  # Less frequent in dev

# ── Auto-scaling (disabled – single replica) ────────────────────────────────
autoscaling_cpu_target    = 80
autoscaling_memory_target = 90

# ── Monitoring (minimal) ───────────────────────────────────────────────────
enable_monitoring  = false
alert_email        = ""
log_retention_days = 7
