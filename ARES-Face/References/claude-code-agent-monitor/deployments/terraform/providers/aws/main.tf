# ─────────────────────────────────────────────────────────────────────────────
# AWS Provider – Full implementation for Claude Code Agent Monitor
#
# Composes the generic modules into a production-ready AWS stack:
#   VPC → ECS Fargate → EFS → ALB → CloudWatch → ACM
#
# Features:
#   - Multi-AZ deployment
#   - Blue/green deployment slots
#   - EFS for persistent SQLite storage
#   - ALB with WebSocket support and sticky sessions
#   - Auto-scaling with CPU/memory targets
#   - CloudWatch monitoring, alarms, and dashboards
#   - IAM least-privilege roles
# ─────────────────────────────────────────────────────────────────────────────

provider "aws" {
  region = var.region

  default_tags {
    tags = local.common_tags
  }
}

# ── Data sources ────────────────────────────────────────────────────────────

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

data "aws_availability_zones" "available" {
  state = "available"
}

# ── Locals ──────────────────────────────────────────────────────────────────

locals {
  name_prefix = lower(replace("${var.project_name}-${var.environment}", "_", "-"))

  common_tags = merge(
    {
      project        = var.project_name
      environment    = var.environment
      managed_by     = "terraform"
      cloud_provider = "aws"
      repository     = "Claude-Code-Agent-Monitor"
    },
    var.tags,
  )

  # Use first 3 available AZs when none specified
  availability_zones = length(var.availability_zones) > 0 ? var.availability_zones : slice(data.aws_availability_zones.available.names, 0, min(3, length(data.aws_availability_zones.available.names)))
}

# ─────────────────────────────────────────────────────────────────────────────
# Networking
# ─────────────────────────────────────────────────────────────────────────────

module "networking" {
  source = "../../modules/networking"

  project_name         = var.project_name
  environment          = var.environment
  cloud_provider       = "aws"
  region               = var.region
  vpc_cidr             = var.vpc_cidr
  availability_zones   = local.availability_zones
  public_subnet_cidrs  = var.public_subnet_cidrs
  private_subnet_cidrs = var.private_subnet_cidrs
  app_port             = var.app_port
  mcp_port             = var.mcp_port
  tags                 = local.common_tags
}

# ─────────────────────────────────────────────────────────────────────────────
# Database (EFS for SQLite persistence)
# ─────────────────────────────────────────────────────────────────────────────

module "database" {
  source = "../../modules/database"

  project_name               = var.project_name
  environment                = var.environment
  cloud_provider             = "aws"
  region                     = var.region
  storage_size_gb            = var.storage_size_gb
  enable_backup              = var.enable_storage_backup
  private_subnet_ids         = module.networking.private_subnet_ids
  vpc_id                     = module.networking.vpc_id
  allowed_security_group_ids = module.networking.storage_security_group_ids
  tags                       = local.common_tags
}

# ─────────────────────────────────────────────────────────────────────────────
# Compute – Blue slot
# ─────────────────────────────────────────────────────────────────────────────

module "compute_blue" {
  source = "../../modules/compute"

  project_name          = var.project_name
  environment           = var.environment
  cloud_provider        = "aws"
  region                = var.region
  deployment_slot       = "blue"
  container_image       = var.app_container_image
  mcp_container_image   = var.mcp_container_image
  app_port              = var.app_port
  mcp_port              = var.mcp_port
  cpu                   = var.cpu
  memory                = var.memory
  desired_count         = var.active_deployment_slot == "blue" ? var.desired_replicas : 0
  min_count             = var.active_deployment_slot == "blue" ? var.min_replicas : 0
  max_count             = var.active_deployment_slot == "blue" ? var.max_replicas : 0
  environment_variables = var.environment_variables
  health_check_path     = var.health_check_path
  vpc_id                = module.networking.vpc_id
  private_subnet_ids    = module.networking.private_subnet_ids
  security_group_ids    = module.networking.private_security_group_ids
  storage_filesystem_id = module.database.filesystem_id
  storage_mount_targets = module.database.mount_target_ids
  autoscaling_cpu_target    = var.autoscaling_cpu_target
  autoscaling_memory_target = var.autoscaling_memory_target
  tags                  = local.common_tags
}

# ─────────────────────────────────────────────────────────────────────────────
# Compute – Green slot
# ─────────────────────────────────────────────────────────────────────────────

module "compute_green" {
  source = "../../modules/compute"

