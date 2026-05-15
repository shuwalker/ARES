# ─────────────────────────────────────────────────────────────────────────────
# Database module – Persistent storage for SQLite
#
# Creates a managed network file system (EFS on AWS) with:
#   - Encryption at rest and in transit
#   - Automated backup policy
#   - Mount targets in each private subnet
#   - Performance mode optimised for SQLite workloads
# ─────────────────────────────────────────────────────────────────────────────

locals {
  name_prefix = lower(replace("${var.project_name}-${var.environment}", "_", "-"))

  common_tags = merge(
    {
      module = "database"
    },
    var.tags,
  )
}

# ─────────────────────────────────────────────────────────────────────────────
# EFS file system
# ─────────────────────────────────────────────────────────────────────────────

resource "aws_efs_file_system" "main" {
  creation_token = "${local.name_prefix}-data"
  encrypted      = true

  # General Purpose is optimal for SQLite (latency-sensitive small I/O)
  performance_mode = "generalPurpose"
  throughput_mode  = "elastic"

  lifecycle_policy {
    transition_to_ia = "AFTER_30_DAYS"
  }

  lifecycle_policy {
    transition_to_primary_storage_class = "AFTER_1_ACCESS"
  }

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-efs"
  })

  lifecycle {
    prevent_destroy = true
  }
}

# ─────────────────────────────────────────────────────────────────────────────
# EFS backup policy
# ─────────────────────────────────────────────────────────────────────────────

resource "aws_efs_backup_policy" "main" {
  file_system_id = aws_efs_file_system.main.id

  backup_policy {
    status = var.enable_backup ? "ENABLED" : "DISABLED"
  }
}

# ─────────────────────────────────────────────────────────────────────────────
# EFS mount targets (one per private subnet / AZ)
# ─────────────────────────────────────────────────────────────────────────────

resource "aws_efs_mount_target" "main" {
  count = length(var.private_subnet_ids)

  file_system_id  = aws_efs_file_system.main.id
  subnet_id       = var.private_subnet_ids[count.index]
  security_groups = var.allowed_security_group_ids
}

# ─────────────────────────────────────────────────────────────────────────────
# EFS access point – scoped to /app/data for the container workload
# ─────────────────────────────────────────────────────────────────────────────

resource "aws_efs_access_point" "app_data" {
  file_system_id = aws_efs_file_system.main.id

  posix_user {
    uid = 1000
    gid = 1000
  }

  root_directory {
    path = "/app-data"

    creation_info {
      owner_uid   = 1000
      owner_gid   = 1000
      permissions = "0755"
    }
  }

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-app-data-ap"
  })
}

# ─────────────────────────────────────────────────────────────────────────────
# EFS file system policy – enforce encryption in transit
# ─────────────────────────────────────────────────────────────────────────────

resource "aws_efs_file_system_policy" "main" {
  file_system_id = aws_efs_file_system.main.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "EnforceEncryptInTransit"
        Effect    = "Deny"
        Principal = { AWS = "*" }
        Action    = "*"
        Resource  = aws_efs_file_system.main.arn
        Condition = {
          Bool = {
            "aws:SecureTransport" = "false"
          }
        }
      },
      {
        Sid       = "AllowMountViaAccessPoint"
        Effect    = "Allow"
        Principal = { AWS = "*" }
        Action = [
          "elasticfilesystem:ClientMount",
          "elasticfilesystem:ClientWrite",
          "elasticfilesystem:ClientRootAccess",
        ]
        Resource = aws_efs_file_system.main.arn
        Condition = {
          Bool = {
            "elasticfilesystem:AccessedViaMountTarget" = "true"
          }
        }
      }
    ]
  })
}
