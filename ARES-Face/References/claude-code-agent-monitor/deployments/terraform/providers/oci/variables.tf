# ─────────────────────────────────────────────────────────────────────────────
# OCI provider variables
# ─────────────────────────────────────────────────────────────────────────────

variable "project_name" {
  description = "Project identifier used in resource naming"
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
  description = "OCI region for resource deployment"
  type        = string
  default     = "us-ashburn-1"
}

variable "tenancy_id" {
  description = "OCI tenancy OCID"
  type        = string
}

variable "compartment_id" {
  description = "OCI compartment OCID for resource deployment"
  type        = string
}

variable "tags" {
  description = "Additional freeform tags to apply to all resources"
  type        = map(string)
  default     = {}
}

# ── Networking ──────────────────────────────────────────────────────────────

variable "vpc_cidr" {
  description = "CIDR block for the VCN"
  type        = string
  default     = "10.0.0.0/16"
}

variable "public_subnet_cidrs" {
  description = "CIDR blocks for public subnets"
  type        = list(string)
  default     = ["10.0.1.0/24"]
}

variable "private_subnet_cidrs" {
  description = "CIDR blocks for private subnets"
  type        = list(string)
  default     = ["10.0.11.0/24"]
}

# ── Compute ─────────────────────────────────────────────────────────────────

variable "app_container_image" {
  description = "Container image URI for the main application"
  type        = string
}

variable "mcp_container_image" {
  description = "Container image URI for the MCP sidecar (empty to disable)"
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
  description = "CPU millicores (converted to OCPUs: 1000m = 1 OCPU)"
  type        = number
  default     = 512
}

variable "memory" {
  description = "Memory in MiB (converted to GiB for OCI)"
  type        = number
  default     = 1024
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
  description = "Traffic weight for blue backend (0-100)"
  type        = number
  default     = 100
  validation {
    condition     = var.blue_weight >= 0 && var.blue_weight <= 100
    error_message = "blue_weight must be between 0 and 100."
  }
}

variable "green_weight" {
  description = "Traffic weight for green backend (0-100)"
  type        = number
  default     = 0
  validation {
    condition     = var.green_weight >= 0 && var.green_weight <= 100
    error_message = "green_weight must be between 0 and 100."
  }
}

# ── Storage ─────────────────────────────────────────────────────────────────

variable "storage_size_gb" {
  description = "FSS export size limit in GiB"
  type        = number
  default     = 50
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
  description = "Seconds before a health check times out"
  type        = number
  default     = 5
}

variable "health_check_unhealthy_threshold" {
  description = "Consecutive failures to mark unhealthy"
  type        = number
  default     = 3
}

# ── Monitoring ──────────────────────────────────────────────────────────────

variable "enable_monitoring" {
  description = "Enable OCI Monitoring alarms and notifications"
  type        = bool
  default     = true
}

variable "alert_email" {
  description = "Email address for alarm notifications"
  type        = string
  default     = ""
}
