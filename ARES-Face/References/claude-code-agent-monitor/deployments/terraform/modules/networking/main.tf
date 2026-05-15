# ─────────────────────────────────────────────────────────────────────────────
# Networking module – Cloud-agnostic VPC / VNet / VCN abstraction
#
# Creates the foundational network topology: virtual network, public and
# private subnets across availability zones, NAT gateway, internet gateway,
# route tables, and security groups / firewall rules.
# ─────────────────────────────────────────────────────────────────────────────

locals {
  name_prefix = lower(replace("${var.project_name}-${var.environment}", "_", "-"))

  # Default AZs when none provided – derive from region
  default_azs = [
    "${var.region}a",
    "${var.region}b",
    "${var.region}c",
  ]

  availability_zones = length(var.availability_zones) > 0 ? var.availability_zones : local.default_azs

  # Number of AZs determines subnet count
  az_count = min(length(local.availability_zones), length(var.public_subnet_cidrs), length(var.private_subnet_cidrs))

  common_tags = merge(
    {
      module = "networking"
    },
    var.tags,
  )
}

# ─────────────────────────────────────────────────────────────────────────────
# VPC
# ─────────────────────────────────────────────────────────────────────────────

resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-vpc"
  })

  lifecycle {
    prevent_destroy = false
  }
}

# ─────────────────────────────────────────────────────────────────────────────
# Internet gateway
# ─────────────────────────────────────────────────────────────────────────────

resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-igw"
  })
}

# ─────────────────────────────────────────────────────────────────────────────
# Public subnets
# ─────────────────────────────────────────────────────────────────────────────

resource "aws_subnet" "public" {
  count = local.az_count

  vpc_id                  = aws_vpc.main.id
  cidr_block              = var.public_subnet_cidrs[count.index]
  availability_zone       = local.availability_zones[count.index]
  map_public_ip_on_launch = true

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-public-${local.availability_zones[count.index]}"
    tier = "public"
  })
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-public-rt"
  })
}

resource "aws_route_table_association" "public" {
  count = local.az_count

  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

# ─────────────────────────────────────────────────────────────────────────────
# NAT gateway (single, in first public subnet – cost-conscious default)
# ─────────────────────────────────────────────────────────────────────────────

resource "aws_eip" "nat" {
  domain = "vpc"

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-nat-eip"
  })
}

resource "aws_nat_gateway" "main" {
  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.public[0].id

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-nat"
  })

  depends_on = [aws_internet_gateway.main]
}

# ─────────────────────────────────────────────────────────────────────────────
# Private subnets
# ─────────────────────────────────────────────────────────────────────────────

resource "aws_subnet" "private" {
  count = local.az_count

  vpc_id            = aws_vpc.main.id
  cidr_block        = var.private_subnet_cidrs[count.index]
  availability_zone = local.availability_zones[count.index]

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-private-${local.availability_zones[count.index]}"
    tier = "private"
  })
}

resource "aws_route_table" "private" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.main.id
  }

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-private-rt"
  })
}

resource "aws_route_table_association" "private" {
  count = local.az_count

  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private.id
}

# ─────────────────────────────────────────────────────────────────────────────
# Security groups
# ─────────────────────────────────────────────────────────────────────────────

# Public (load-balancer-facing)
resource "aws_security_group" "public" {
  name_prefix = "${local.name_prefix}-public-"
  description = "Allow HTTPS/HTTP inbound and all outbound"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "HTTPS"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "HTTP (redirect)"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "All outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-public-sg"
  })

  lifecycle {
    create_before_destroy = true
  }
}

# Private (container-facing)
resource "aws_security_group" "private" {
  name_prefix = "${local.name_prefix}-private-"
  description = "Allow traffic from public SG to app and MCP ports"
  vpc_id      = aws_vpc.main.id

  ingress {
    description     = "Application port from LB"
    from_port       = var.app_port
    to_port         = var.app_port
    protocol        = "tcp"
    security_groups = [aws_security_group.public.id]
  }

  ingress {
    description     = "MCP sidecar port from LB"
    from_port       = var.mcp_port
    to_port         = var.mcp_port
    protocol        = "tcp"
    security_groups = [aws_security_group.public.id]
  }

  ingress {
    description = "NFS (EFS) within VPC"
    from_port   = 2049
    to_port     = 2049
    protocol    = "tcp"
    self        = true
  }

  egress {
    description = "All outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-private-sg"
  })

  lifecycle {
    create_before_destroy = true
  }
}

# EFS security group
resource "aws_security_group" "storage" {
  name_prefix = "${local.name_prefix}-storage-"
  description = "Allow NFS access from private security group"
  vpc_id      = aws_vpc.main.id

  ingress {
    description     = "NFS from private subnets"
    from_port       = 2049
    to_port         = 2049
    protocol        = "tcp"
    security_groups = [aws_security_group.private.id]
  }

  egress {
    description = "All outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-storage-sg"
  })

  lifecycle {
    create_before_destroy = true
  }
}
