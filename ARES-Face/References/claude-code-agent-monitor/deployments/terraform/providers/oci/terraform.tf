# ─────────────────────────────────────────────────────────────────────────────
# OCI provider – Terraform and provider constraints
# ─────────────────────────────────────────────────────────────────────────────

terraform {
  required_version = ">= 1.5.0"

  required_providers {
    oci = {
      source  = "oracle/oci"
      version = "~> 5.0"
    }
  }
}
