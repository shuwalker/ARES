# ─────────────────────────────────────────────────────────────────────────────
# Compute module variables
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

variable "deployment_slot" {
  description = "Deployment slot identifier for blue-green: blue or green"
  type        = string
  default     = "blue"
  validation {
    condition     = contains(["blue", "green"], var.deployment_slot)
    error_message = "deployment_slot must be blue or green."
  }
}

variable "container_image" {
  description = "Container image URI for the main application"
  type        = string
}

variable "mcp_container_image" {
  description = "Container image URI for the MCP sidecar (empty to disable)"
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
  description = "CPU units for the task (256, 512, 1024, 2048, 4096)"
  type        = number
  default     = 512
  validation {
    condition     = contains([256, 512, 1024, 2048, 4096], var.cpu)
    error_message = "cpu must be one of: 256, 512, 1024, 2048, 4096."
  }
}

variable "memory" {
  description = "Memory in MiB for the task"
  type        = number
  default     = 1024
}

variable "desired_count" {
  description = "Desired number of running task instances"
  type        = number
  default     = 1
}

variable "min_count" {
  description = "Minimum number of task instances for auto-scaling"
  type        = number
  default     = 1
}

variable "max_count" {
  description = "Maximum number of task instances for auto-scaling"
  type        = number
  default     = 3
}

variable "environment_variables" {
  description = "Map of environment variables for the application container"
  type        = map(string)
  default     = {}
}

variable "health_check_path" {
  description = "HTTP path for container health checks"
  type        = string
  default     = "/api/health"
}

variable "vpc_id" {
  description = "VPC ID for target group and networking"
  type        = string
}

variable "private_subnet_ids" {
  description = "Subnet IDs where tasks will be placed"
  type        = list(string)
}

variable "security_group_ids" {
  description = "Security group IDs attached to task ENIs"
  type        = list(string)
}

variable "storage_filesystem_id" {
  description = "EFS file system ID for persistent SQLite storage"
  type        = string
}

variable "storage_mount_targets" {
  description = "EFS mount target IDs (ensures mount targets exist before service)"
  type        = list(string)
  default     = []
}

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

variable "tags" {
  description = "Resource tags"
  type        = map(string)
  default     = {}
}
