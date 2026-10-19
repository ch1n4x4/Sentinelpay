# ---------------------------------------------------------
# ALB Security Group
# ---------------------------------------------------------

resource "aws_security_group" "alb" {
  name        = "${var.project_name}-${var.environment}-alb-sg"
  description = "Security group for Sentinelpay Application Load Balancer"
  vpc_id      = var.vpc_id

  tags = {
    Name        = "${var.project_name}-${var.environment}-alb-sg"
    Environment = var.environment
  }
}
# ---------------------------------------------------------
# HTTPS ingress
# ---------------------------------------------------------

resource "aws_vpc_security_group_ingress_rule" "https" {
  security_group_id = aws_security_group.alb.id

  cidr_ipv4   = "0.0.0.0/0"
  from_port   = 443
  to_port     = 443
  ip_protocol = "tcp"

  description = "Allow HTTPS from the internet to the ALB"
}

# ---------------------------------------------------------
# HTTP ingress - redirect only
# ---------------------------------------------------------

resource "aws_vpc_security_group_ingress_rule" "http_redirect" {
  # checkov:skip=CKV_AWS_260:Port 80 is used only for HTTP to HTTPS redirection

  security_group_id = aws_security_group.alb.id

  cidr_ipv4   = "0.0.0.0/0"
  from_port   = 80
  to_port     = 80
  ip_protocol = "tcp"

  description = "Allow HTTP only for redirecting requests to HTTPS"
}

# ---------------------------------------------------------
# ALB outbound traffic
# ---------------------------------------------------------

resource "aws_vpc_security_group_egress_rule" "alb_to_ecs" {
  security_group_id = aws_security_group.alb.id

  cidr_ipv4 = var.vpc_cidr

  from_port   = 8001
  to_port     = 8002
  ip_protocol = "tcp"

  description = "Allow ALB outbound traffic to ECS targets within the VPC"
}
# ---------------------------------------------------------
# Application Load Balancer
# ---------------------------------------------------------

resource "aws_lb" "this" {
  # tfsec:ignore:aws-elb-alb-not-public
  # The ALB is intentionally internet-facing and deployed in public subnets.
  # Backend ECS services remain in private subnets, with the ALB acting as
  # the controlled public ingress point.

  # checkov:skip=CKV2_AWS_76:ALB is associated with a WAFv2 WebACL containing AWSManagedRulesKnownBadInputsRuleSet for Log4j protection

  name               = "${var.project_name}-${var.environment}-alb"
  internal           = false 
  load_balancer_type = "application"

  security_groups = [
    aws_security_group.alb.id
  ]

  subnets = var.public_subnet_ids

  enable_deletion_protection = false
  drop_invalid_header_fields = true
  enable_http2               = true

  access_logs {
    bucket  = var.alb_logs_bucket
    prefix  = "alb"
    enabled = false #changed for dast testing
  }

  tags = {
    Name        = "${var.project_name}-${var.environment}-alb"
    Environment = var.environment
    ManagedBy   = "Terraform"
  }
}
# ---------------------------------------------------------
# ALB Target Group
# ---------------------------------------------------------

resource "aws_lb_target_group" "this" {
  # checkov:skip=CKV_AWS_378:TLS terminates at the ALB and backend traffic remains inside the private VPC

  name        = "${var.project_name}-${var.environment}-payments-tg"
  port        = 8001
  protocol    = "HTTP"
  vpc_id      = var.vpc_id
  target_type = "ip"

  health_check {
    enabled             = true
    path                = "/health"
    protocol            = "HTTP"
    matcher             = "200-399"
    healthy_threshold   = 2
    unhealthy_threshold = 3
    interval            = 30
    timeout             = 5
  }

  tags = {
    Name = "${var.project_name}-${var.environment}-tg"
  }
}

resource "aws_lb_target_group" "kyc" {
  name        = "${var.project_name}-${var.environment}-kyc-tg"
  port        = 8002
  protocol    = "HTTP"
  vpc_id      = var.vpc_id
  target_type = "ip"

  health_check {
    enabled             = true
    path                = "/health"
    protocol            = "HTTP"
    matcher             = "200-399"
    healthy_threshold   = 2
    unhealthy_threshold = 3
    interval            = 30
    timeout             = 5
  }
  tags = {
    Name = "${var.project_name}-${var.environment}-tg"
  }
}

