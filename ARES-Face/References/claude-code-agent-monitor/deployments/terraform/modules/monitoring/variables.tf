# ─────────────────────────────────────────────────────────────────────────────
# Monitoring module variables
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

variable "alert_email" {
  description = "Email address for alert notifications (empty to skip)"
  type        = string
  default     = ""
}

variable "log_retention_days" {
  description = "Number of days to retain application logs"
  type        = number
  default     = 30
  validation {
    condition     = contains([1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1827, 3653], var.log_retention_days)
    error_message = "log_retention_days must be a valid CloudWatch retention period."
  }
}

variable "loadbalancer_arn" {
  description = "ARN of the application load balancer to monitor"
  type        = string
}

variable "target_group_arns" {
  description = "ARNs of target groups to monitor for unhealthy hosts"
  type        = list(string)
  default     = []
}

variable "compute_cluster_name" {
  description = "Name of the ECS cluster for compute metrics"
  type        = string
}

variable "filesystem_id" {
  description = "EFS file system ID for storage metrics"
  type        = string
}

variable "tags" {
  description = "Resource tags"
  type        = map(string)
  default     = {}
}
