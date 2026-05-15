# ─────────────────────────────────────────────────────────────────────────────
# Root module variables – Claude Code Agent Monitor
# ─────────────────────────────────────────────────────────────────────────────

# ── Provider selection ──────────────────────────────────────────────────────

variable "cloud_provider" {
  description = "Target cloud provider: aws, gcp, azure, or oci"
  type        = string
  validation {
    condition     = contains(["aws", "gcp", "azure", "oci"], var.cloud_provider)
    error_message = "cloud_provider must be one of: aws, gcp, azure, oci."
  }
}

variable "region" {
  description = "Cloud provider region for resource deployment"
  type        = string
}

# ── Project metadata ────────────────────────────────────────────────────────

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

variable "tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default     = {}
}

# ── Networking ──────────────────────────────────────────────────────────────

variable "vpc_cidr" {
  description = "CIDR block for the VPC / VNet / VCN"
  type        = string
  default     = "10.0.0.0/16"
  validation {
    condition     = can(cidrhost(var.vpc_cidr, 0))
    error_message = "vpc_cidr must be a valid CIDR block."
  }
}

variable "availability_zones" {
  description = "List of availability zones for multi-AZ deployment"
  type        = list(string)
  default     = []
}

variable "public_subnet_cidrs" {
  description = "CIDR blocks for public subnets (one per AZ)"
  type        = list(string)
  default     = ["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"]
}

variable "private_subnet_cidrs" {
  description = "CIDR blocks for private subnets (one per AZ)"
  type        = list(string)
  default     = ["10.0.11.0/24", "10.0.12.0/24", "10.0.13.0/24"]
}

# ── Compute ─────────────────────────────────────────────────────────────────

variable "app_container_image" {
  description = "Container image URI for the main application"
  type        = string
}

variable "mcp_container_image" {
  description = "Container image URI for the MCP sidecar"
  type        = string
  default     = ""
}

variable "app_port" {
  description = "Port the application container listens on"
  type        = number
  default     = 4820
}

variable "mcp_port" {
  description = "Port the MCP sidecar container listens on"
  type        = number
  default     = 8819
}

variable "cpu" {
  description = "CPU units for each container instance (e.g. 256, 512, 1024)"
  type        = number
  default     = 512
  validation {
    condition     = contains([256, 512, 1024, 2048, 4096], var.cpu)
    error_message = "cpu must be one of: 256, 512, 1024, 2048, 4096 (valid Fargate CPU values)."
  }
}

variable "memory" {
  description = "Memory in MiB for each container instance"
  type        = number
  default     = 1024
}

variable "min_replicas" {
  description = "Minimum number of container replicas"
  type        = number
  default     = 1
}

variable "max_replicas" {
  description = "Maximum number of container replicas for auto-scaling"
  type        = number
  default     = 3
}

variable "desired_replicas" {
  description = "Desired number of container replicas at steady state"
  type        = number
  default     = 1
}

variable "environment_variables" {
  description = "Environment variables passed to the application container"
  type        = map(string)
  default = {
    NODE_ENV       = "production"
    DASHBOARD_PORT = "4820"
  }
}

# ── Deployment strategy ─────────────────────────────────────────────────────

variable "deployment_strategy" {
  description = "Deployment strategy: rolling, blue-green, or canary"
  type        = string
  default     = "rolling"
  validation {
    condition     = contains(["rolling", "blue-green", "canary"], var.deployment_strategy)
    error_message = "deployment_strategy must be one of: rolling, blue-green, canary."
  }
}

variable "active_deployment_slot" {
  description = "Active deployment slot for blue-green: blue or green"
  type        = string
  default     = "blue"
  validation {
    condition     = contains(["blue", "green"], var.active_deployment_slot)
    error_message = "active_deployment_slot must be blue or green."
  }
}

variable "blue_weight" {
  description = "Traffic weight percentage for the blue deployment slot (0-100)"
  type        = number
  default     = 100
  validation {
    condition     = var.blue_weight >= 0 && var.blue_weight <= 100
    error_message = "blue_weight must be between 0 and 100."
  }
}

variable "green_weight" {
  description = "Traffic weight percentage for the green deployment slot (0-100)"
  type        = number
  default     = 0
  validation {
    condition     = var.green_weight >= 0 && var.green_weight <= 100
    error_message = "green_weight must be between 0 and 100."
  }
}

# ── TLS / Domain ────────────────────────────────────────────────────────────

variable "domain_name" {
  description = "Fully qualified domain name for the application"
  type        = string
  default     = ""
}

variable "tls_certificate_arn" {
  description = "ARN / ID of the TLS certificate for HTTPS termination"
  type        = string
  default     = ""
}

# ── Monitoring ──────────────────────────────────────────────────────────────

variable "enable_monitoring" {
  description = "Enable monitoring, alerting, and log aggregation"
  type        = bool
  default     = true
}

variable "alert_email" {
  description = "Email address for monitoring alert notifications"
  type        = string
  default     = ""
}

variable "log_retention_days" {
  description = "Number of days to retain application logs"
  type        = number
  default     = 30
  validation {
    condition     = contains([1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1827, 3653], var.log_retention_days)
    error_message = "log_retention_days must be a valid CloudWatch retention period (1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1827, or 3653)."
  }
}

# ── Storage ─────────────────────────────────────────────────────────────────

variable "storage_size_gb" {
  description = "Persistent storage size in GiB for the SQLite database"
  type        = number
  default     = 20
}

variable "enable_storage_backup" {
  description = "Enable automated backup of persistent storage"
  type        = bool
  default     = true
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

# ── Health check ────────────────────────────────────────────────────────────

variable "health_check_path" {
  description = "HTTP path for application health checks"
  type        = string
  default     = "/api/health"
}

variable "health_check_interval" {
  description = "Interval in seconds between health checks"
  type        = number
  default     = 30
}

variable "health_check_timeout" {
  description = "Timeout in seconds for each health check request"
  type        = number
  default     = 5
}

variable "health_check_healthy_threshold" {
  description = "Consecutive successes required to mark target healthy"
  type        = number
  default     = 2
}

variable "health_check_unhealthy_threshold" {
  description = "Consecutive failures required to mark target unhealthy"
  type        = number
  default     = 3
}