# ---------------------------------------------------------
# HTTPS Listener
# ---------------------------------------------------------

resource "aws_lb_listener" "https" {
  count = var.acm_certificate_arn != null ? 1 : 0

  load_balancer_arn = aws_lb.this.arn
  port              = 443
  protocol          = "HTTPS"

  ssl_policy      = "ELBSecurityPolicy-TLS13-1-2-2021-06"
  certificate_arn = var.acm_certificate_arn

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.this.arn
  }
}

resource "aws_lb_listener_rule" "kyc_routing" {
  listener_arn = var.acm_certificate_arn != null ? aws_lb_listener.https[0].arn : aws_lb_listener.http_forward[0].arn
  priority     = 100

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.kyc.arn
  }

  condition {
    path_pattern {
      values = ["/v1/verify*", "/v1/documents*"]
    }
  }
}

# ---------------------------------------------------------
# HTTP Forward Listener (used when acm_certificate_arn is null)
# ---------------------------------------------------------
resource "aws_lb_listener" "http_forward" {
  count             = var.acm_certificate_arn == null ? 1 : 0
  load_balancer_arn = aws_lb.this.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.this.arn
  }
}

# ---------------------------------------------------------
# HTTP -> HTTPS Redirect Listener
# ---------------------------------------------------------

resource "aws_lb_listener" "http" {
  count = var.acm_certificate_arn != null ? 1 : 0

  load_balancer_arn = aws_lb.this.arn
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
  depends_on = [
    aws_lb_listener.http_forward
  ]
}

# ---------------------------------------------------------
# AWS WAFv2 Web ACL
# ---------------------------------------------------------

resource "aws_wafv2_web_acl" "this" {
  name  = "${var.project_name}-${var.environment}-waf"
  scope = "REGIONAL"

  default_action {
    allow {}
  }

  # -------------------------------------------------------
  # AWS Managed Common Rule Set
  # -------------------------------------------------------

  rule {
    name     = "AWS-AWSManagedRulesCommonRuleSet"
    priority = 1

    override_action {
      none {}
    }

    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesCommonRuleSet"
        vendor_name = "AWS"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "AWSManagedRulesCommonRuleSet"
      sampled_requests_enabled   = true
    }
  }

  # -------------------------------------------------------
  # AWS Known Bad Inputs / Log4j Protection
  # ---------------------------------------------------------

  rule {
    name     = "AWS-AWSManagedRulesKnownBadInputsRuleSet"
    priority = 2

    override_action {
      none {}
    }

    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesKnownBadInputsRuleSet"
        vendor_name = "AWS"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "AWSManagedRulesKnownBadInputsRuleSet"
      sampled_requests_enabled   = true
    }
  }

  visibility_config {
    cloudwatch_metrics_enabled = true
    metric_name                = "${var.project_name}-${var.environment}-waf"
    sampled_requests_enabled   = true
  }

  tags = {
    Name = "${var.project_name}-${var.environment}-waf"
  }
}

# ---------------------------------------------------------
# Associate WAF with ALB
# ---------------------------------------------------------

resource "aws_wafv2_web_acl_association" "alb" {
  resource_arn = aws_lb.this.arn
  web_acl_arn  = aws_wafv2_web_acl.this.arn
}

# ---------------------------------------------------------
# WAF CloudWatch Log Group
# ---------------------------------------------------------

resource "aws_cloudwatch_log_group" "waf" {
  name = "aws-waf-logs-${var.project_name}-${var.environment}"

  retention_in_days = 365
  kms_key_id        = var.kms_key_arn

  tags = {
    Name = "aws-waf-logs-${var.project_name}-${var.environment}"
  }
}

# ---------------------------------------------------------
# WAF Logging Configuration
# ---------------------------------------------------------

resource "aws_wafv2_web_acl_logging_configuration" "this" {
  resource_arn = aws_wafv2_web_acl.this.arn

  log_destination_configs = [
    aws_cloudwatch_log_group.waf.arn
  ]

  redacted_fields {
    single_header {
      name = "authorization"
    }
  }

  depends_on = [
    aws_cloudwatch_log_group.waf,
    aws_wafv2_web_acl.this
  ]
}