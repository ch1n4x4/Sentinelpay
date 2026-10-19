data "aws_caller_identity" "current" {}

# ---------------------------------------------------------
# Secrets Manager Secret
# ---------------------------------------------------------

resource "aws_secretsmanager_secret" "database" {
  name = "${var.project_name}/${var.environment}/database"

  kms_key_id = var.kms_key_arn

  tags = {
    Name        = "${var.project_name}-${var.environment}-database-secret"
    Environment = var.environment
    ManagedBy   = "Terraform"
  }
}

resource "aws_secretsmanager_secret_version" "database" {
  secret_id = aws_secretsmanager_secret.database.id

  secret_string = jsonencode({
    engine   = "postgres"
    host     = var.db_host
    port     = var.db_port
    dbname   = var.db_name
    username = var.db_username
    password = var.db_password
  })
}

# ---------------------------------------------------------
# Lambda Security Group
# ---------------------------------------------------------

resource "aws_security_group" "rotation" {
  name        = "${var.project_name}-${var.environment}-rotation-sg"
  description = "Security group for Secrets Manager PostgreSQL rotation Lambda"
  vpc_id      = var.vpc_id

  tags = {
    Name        = "${var.project_name}-${var.environment}-rotation-sg"
    Environment = var.environment
    ManagedBy   = "Terraform"
  }
}

# ---------------------------------------------------------
# Allow Lambda to connect to RDS PostgreSQL
# ---------------------------------------------------------

resource "aws_vpc_security_group_ingress_rule" "rotation_to_rds" {
  security_group_id = var.rds_security_group_id

  referenced_security_group_id = aws_security_group.rotation.id

  description = "Allow PostgreSQL traffic from Secrets Manager rotation Lambda"

  from_port   = 5432
  to_port     = 5432
  ip_protocol = "tcp"
}

# ---------------------------------------------------------
# Lambda outbound connectivity
# ---------------------------------------------------------

resource "aws_vpc_security_group_egress_rule" "rotation" {
  security_group_id = aws_security_group.rotation.id

  description = "Allow outbound traffic from Secrets Manager rotation Lambda"

  cidr_ipv4   = "0.0.0.0/0"
  ip_protocol = "-1"
}

# ---------------------------------------------------------
# Lambda IAM Role
# ---------------------------------------------------------

