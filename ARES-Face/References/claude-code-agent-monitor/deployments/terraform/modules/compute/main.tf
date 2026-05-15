# ─────────────────────────────────────────────────────────────────────────────
# Compute module – Container orchestration with blue/green slot support
#
# Provisions an ECS Fargate service with:
#   - Main application container (Express + React)
#   - MCP sidecar container
#   - EFS persistent volume for SQLite
#   - Auto-scaling policies
#   - Blue/green deployment slot via variable
# ─────────────────────────────────────────────────────────────────────────────

locals {
  name_prefix = lower(replace("${var.project_name}-${var.environment}", "_", "-"))
  slot_name   = "${local.name_prefix}-${var.deployment_slot}"

  common_tags = merge(
    {
      module          = "compute"
      deployment_slot = var.deployment_slot
    },
    var.tags,
  )
}

# ─────────────────────────────────────────────────────────────────────────────
# ECS Cluster (shared across slots)
# ─────────────────────────────────────────────────────────────────────────────

resource "aws_ecs_cluster" "main" {
  name = "${local.name_prefix}-cluster"

  setting {
    name  = "containerInsights"
    value = "enabled"
  }

  configuration {
    execute_command_configuration {
      logging = "DEFAULT"
    }
  }

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-cluster"
  })

  lifecycle {
    prevent_destroy = false
  }
}

resource "aws_ecs_cluster_capacity_providers" "main" {
  cluster_name = aws_ecs_cluster.main.name

  capacity_providers = ["FARGATE", "FARGATE_SPOT"]

  default_capacity_provider_strategy {
    base              = 1
    weight            = 1
    capacity_provider = "FARGATE"
  }
}

# ─────────────────────────────────────────────────────────────────────────────
# IAM roles
# ─────────────────────────────────────────────────────────────────────────────

data "aws_region" "current" {}
data "aws_caller_identity" "current" {}

resource "aws_iam_role" "task_execution" {
  name = "${local.slot_name}-task-exec"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "ecs-tasks.amazonaws.com"
      }
    }]
  })

  tags = local.common_tags
}

resource "aws_iam_role_policy_attachment" "task_execution" {
  role       = aws_iam_role.task_execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

resource "aws_iam_role" "task" {
  name = "${local.slot_name}-task"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "ecs-tasks.amazonaws.com"
      }
    }]
  })

  tags = local.common_tags
}

# EFS access policy for the task role
resource "aws_iam_role_policy" "task_efs" {
  name = "${local.slot_name}-efs-access"
  role = aws_iam_role.task.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "elasticfilesystem:ClientMount",
        "elasticfilesystem:ClientWrite",
        "elasticfilesystem:ClientRootAccess",
      ]
      Resource = "arn:aws:elasticfilesystem:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:file-system/${var.storage_filesystem_id}"
    }]
  })
}

# ─────────────────────────────────────────────────────────────────────────────
# CloudWatch log group
# ─────────────────────────────────────────────────────────────────────────────

resource "aws_cloudwatch_log_group" "app" {
  name              = "/ecs/${local.slot_name}"
  retention_in_days = 30

  tags = local.common_tags
}

# ─────────────────────────────────────────────────────────────────────────────
# Task definition
# ─────────────────────────────────────────────────────────────────────────────

resource "aws_ecs_task_definition" "app" {
  family                   = local.slot_name
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = tostring(var.cpu)
  memory                   = tostring(var.memory)
  execution_role_arn       = aws_iam_role.task_execution.arn
  task_role_arn            = aws_iam_role.task.arn

  container_definitions = jsonencode(concat(
    [
      {
        name      = "app"
        image     = var.container_image
        essential = true
        cpu       = var.mcp_container_image != "" ? floor(var.cpu * 0.75) : var.cpu
        memory    = var.mcp_container_image != "" ? floor(var.memory * 0.75) : var.memory

        portMappings = [
          {
            containerPort = var.app_port
            protocol      = "tcp"
          }
        ]

        environment = [
          for k, v in var.environment_variables : {
            name  = k
            value = v
          }
        ]

        mountPoints = [
          {
            sourceVolume  = "app-data"
            containerPath = "/app/data"
            readOnly      = false
          }
        ]

        healthCheck = {
          command     = ["CMD-SHELL", "wget --no-verbose --tries=1 --spider http://localhost:${var.app_port}${var.health_check_path} || exit 1"]
          interval    = 30
          timeout     = 5
          retries     = 3
          startPeriod = 60
        }

        logConfiguration = {
          logDriver = "awslogs"
          options = {
            "awslogs-group"         = aws_cloudwatch_log_group.app.name
            "awslogs-region"        = data.aws_region.current.name
            "awslogs-stream-prefix" = "app"
          }
        }
      }
    ],
    var.mcp_container_image != "" ? [
      {
        name      = "mcp-sidecar"
        image     = var.mcp_container_image
        essential = false
        cpu       = floor(var.cpu * 0.25)
        memory    = floor(var.memory * 0.25)

        portMappings = [
          {
            containerPort = var.mcp_port
            protocol      = "tcp"
          }
        ]

        environment = [
          {
            name  = "NODE_ENV"
            value = "production"
          },
          {
            name  = "MCP_PORT"
            value = tostring(var.mcp_port)
          }
        ]

        logConfiguration = {
          logDriver = "awslogs"
          options = {
            "awslogs-group"         = aws_cloudwatch_log_group.app.name
            "awslogs-region"        = data.aws_region.current.name
            "awslogs-stream-prefix" = "mcp"
          }
        }
      }
    ] : []
  ))

  volume {
    name = "app-data"

    efs_volume_configuration {
      file_system_id     = var.storage_filesystem_id
      root_directory     = "/"
      transit_encryption = "ENABLED"

      authorization_config {
        iam = "ENABLED"
      }
    }
  }

  tags = local.common_tags

  lifecycle {
    create_before_destroy = true
  }
}

