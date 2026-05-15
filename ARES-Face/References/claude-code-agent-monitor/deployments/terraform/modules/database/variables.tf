# ─────────────────────────────────────────────────────────────────────────────
# Database module variables
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

variable "storage_size_gb" {
  description = "Storage allocation in GiB (used by providers with provisioned capacity)"
  type        = number
  default     = 20
  validation {
    condition     = var.storage_size_gb >= 1
    error_message = "storage_size_gb must be at least 1 GiB."
  }
}

variable "enable_backup" {
  description = "Enable automated backup of the file system"
  type        = bool
  default     = true
}

variable "private_subnet_ids" {
  description = "Private subnet IDs for mount targets"
  type        = list(string)
}

variable "vpc_id" {
  description = "VPC ID for security group association"
  type        = string
}

variable "allowed_security_group_ids" {
  description = "Security group IDs allowed to mount the file system"
  type        = list(string)
}

variable "tags" {
  description = "Resource tags"
  type        = map(string)
  default     = {}
}