resource "aws_iam_role" "rotation" {
  name = "${var.project_name}-${var.environment}-rotation-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"

    Statement = [
      {
        Sid    = "LambdaAssumeRole"
        Effect = "Allow"

        Principal = {
          Service = "lambda.amazonaws.com"
        }

        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = {
    Name        = "${var.project_name}-${var.environment}-rotation-role"
    Environment = var.environment
    ManagedBy   = "Terraform"
  }
}

# ---------------------------------------------------------
# Dead Letter Queue
# CKV_AWS_116
# ---------------------------------------------------------

resource "aws_sqs_queue" "rotation_dlq" {
  name = "${var.project_name}-${var.environment}-rotation-dlq"

  message_retention_seconds = 1209600

  kms_master_key_id = var.kms_key_arn

  tags = {
    Name        = "${var.project_name}-${var.environment}-rotation-dlq"
    Environment = var.environment
    ManagedBy   = "Terraform"
  }
}

# ---------------------------------------------------------
# Lambda IAM Policy
# ---------------------------------------------------------

resource "aws_iam_role_policy" "rotation" {
  name = "${var.project_name}-${var.environment}-rotation-policy"
  role = aws_iam_role.rotation.id

  policy = jsonencode({
    Version = "2012-10-17"

    Statement = [
      {
        Sid    = "SecretRotation"
        Effect = "Allow"

        Action = [
          "secretsmanager:DescribeSecret",
          "secretsmanager:GetSecretValue",
          "secretsmanager:PutSecretValue",
          "secretsmanager:UpdateSecretVersionStage"
        ]

        Resource = aws_secretsmanager_secret.database.arn
      },

      {
        Sid    = "GeneratePassword"
        Effect = "Allow"

        Action = [
          "secretsmanager:GetRandomPassword"
        ]

        Resource = "*"
      },

      {
        Sid    = "UseKMSKey"
        Effect = "Allow"

        Action = [
          "kms:Decrypt",
          "kms:Encrypt",
          "kms:GenerateDataKey"
        ]

        Resource = var.kms_key_arn
      },

      {
        Sid    = "SendToDeadLetterQueue"
        Effect = "Allow"

        Action = [
          "sqs:SendMessage"
        ]

        Resource = aws_sqs_queue.rotation_dlq.arn
      },

      {
        Sid    = "WriteXRayTelemetry"
        Effect = "Allow"

        Action = [
          "xray:PutTraceSegments",
          "xray:PutTelemetryRecords"
        ]

        Resource = "*"
      }
    ]
  })
}

# ---------------------------------------------------------
# Lambda VPC Permissions
# ---------------------------------------------------------

resource "aws_iam_role_policy_attachment" "lambda_vpc_access" {
  role = aws_iam_role.rotation.name

  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaVPCAccessExecutionRole"
}

# ---------------------------------------------------------
# AWS Signer Profile
# CKV_AWS_272
# ---------------------------------------------------------

resource "aws_signer_signing_profile" "rotation" {
  name_prefix = "${var.project_name}_${var.environment}_rotation_"

  platform_id = "AWSLambda-SHA384-ECDSA"

  signature_validity_period {
    value = 135
    type  = "MONTHS"
  }

  tags = {
    Name        = "${var.project_name}-${var.environment}-rotation-signing-profile"
    Environment = var.environment
    ManagedBy   = "Terraform"
  }
}

# ---------------------------------------------------------
# Lambda Code Signing Configuration
# CKV_AWS_272
# ---------------------------------------------------------

resource "aws_lambda_code_signing_config" "rotation" {
  description = "Code signing configuration for PostgreSQL rotation Lambda"

  allowed_publishers {
    signing_profile_version_arns = [
      aws_signer_signing_profile.rotation.version_arn
    ]
  }

  policies {
    untrusted_artifact_on_deployment = "Warn" #changed for dast testing
  }

  tags = {
    Name        = "${var.project_name}-${var.environment}-rotation-code-signing"
    Environment = var.environment
    ManagedBy   = "Terraform"
  }
}

# ---------------------------------------------------------
# Lambda Function
# ---------------------------------------------------------

resource "aws_lambda_function" "rotation" {
  function_name = "${var.project_name}-${var.environment}-postgres-rotation"

  role = aws_iam_role.rotation.arn

  runtime = "python3.13"
  handler = "lambda_function.lambda_handler"

  filename         = var.rotation_lambda_zip
  source_code_hash = filebase64sha256(var.rotation_lambda_zip)

  timeout     = 60
  memory_size = 256

  # -------------------------------------------------------
  # CKV_AWS_272 - Code signing
  # -------------------------------------------------------

  code_signing_config_arn = aws_lambda_code_signing_config.rotation.arn

  # -------------------------------------------------------
  # CKV_AWS_115 - Reserved concurrency
  # -------------------------------------------------------

  #reserved_concurrent_executions = 5 #removed for dast testing

  # -------------------------------------------------------
  # CKV_AWS_116 - Dead Letter Queue
  # -------------------------------------------------------

  dead_letter_config {
    target_arn = aws_sqs_queue.rotation_dlq.arn
  }

  # -------------------------------------------------------
  # CKV_AWS_50 - X-Ray tracing
  # -------------------------------------------------------

  tracing_config {
    mode = "Active"
  }

  # -------------------------------------------------------
  # VPC Configuration
  # -------------------------------------------------------

  vpc_config {
    subnet_ids = var.private_subnet_ids

    security_group_ids = [
      aws_security_group.rotation.id
    ]
  }

  depends_on = [
    aws_iam_role_policy.rotation,
    aws_iam_role_policy_attachment.lambda_vpc_access,
    aws_lambda_code_signing_config.rotation
  ]

  tags = {
    Name        = "${var.project_name}-${var.environment}-postgres-rotation"
    Environment = var.environment
    ManagedBy   = "Terraform"
  }
}

# ---------------------------------------------------------
# Allow Secrets Manager to invoke Lambda
# ---------------------------------------------------------

resource "aws_lambda_permission" "secrets_manager" {
  statement_id = "AllowSecretsManager"

  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.rotation.function_name

  principal = "secretsmanager.amazonaws.com"

  source_account = data.aws_caller_identity.current.account_id

  source_arn = aws_secretsmanager_secret.database.arn
}

# ---------------------------------------------------------
# Secret Rotation
# ---------------------------------------------------------

resource "aws_secretsmanager_secret_rotation" "database" {
  secret_id = aws_secretsmanager_secret.database.id

  rotation_lambda_arn = aws_lambda_function.rotation.arn

  rotation_rules {
    automatically_after_days = 30
  }

  depends_on = [
    aws_lambda_permission.secrets_manager
  ]
}