# ─────────────────────────────────────────────────────────────────────────────
# Target group (registered with LB by the loadbalancer module)
# ─────────────────────────────────────────────────────────────────────────────

resource "aws_lb_target_group" "app" {
  name_prefix = substr(var.deployment_slot, 0, 5)
  port        = var.app_port
  protocol    = "HTTP"
  vpc_id      = var.vpc_id
  target_type = "ip"

  health_check {
    enabled             = true
    path                = var.health_check_path
    port                = "traffic-port"
    protocol            = "HTTP"
    healthy_threshold   = 2
    unhealthy_threshold = 3
    timeout             = 5
    interval            = 30
    matcher             = "200"
  }

  stickiness {
    type            = "lb_cookie"
    cookie_duration = 86400
    enabled         = true
  }

  deregistration_delay = 60

  tags = merge(local.common_tags, {
    Name = "${local.slot_name}-tg"
  })

  lifecycle {
    create_before_destroy = true
  }
}

# ─────────────────────────────────────────────────────────────────────────────
# ECS Service
# ─────────────────────────────────────────────────────────────────────────────

resource "aws_ecs_service" "app" {
  name                              = local.slot_name
  cluster                           = aws_ecs_cluster.main.id
  task_definition                   = aws_ecs_task_definition.app.arn
  desired_count                     = var.desired_count
  launch_type                       = "FARGATE"
  platform_version                  = "LATEST"
  health_check_grace_period_seconds = 120
  enable_execute_command            = var.environment != "production"

  network_configuration {
    subnets          = var.private_subnet_ids
    security_groups  = var.security_group_ids
    assign_public_ip = false
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.app.arn
    container_name   = "app"
    container_port   = var.app_port
  }

  deployment_configuration {
    maximum_percent         = 200
    minimum_healthy_percent = 100
  }

  deployment_circuit_breaker {
    enable   = true
    rollback = true
  }

  tags = local.common_tags

  lifecycle {
    ignore_changes = [desired_count]
  }
}

# ─────────────────────────────────────────────────────────────────────────────
# Auto-scaling
# ─────────────────────────────────────────────────────────────────────────────

resource "aws_appautoscaling_target" "ecs" {
  count = var.max_count > 0 ? 1 : 0

  max_capacity       = var.max_count
  min_capacity       = var.min_count
  resource_id        = "service/${aws_ecs_cluster.main.name}/${aws_ecs_service.app.name}"
  scalable_dimension = "ecs:service:DesiredCount"
  service_namespace  = "ecs"

  tags = local.common_tags
}

resource "aws_appautoscaling_policy" "cpu" {
  count = var.max_count > 0 ? 1 : 0

  name               = "${local.slot_name}-cpu-scaling"
  policy_type        = "TargetTrackingScaling"
  resource_id        = aws_appautoscaling_target.ecs[0].resource_id
  scalable_dimension = aws_appautoscaling_target.ecs[0].scalable_dimension
  service_namespace  = aws_appautoscaling_target.ecs[0].service_namespace

  target_tracking_scaling_policy_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ECSServiceAverageCPUUtilization"
    }
    target_value       = var.autoscaling_cpu_target
    scale_in_cooldown  = 300
    scale_out_cooldown = 60
  }
}

resource "aws_appautoscaling_policy" "memory" {
  count = var.max_count > 0 ? 1 : 0

  name               = "${local.slot_name}-memory-scaling"
  policy_type        = "TargetTrackingScaling"
  resource_id        = aws_appautoscaling_target.ecs[0].resource_id
  scalable_dimension = aws_appautoscaling_target.ecs[0].scalable_dimension
  service_namespace  = aws_appautoscaling_target.ecs[0].service_namespace

  target_tracking_scaling_policy_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ECSServiceAverageMemoryUtilization"
    }
    target_value       = var.autoscaling_memory_target
    scale_in_cooldown  = 300
    scale_out_cooldown = 60
  }
}
