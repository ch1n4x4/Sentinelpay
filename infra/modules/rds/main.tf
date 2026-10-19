# ---------------------------------------------------------
# RDS Subnet Group
# ---------------------------------------------------------

resource "aws_db_subnet_group" "this" {
  name       = "${var.project_name}-${var.environment}-db-subnets"
  subnet_ids = var.private_subnet_ids

  tags = {
    Name        = "${var.project_name}-${var.environment}-db-subnets"
    Environment = var.environment
  }
}

# ---------------------------------------------------------
# RDS Security Group
# ---------------------------------------------------------

resource "aws_security_group" "this" {
  name        = "${var.project_name}-${var.environment}-rds-sg"
  description = "PostgreSQL access from application security group only"
  vpc_id      = var.vpc_id

  tags = {
    Name        = "${var.project_name}-${var.environment}-rds-sg"
    Environment = var.environment
  }
}

# ---------------------------------------------------------
# Application -> PostgreSQL
# ---------------------------------------------------------

resource "aws_vpc_security_group_ingress_rule" "application" {
  security_group_id            = aws_security_group.this.id
  referenced_security_group_id = var.application_security_group_id

  from_port   = 5432
  to_port     = 5432
  ip_protocol = "tcp"

  description = "Allow PostgreSQL traffic from application security group"
}

# ---------------------------------------------------------
# RDS Enhanced Monitoring IAM Role
# CKV_AWS_118
# ---------------------------------------------------------

resource "aws_iam_role" "rds_monitoring" {
  name = "${var.project_name}-${var.environment}-rds-monitoring"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"

    Statement = [
      {
        Effect = "Allow"

        Principal = {
          Service = "monitoring.rds.amazonaws.com"
        }

        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = {
    Name        = "${var.project_name}-${var.environment}-rds-monitoring"
    Environment = var.environment
  }
}

resource "aws_iam_role_policy_attachment" "rds_monitoring" {
  role = aws_iam_role.rds_monitoring.name

  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonRDSEnhancedMonitoringRole"
}

# ---------------------------------------------------------
# PostgreSQL Parameter Group
#
# CKV2_AWS_30
# CKV2_AWS_69
# ---------------------------------------------------------

resource "aws_db_parameter_group" "this" {
  name   = "${var.project_name}-${var.environment}-postgres"
  family = var.postgres_parameter_group_family

  # -------------------------------------------------------
  # Enforce SSL/TLS connections
  # CKV2_AWS_69
  # -------------------------------------------------------

  parameter {
    name         = "rds.force_ssl"
    value        = "1"
    apply_method = "pending-reboot"
  }

  # -------------------------------------------------------
  # PostgreSQL query logging
  # CKV2_AWS_30
  # -------------------------------------------------------

  parameter {
    name  = "log_statement"
    value = "ddl"
  }

  parameter {
    name  = "log_min_duration_statement"
    value = "1000"
  }

  parameter {
    name  = "log_connections"
    value = "1"
  }

  parameter {
    name  = "log_disconnections"
    value = "1"
  }

  tags = {
    Name        = "${var.project_name}-${var.environment}-postgres-parameters"
    Environment = var.environment
  }
}

# ---------------------------------------------------------
# PostgreSQL RDS Instance
# ---------------------------------------------------------

resource "aws_db_instance" "this" {
  identifier = "${var.project_name}-${var.environment}-postgres"

  # -------------------------------------------------------
  # Engine
  # -------------------------------------------------------

  engine         = "postgres"
  engine_version = var.postgres_version
  instance_class = var.instance_class

  # -------------------------------------------------------
  # Storage
  # -------------------------------------------------------

  allocated_storage     = 20
  max_allocated_storage = 100
  storage_type          = "gp3"

  storage_encrypted = true
  kms_key_id        = var.kms_key_arn

  # -------------------------------------------------------
  # Database configuration
  # -------------------------------------------------------

  db_name  = var.db_name
  username = var.db_username
  password = var.db_password

  parameter_group_name = aws_db_parameter_group.this.name

  # -------------------------------------------------------
  # Networking
  # -------------------------------------------------------

  db_subnet_group_name = aws_db_subnet_group.this.name

  vpc_security_group_ids = [
    aws_security_group.this.id
  ]

  publicly_accessible = false

  # -------------------------------------------------------
  # IAM Database Authentication
  # CKV_AWS_161
  # -------------------------------------------------------

  iam_database_authentication_enabled = true

  # -------------------------------------------------------
  # Backups
  # -------------------------------------------------------

  backup_retention_period = 0 #changed for dast testing

  copy_tags_to_snapshot = true

  # -------------------------------------------------------
  # High Availability
  # CKV_AWS_157
  # -------------------------------------------------------

  multi_az = true

  # -------------------------------------------------------
  # CloudWatch PostgreSQL Logs
  # CKV_AWS_129
  # -------------------------------------------------------

  enabled_cloudwatch_logs_exports = [
    "postgresql",
    "upgrade"
  ]

  # -------------------------------------------------------
  # Enhanced Monitoring
  # CKV_AWS_118
  # -------------------------------------------------------

  monitoring_interval = 60
  monitoring_role_arn = aws_iam_role.rds_monitoring.arn

  # -------------------------------------------------------
  # Performance Insights
  # CKV_AWS_353
  # -------------------------------------------------------

  performance_insights_enabled          = true
  performance_insights_kms_key_id       = var.kms_key_arn
  performance_insights_retention_period = 7

  # -------------------------------------------------------
  # Maintenance
  # -------------------------------------------------------

  auto_minor_version_upgrade = true

  # -------------------------------------------------------
  # Deletion Protection
  # CKV_AWS_293
  # -------------------------------------------------------

  deletion_protection = false

  skip_final_snapshot = true

  final_snapshot_identifier = "${var.project_name}-${var.environment}-postgres-final"

  # -------------------------------------------------------
  # Tags
  # -------------------------------------------------------

  tags = {
    Name        = "${var.project_name}-${var.environment}-postgres"
    Environment = var.environment
  }

  depends_on = [
    aws_iam_role_policy_attachment.rds_monitoring
  ]
}