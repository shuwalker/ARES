# ─────────────────────────────────────────────────────────────────────────────
# Networking module variables
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

variable "vpc_cidr" {
  description = "CIDR block for the virtual network"
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

variable "tags" {
  description = "Resource tags"
  type        = map(string)
  default     = {}
}
