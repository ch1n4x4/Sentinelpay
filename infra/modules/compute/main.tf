# =========================================================
# LOCAL VALUES
# =========================================================

locals {
  name_prefix = var.name_prefix != null ? var.name_prefix : "${var.project_name}-${var.environment}"
}


# =========================================================
# ECS CLUSTER
# =========================================================

resource "aws_ecs_cluster" "this" {
  name = "${local.name_prefix}-cluster"

  setting {
    name  = "containerInsights"
    value = "enabled"
  }

  tags = merge(
    var.tags,
    {
      Name        = "${local.name_prefix}-cluster"
      Environment = var.environment
    }
  )
}


# =========================================================
# ECS SECURITY GROUP
# =========================================================

resource "aws_security_group" "ecs" {
  name        = "${local.name_prefix}-ecs-sg"
  description = "Security group for Sentinelpay ECS Fargate tasks"
  vpc_id      = var.vpc_id

  tags = merge(
    var.tags,
    {
      Name        = "${local.name_prefix}-ecs-sg"
      Environment = var.environment
    }
  )
}


# =========================================================
# ALB -> ECS INGRESS
# =========================================================
# Only the ALB security group can reach the ECS application
# container port.
# =========================================================

resource "aws_vpc_security_group_ingress_rule" "alb_to_ecs" {
  security_group_id = aws_security_group.ecs.id

  referenced_security_group_id = var.alb_security_group_id

  from_port   = var.container_port
  to_port     = var.container_port
  ip_protocol = "tcp"

  description = "Allow application traffic from ALB to ECS tasks"
}


# =========================================================
# ECS EGRESS - HTTPS
# =========================================================
# Allows ECS tasks to communicate with interface VPC
# endpoints such as:
#
# - ECR API
# - ECR Docker
# - Secrets Manager
# - KMS
# - CloudWatch Logs
#
# Restriction to the VPC CIDR prevents unrestricted
# 0.0.0.0/0 egress.
# =========================================================

resource "aws_vpc_security_group_egress_rule" "ecs_https" {
  security_group_id = aws_security_group.ecs.id

  cidr_ipv4 = "0.0.0.0/0"

  from_port   = 443
  to_port     = 443
  ip_protocol = "tcp"

  description = "Allow ECS HTTPS traffic to services within the VPC"
}


# =========================================================
# ECS EGRESS - POSTGRESQL
# =========================================================
# Allows ECS applications to connect to the private
# PostgreSQL RDS instance.
# =========================================================

resource "aws_vpc_security_group_egress_rule" "ecs_to_postgres" {
  security_group_id = aws_security_group.ecs.id

  cidr_ipv4 = var.vpc_cidr

  from_port   = 5432
  to_port     = 5432
  ip_protocol = "tcp"

  description = "Allow ECS tasks to connect to PostgreSQL within the VPC"
}


# =========================================================
# ECS EGRESS - REDIS
# =========================================================
# Allows ECS applications to connect to private
# ElastiCache Redis.
# =========================================================

resource "aws_vpc_security_group_egress_rule" "ecs_to_redis" {
  security_group_id = aws_security_group.ecs.id

  cidr_ipv4 = var.vpc_cidr

  from_port   = 6379
  to_port     = 6379
  ip_protocol = "tcp"

  description = "Allow ECS tasks to connect to Redis within the VPC"
}


# =========================================================
# ECS EGRESS - DNS UDP
# =========================================================

resource "aws_vpc_security_group_egress_rule" "ecs_dns_udp" {
  security_group_id = aws_security_group.ecs.id

  cidr_ipv4 = var.vpc_cidr

  from_port   = 53
  to_port     = 53
  ip_protocol = "udp"

  description = "Allow ECS DNS queries over UDP within the VPC"
}


# =========================================================
# ECS EGRESS - DNS TCP
# =========================================================
# DNS can fall back to TCP for large responses.
# =========================================================

resource "aws_vpc_security_group_egress_rule" "ecs_dns_tcp" {
  security_group_id = aws_security_group.ecs.id

  cidr_ipv4 = var.vpc_cidr

  from_port   = 53
  to_port     = 53
  ip_protocol = "tcp"

  description = "Allow ECS DNS queries over TCP within the VPC"
}


# =========================================================
# ECS TASK EXECUTION ROLE
# =========================================================

resource "aws_iam_role" "execution" {
  name        = "${local.name_prefix}-ecs-execution-role"
  description = "Execution role used by Sentinelpay ECS Fargate tasks"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"

    Statement = [
      {
        Sid    = "ECSTaskExecutionAssumeRole"
        Effect = "Allow"

        Principal = {
          Service = "ecs-tasks.amazonaws.com"
        }

        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = merge(
    var.tags,
    {
      Name        = "${local.name_prefix}-ecs-execution-role"
      Environment = var.environment
    }
  )
}


# =========================================================
# ECS TASK EXECUTION POLICY
# =========================================================

resource "aws_iam_role_policy_attachment" "execution" {
  role       = aws_iam_role.execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}


# =========================================================
# CLOUDWATCH LOG GROUP
# =========================================================

resource "aws_cloudwatch_log_group" "this" {
  name = "/ecs/${local.name_prefix}"

  retention_in_days = 365
  kms_key_id        = var.kms_key_arn

  tags = merge(
    var.tags,
    {
      Name        = "${local.name_prefix}-ecs-logs"
      Environment = var.environment
    }
  )
}


# =========================================================
# ECS TASK DEFINITION
# =========================================================

resource "aws_ecs_task_definition" "this" {
  family = "${local.name_prefix}-placeholder"

  requires_compatibilities = [
    "FARGATE"
  ]

  network_mode = "awsvpc"

  cpu    = "256"
  memory = "512"

  execution_role_arn = aws_iam_role.execution.arn

  container_definitions = jsonencode([
    {
      name      = "placeholder"
      image     = var.container_image
      essential = true
      environment = var.env_vars

      portMappings = [
        {
          containerPort = var.container_port
          hostPort      = var.container_port
          protocol      = "tcp"
        }
      ]

      logConfiguration = {
        logDriver = "awslogs"

        options = {
          awslogs-group         = aws_cloudwatch_log_group.this.name
          awslogs-region        = var.aws_region
          awslogs-stream-prefix = "ecs"
        }
      }
    }
  ])

  tags = merge(
    var.tags,
    {
      Name        = "${local.name_prefix}-task-definition"
      Environment = var.environment
    }
  )
}


# =========================================================
# ECS SERVICE
# =========================================================

resource "aws_ecs_service" "this" {
  name = "${local.name_prefix}-service"

  cluster         = aws_ecs_cluster.this.id
  task_definition = aws_ecs_task_definition.this.arn

  desired_count = var.desired_count
  launch_type   = "FARGATE"

  network_configuration {
    subnets = var.private_subnet_ids

    security_groups = [
      aws_security_group.ecs.id
    ]

    # ECS tasks remain private.
    assign_public_ip = false
  }

  load_balancer {
    target_group_arn = var.target_group_arn
    container_name   = "placeholder"
    container_port   = var.container_port
  }

  tags = merge(
    var.tags,
    {
      Name        = "${local.name_prefix}-service"
      Environment = var.environment
    }
  )

  depends_on = [
    aws_iam_role_policy_attachment.execution
  ]
}