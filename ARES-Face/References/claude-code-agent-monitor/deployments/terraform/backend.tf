# ─────────────────────────────────────────────────────────────────────────────
# Remote state backend – uncomment the block matching your cloud provider.
# Only ONE backend may be active at a time.
# ─────────────────────────────────────────────────────────────────────────────

# ── AWS S3 ──────────────────────────────────────────────────────────────────
# terraform {
#   backend "s3" {
#     bucket         = "ccam-terraform-state"
#     key            = "claude-agent-monitor/terraform.tfstate"
#     region         = "us-east-1"
#     encrypt        = true
#     dynamodb_table = "ccam-terraform-locks"
#   }
# }

# ── GCP Cloud Storage ──────────────────────────────────────────────────────
# terraform {
#   backend "gcs" {
#     bucket = "ccam-terraform-state"
#     prefix = "claude-agent-monitor"
#   }
# }

# ── Azure Blob Storage ─────────────────────────────────────────────────────
# terraform {
#   backend "azurerm" {
#     resource_group_name  = "ccam-terraform-state-rg"
#     storage_account_name = "ccamtfstate"
#     container_name       = "tfstate"
#     key                  = "claude-agent-monitor.tfstate"
#   }
# }

# ── OCI Object Storage ─────────────────────────────────────────────────────
# terraform {
#   backend "s3" {
#     bucket                      = "ccam-terraform-state"
#     key                         = "claude-agent-monitor/terraform.tfstate"
#     region                      = "us-ashburn-1"
#     endpoint                    = "https://<namespace>.compat.objectstorage.<region>.oraclecloud.com"
#     skip_region_validation      = true
#     skip_credentials_validation = true
#     skip_metadata_api_check     = true
#     force_path_style            = true
#   }
# }
