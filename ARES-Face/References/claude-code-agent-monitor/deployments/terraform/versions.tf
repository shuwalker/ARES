# ─────────────────────────────────────────────────────────────────────────────
# Claude Code Agent Monitor – Terraform version constraints
# ─────────────────────────────────────────────────────────────────────────────

terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.80"
    }
    oci = {
      source  = "oracle/oci"
      version = "~> 5.0"
    }
  }
}
