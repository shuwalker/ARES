# ─────────────────────────────────────────────────────────────────────────────
# AWS provider variables
# ─────────────────────────────────────────────────────────────────────────────

# ── Core ────────────────────────────────────────────────────────────────────

variable "project_name" {
  description = "Project identifier used in resource naming and tagging"
  type        = string
  default     = "claude-agent-monitor"
}

variable "environment" {
  description = "Deployment environment: dev, staging, or production"
  type        = string
  validation {
    condition     = contains(["dev", "staging", "production"], var.environment)
    error_message = "environment must be one of: dev, staging, production."
  }
}

variable "region" {
  description = "AWS region for resource deployment"
  type        = string
  default     = "us-east-1"
}

variable "tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default     = {}
}

# ── Networking ──────────────────────────────────────────────────────────────

variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "availability_zones" {
  description = "List of AZs (auto-detected if empty)"
  type        = list(string)
  default     = []
}

variable "public_subnet_cidrs" {
  description = "CIDR blocks for public subnets"
  type        = list(string)
  default     = ["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"]
}

variable "private_subnet_cidrs" {
  description = "CIDR blocks for private subnets"
  type        = list(string)
  default     = ["10.0.11.0/24", "10.0.12.0/24", "10.0.13.0/24"]
}

# ── Compute ─────────────────────────────────────────────────────────────────

variable "app_container_image" {
  description = "Docker image URI for the main application"
  type        = string
}

variable "mcp_container_image" {
  description = "Docker image URI for the MCP sidecar (empty to disable)"
  type        = string
  default     = ""
}

variable "app_port" {
  description = "Application container port"
  type        = number
  default     = 4820
}

variable "mcp_port" {
  description = "MCP sidecar container port"
  type        = number
  default     = 8819
}

variable "cpu" {
  description = "CPU units for Fargate tasks (256, 512, 1024, 2048, 4096)"
  type        = number
  default     = 512
}

variable "memory" {
  description = "Memory in MiB for Fargate tasks"
  type        = number
  default     = 1024
}

variable "min_replicas" {
  description = "Minimum number of ECS tasks"
  type        = number
  default     = 1
}

variable "max_replicas" {
  description = "Maximum number of ECS tasks for auto-scaling"
  type        = number
  default     = 3
}

variable "desired_replicas" {
  description = "Desired number of ECS tasks at steady state"
  type        = number
  default     = 1
}

variable "environment_variables" {
  description = "Environment variables for the application container"
  type        = map(string)
  default = {
    NODE_ENV       = "production"
    DASHBOARD_PORT = "4820"
  }
}

# ── Deployment ──────────────────────────────────────────────────────────────

variable "active_deployment_slot" {
  description = "Active deployment slot: blue or green"
  type        = string
  default     = "blue"
  validation {
    condition     = contains(["blue", "green"], var.active_deployment_slot)
    error_message = "active_deployment_slot must be blue or green."
  }
}

variable "blue_weight" {
  description = "Traffic weight for blue target group (0-100)"
  type        = number
  default     = 100
  validation {
    condition     = var.blue_weight >= 0 && var.blue_weight <= 100
    error_message = "blue_weight must be between 0 and 100."
  }
}

variable "green_weight" {
  description = "Traffic weight for green target group (0-100)"
  type        = number
  default     = 0
  validation {
    condition     = var.green_weight >= 0 && var.green_weight <= 100
    error_message = "green_weight must be between 0 and 100."
  }
}

# ── TLS / Domain ────────────────────────────────────────────────────────────

variable "domain_name" {
  description = "FQDN for the application (empty to skip DNS/TLS)"
  type        = string
  default     = ""
}

variable "tls_certificate_arn" {
  description = "ARN of an existing ACM certificate (auto-created if domain_name set)"
  type        = string
  default     = ""
}

variable "route53_zone_id" {
  description = "Route53 hosted zone ID for DNS records (empty to skip)"
  type        = string
  default     = ""
}

# ── Storage ─────────────────────────────────────────────────────────────────

variable "storage_size_gb" {
  description = "EFS storage does not require pre-provisioning; kept for interface compatibility"
  type        = number
  default     = 20
}

variable "enable_storage_backup" {
  description = "Enable AWS Backup for EFS"
  type        = bool
  default     = true
}

# ── Health check ────────────────────────────────────────────────────────────

variable "health_check_path" {
  description = "HTTP path for health checks"
  type        = string
  default     = "/api/health"
}

variable "health_check_interval" {
  description = "Seconds between health checks"
  type        = number
  default     = 30
}

variable "health_check_timeout" {
  description = "Seconds before a health check request times out"
  type        = number
  default     = 5
}

variable "health_check_healthy_threshold" {
  description = "Consecutive successes to mark target healthy"
  type        = number
  default     = 2
}

variable "health_check_unhealthy_threshold" {
  description = "Consecutive failures to mark target unhealthy"
  type        = number
  default     = 3
}

# ── Auto-scaling ────────────────────────────────────────────────────────────

variable "autoscaling_cpu_target" {
  description = "Target CPU utilization percentage for auto-scaling"
  type        = number
  default     = 70
}

variable "autoscaling_memory_target" {
  description = "Target memory utilization percentage for auto-scaling"
  type        = number
  default     = 80
}

# ── Monitoring ──────────────────────────────────────────────────────────────

variable "enable_monitoring" {
  description = "Enable CloudWatch monitoring, alarms, and dashboards"
  type        = bool
  default     = true
}

variable "alert_email" {
  description = "Email address for SNS alert notifications"
  type        = string
  default     = ""
}

variable "log_retention_days" {
  description = "CloudWatch log retention in days"
  type        = number
  default     = 30
}
