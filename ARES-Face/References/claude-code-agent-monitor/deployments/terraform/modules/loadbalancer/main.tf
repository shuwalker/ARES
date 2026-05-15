# ─────────────────────────────────────────────────────────────────────────────
# Load Balancer module – Application load balancer with WebSocket support
#
# Provisions:
#   - ALB in public subnets
#   - HTTPS listener with TLS termination
#   - HTTP → HTTPS redirect
#   - Weighted target groups for blue/green and canary deployments
#   - Sticky sessions for WebSocket connections
#   - Path-based routing for MCP sidecar (/mcp/*)
#   - Health checks at /api/health
# ─────────────────────────────────────────────────────────────────────────────

# Production TLS enforcement — prevents deploying production without encryption
check "production_tls_required" {
  assert {
    condition     = var.environment != "production" || var.tls_certificate_arn != ""
    error_message = "Production deployments require TLS. Set tls_certificate_arn and domain_name."
  }
}

check "production_domain_required" {
  assert {
    condition     = var.environment != "production" || var.domain_name != ""
    error_message = "Production deployments require a domain name. Set domain_name."
  }
}

locals {
  name_prefix = lower(replace("${var.project_name}-${var.environment}", "_", "-"))

  # Determine whether TLS is configured
  has_tls = var.tls_certificate_arn != ""

  common_tags = merge(
    {
      module = "loadbalancer"
    },
    var.tags,
  )
}

# ─────────────────────────────────────────────────────────────────────────────
# Application Load Balancer
# ─────────────────────────────────────────────────────────────────────────────

resource "aws_lb" "main" {
  name               = "${local.name_prefix}-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = var.security_group_ids
  subnets            = var.public_subnet_ids

  enable_deletion_protection = var.environment == "production" ? true : var.enable_deletion_protection
  enable_http2               = true
  idle_timeout               = 300 # WebSocket connections may be long-lived

  drop_invalid_header_fields = true

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-alb"
  })

  lifecycle {
    prevent_destroy = false
    # For production, set enable_deletion_protection = true above (enforced automatically)
  }
}

# ─────────────────────────────────────────────────────────────────────────────
# HTTPS listener (primary – with weighted target groups for blue/green)
# ─────────────────────────────────────────────────────────────────────────────

resource "aws_lb_listener" "https" {
  count = local.has_tls ? 1 : 0

  load_balancer_arn = aws_lb.main.arn
  port              = 443
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-TLS13-1-2-2021-06"
  certificate_arn   = var.tls_certificate_arn

  default_action {
    type = "forward"

    forward {
      target_group {
        arn    = var.blue_target_group_arn
        weight = var.blue_weight
      }

      target_group {
        arn    = var.green_target_group_arn
        weight = var.green_weight
      }

      stickiness {
        enabled  = true
        duration = 86400
      }
    }
  }

  tags = local.common_tags
}

# ─────────────────────────────────────────────────────────────────────────────
# HTTP listener – redirect to HTTPS when TLS is configured, else forward
# ─────────────────────────────────────────────────────────────────────────────

resource "aws_lb_listener" "http_redirect" {
  count = local.has_tls ? 1 : 0

  load_balancer_arn = aws_lb.main.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type = "redirect"

    redirect {
      port        = "443"
      protocol    = "HTTPS"
      status_code = "HTTP_301"
    }
  }

  tags = local.common_tags
}

resource "aws_lb_listener" "http_forward" {
  count = local.has_tls ? 0 : 1

  load_balancer_arn = aws_lb.main.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type = "forward"

    forward {
      target_group {
        arn    = var.blue_target_group_arn
        weight = var.blue_weight
      }

      target_group {
        arn    = var.green_target_group_arn
        weight = var.green_weight
      }

      stickiness {
        enabled  = true
        duration = 86400
      }
    }
  }

  tags = local.common_tags
}

# ─────────────────────────────────────────────────────────────────────────────
# MCP sidecar target group
# ─────────────────────────────────────────────────────────────────────────────

resource "aws_lb_target_group" "mcp" {
  name_prefix = "mcp-"
  port        = var.mcp_port
  protocol    = "HTTP"
  vpc_id      = var.vpc_id
  target_type = "ip"

  health_check {
    enabled             = true
    path                = "/"
    port                = tostring(var.mcp_port)
    protocol            = "HTTP"
    healthy_threshold   = var.health_check_healthy_threshold
    unhealthy_threshold = var.health_check_unhealthy_threshold
    timeout             = var.health_check_timeout
    interval            = var.health_check_interval
    matcher             = "200-404"
  }

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-mcp-tg"
  })

  lifecycle {
    create_before_destroy = true
  }
}

# ─────────────────────────────────────────────────────────────────────────────
# Path-based routing rule for MCP sidecar (/mcp/*)
# ─────────────────────────────────────────────────────────────────────────────

resource "aws_lb_listener_rule" "mcp_https" {
  count = local.has_tls ? 1 : 0

  listener_arn = aws_lb_listener.https[0].arn
  priority     = 10

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.mcp.arn
  }

  condition {
    path_pattern {
      values = ["/mcp", "/mcp/*"]
    }
  }

  tags = local.common_tags
}

resource "aws_lb_listener_rule" "mcp_http" {
  count = local.has_tls ? 0 : 1

  listener_arn = aws_lb_listener.http_forward[0].arn
  priority     = 10

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.mcp.arn
  }

  condition {
    path_pattern {
      values = ["/mcp", "/mcp/*"]
    }
  }

  tags = local.common_tags
}

# ─────────────────────────────────────────────────────────────────────────────
# Weight sum validation
# ─────────────────────────────────────────────────────────────────────────────

check "lb_weight_sum" {
  assert {
    condition     = var.blue_weight + var.green_weight == 100
    error_message = "blue_weight (${var.blue_weight}) + green_weight (${var.green_weight}) must sum to 100 for correct traffic routing."
  }
}
