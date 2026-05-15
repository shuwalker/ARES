# ─────────────────────────────────────────────────────────────────────────────
# Production environment – terraform.tfvars
#
# Full production configuration.  3+ replicas with auto-scaling, large
# compute, comprehensive monitoring, TLS, blue-green deployment ready.
# ─────────────────────────────────────────────────────────────────────────────

# ── Provider ────────────────────────────────────────────────────────────────
cloud_provider = "aws"
region         = "us-east-1"

# ── Project ─────────────────────────────────────────────────────────────────
project_name = "claude-agent-monitor"
environment  = "production"

tags = {
  team        = "platform"
  cost_center = "engineering"
  criticality = "high"
  compliance  = "soc2"
}

# ── Networking (3 AZs for high availability) ───────────────────────────────
vpc_cidr             = "10.2.0.0/16"
public_subnet_cidrs  = ["10.2.1.0/24", "10.2.2.0/24", "10.2.3.0/24"]
private_subnet_cidrs = ["10.2.11.0/24", "10.2.12.0/24", "10.2.13.0/24"]

# ── Compute (large) ────────────────────────────────────────────────────────
app_container_image = "ghcr.io/anthropics/claude-agent-monitor:latest"
mcp_container_image = "ghcr.io/anthropics/claude-agent-monitor-mcp:latest"
cpu                 = 1024 # 1 vCPU
memory              = 2048 # 2 GiB

min_replicas     = 3
max_replicas     = 10
desired_replicas = 3

environment_variables = {
  NODE_ENV       = "production"
  DASHBOARD_PORT = "4820"
  LOG_LEVEL      = "warn"
}

# ── Deployment (blue-green with canary support) ────────────────────────────
deployment_strategy    = "blue-green"
active_deployment_slot = "blue"
blue_weight            = 100
green_weight           = 0

# During canary deployment, adjust weights:
#   blue_weight  = 90
#   green_weight = 10
# Then gradually shift to:
#   blue_weight  = 0
#   green_weight = 100
# Finally, flip active_deployment_slot = "green"

# ── TLS ─────────────────────────────────────────────────────────────────────
domain_name         = ""  # Set to production FQDN (e.g. "monitor.example.com")
tls_certificate_arn = ""  # Set to existing ACM cert ARN or leave empty for auto

# ── Storage ─────────────────────────────────────────────────────────────────
storage_size_gb       = 50
enable_storage_backup = true

# ── Health check (strict thresholds) ───────────────────────────────────────
health_check_path                = "/api/health"
health_check_interval            = 15
health_check_timeout             = 5
health_check_healthy_threshold   = 2
health_check_unhealthy_threshold = 2

# ── Auto-scaling (aggressive) ──────────────────────────────────────────────
autoscaling_cpu_target    = 60
autoscaling_memory_target = 70

# ── Monitoring (comprehensive) ─────────────────────────────────────────────
enable_monitoring  = true
alert_email        = ""  # REQUIRED: Set to ops team email for production alerts
log_retention_days = 90