  project_name          = var.project_name
  environment           = var.environment
  cloud_provider        = "aws"
  region                = var.region
  deployment_slot       = "green"
  container_image       = var.app_container_image
  mcp_container_image   = var.mcp_container_image
  app_port              = var.app_port
  mcp_port              = var.mcp_port
  cpu                   = var.cpu
  memory                = var.memory
  desired_count         = var.active_deployment_slot == "green" ? var.desired_replicas : 0
  min_count             = var.active_deployment_slot == "green" ? var.min_replicas : 0
  max_count             = var.active_deployment_slot == "green" ? var.max_replicas : 0
  environment_variables = var.environment_variables
  health_check_path     = var.health_check_path
  vpc_id                = module.networking.vpc_id
  private_subnet_ids    = module.networking.private_subnet_ids
  security_group_ids    = module.networking.private_security_group_ids
  storage_filesystem_id = module.database.filesystem_id
  storage_mount_targets = module.database.mount_target_ids
  autoscaling_cpu_target    = var.autoscaling_cpu_target
  autoscaling_memory_target = var.autoscaling_memory_target
  tags                  = local.common_tags
}

# ─────────────────────────────────────────────────────────────────────────────
# ACM Certificate (optional – when domain_name is specified)
# ─────────────────────────────────────────────────────────────────────────────

resource "aws_acm_certificate" "main" {
  count = var.domain_name != "" && var.tls_certificate_arn == "" ? 1 : 0

  domain_name       = var.domain_name
  validation_method = "DNS"

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-cert"
  })

  lifecycle {
    create_before_destroy = true
  }
}

locals {
  tls_cert_arn = var.tls_certificate_arn != "" ? var.tls_certificate_arn : (
    length(aws_acm_certificate.main) > 0 ? aws_acm_certificate.main[0].arn : ""
  )
}

# ─────────────────────────────────────────────────────────────────────────────
# Load Balancer
# ─────────────────────────────────────────────────────────────────────────────

module "loadbalancer" {
  source = "../../modules/loadbalancer"

  project_name        = var.project_name
  environment         = var.environment
  cloud_provider      = "aws"
  region              = var.region
  vpc_id              = module.networking.vpc_id
  public_subnet_ids   = module.networking.public_subnet_ids
  security_group_ids  = module.networking.public_security_group_ids
  app_port            = var.app_port
  mcp_port            = var.mcp_port
  tls_certificate_arn = local.tls_cert_arn
  domain_name         = var.domain_name

  blue_target_group_arn  = module.compute_blue.target_group_arn
  green_target_group_arn = module.compute_green.target_group_arn
  blue_weight            = var.blue_weight
  green_weight           = var.green_weight

  health_check_path                = var.health_check_path
  health_check_interval            = var.health_check_interval
  health_check_timeout             = var.health_check_timeout
  health_check_healthy_threshold   = var.health_check_healthy_threshold
  health_check_unhealthy_threshold = var.health_check_unhealthy_threshold

  enable_deletion_protection = var.environment == "production"

  tags = local.common_tags
}

# ─────────────────────────────────────────────────────────────────────────────
# Monitoring
# ─────────────────────────────────────────────────────────────────────────────

module "monitoring" {
  source = "../../modules/monitoring"
  count  = var.enable_monitoring ? 1 : 0

  project_name       = var.project_name
  environment        = var.environment
  cloud_provider     = "aws"
  region             = var.region
  alert_email        = var.alert_email
  log_retention_days = var.log_retention_days

  loadbalancer_arn     = module.loadbalancer.loadbalancer_arn
  target_group_arns    = [module.compute_blue.target_group_arn, module.compute_green.target_group_arn]
  compute_cluster_name = module.compute_blue.cluster_name
  filesystem_id        = module.database.filesystem_id

  tags = local.common_tags
}

# ─────────────────────────────────────────────────────────────────────────────
# Route53 DNS record (optional)
# ─────────────────────────────────────────────────────────────────────────────

data "aws_route53_zone" "main" {
  count = var.domain_name != "" && var.route53_zone_id != "" ? 1 : 0

  zone_id = var.route53_zone_id
}

resource "aws_route53_record" "app" {
  count = var.domain_name != "" && var.route53_zone_id != "" ? 1 : 0

  zone_id = data.aws_route53_zone.main[0].zone_id
  name    = var.domain_name
  type    = "A"

  alias {
    name                   = module.loadbalancer.dns_name
    zone_id                = module.loadbalancer.zone_id
    evaluate_target_health = true
  }
}
