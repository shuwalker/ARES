# ─────────────────────────────────────────────────────────────────────────────
# Load Balancer module variables
# ─────────────────────────────────────────────────────────────────────────────

variable "project_name" {
  description = "Project identifier used in resource naming"
  type        = string
}

variable "environment" {
  description = "Deployment environment (dev, staging, production)"
  type        = string
}

variable "cloud_provider" {
  description = "Target cloud provider (aws, gcp, azure, oci)"
  type        = string
}

variable "region" {
  description = "Cloud region for deployment"
  type        = string
}

variable "vpc_id" {
  description = "VPC ID for target group association"
  type        = string
}

variable "public_subnet_ids" {
  description = "Public subnet IDs for load balancer placement"
  type        = list(string)
}

variable "security_group_ids" {
  description = "Security group IDs attached to the load balancer"
  type        = list(string)
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

variable "tls_certificate_arn" {
  description = "ARN of the TLS certificate for HTTPS (required for production)"
  type        = string
  default     = ""
}

variable "domain_name" {
  description = "Fully qualified domain name for the application (required for production)"
  type        = string
  default     = ""
}

variable "blue_target_group_arn" {
  description = "ARN of the blue deployment target group"
  type        = string
}

variable "green_target_group_arn" {
  description = "ARN of the green deployment target group"
  type        = string
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

variable "health_check_healthy_threshold" {
  description = "Consecutive successes to mark healthy"
  type        = number
  default     = 2
}

variable "health_check_unhealthy_threshold" {
  description = "Consecutive failures to mark unhealthy"
  type        = number
  default     = 3
}

variable "tags" {
  description = "Resource tags"
  type        = map(string)
  default     = {}
}

variable "enable_deletion_protection" {
  description = "Enable deletion protection on the load balancer (recommended for production)"
  type        = bool
  default     = false
}
