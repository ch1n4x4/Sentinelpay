module "network" { #tfsec:ignore:aws-iam-no-policy-wildcards
  source = "../../modules/network"

  project_name = var.project_name
  environment  = var.environment

  vpc_cidr = var.vpc_cidr

  public_subnet_cidrs  = var.public_subnet_cidrs
  private_subnet_cidrs = var.private_subnet_cidrs
  availability_zones   = var.availability_zones

  kms_key_arn = module.kms.key_arn

  tags = {
    Project     = var.project_name
    Environment = var.environment
    ManagedBy   = "Terraform"
  }
}


module "edge" {
  source = "../../modules/edge"

  project_name = var.project_name
  environment  = var.environment

  vpc_id   = module.network.vpc_id
  vpc_cidr = var.vpc_cidr

  public_subnet_ids = module.network.public_subnet_ids

  container_port = var.container_port

  acm_certificate_arn = var.acm_certificate_arn

  alb_logs_bucket = module.data.access_logs_bucket_name

  kms_key_arn = module.kms.key_arn
}


module "compute_payments" {
  source = "../../modules/compute"

  project_name = var.project_name
  environment  = var.environment
  name_prefix  = "${var.project_name}-${var.environment}-payments"

  # ======================================================
  # NETWORK
  # ======================================================

  vpc_id   = module.network.vpc_id
  vpc_cidr = var.vpc_cidr

  private_subnet_ids = module.network.private_subnet_ids

  # ======================================================
  # ALB / EDGE
  # ======================================================

  alb_security_group_id = module.edge.alb_security_group_id
  target_group_arn      = module.edge.target_group_arn

  # ======================================================
  # ECS
  # ======================================================

  container_image = "865266771761.dkr.ecr.eu-west-1.amazonaws.com/sentinelpay-dev-payments-api:latest"
  container_port  = 8001
  desired_count   = var.desired_count

  # ======================================================
  # KMS / REGION
  # ======================================================

  kms_key_arn = module.kms.key_arn
  aws_region  = var.aws_region

  env_vars = [
    { name = "ENVIRONMENT", value = "development" },
    { name = "DATABASE_URL", value = "postgresql://sentinelpay_admin:${random_password.database.result}@${module.rds.endpoint}:${module.rds.port}/sentinelpay" },
    { name = "REDIS_URL", value = "rediss://:${module.data.redis_password}@${module.data.redis_endpoint}:6379/0" },
    { name = "RATELIMIT_STORAGE_URI", value = "rediss://:${module.data.redis_password}@${module.data.redis_endpoint}:6379/2" },
    { name = "SESSION_SIGNING_KEY", value = "test-session-key-12345" },
    { name = "RATE_LIMIT_KEY_SECRET", value = "test-rate-limit-key" },
    {
      name  = "JWT_PUBLIC_KEY"
      value = <<-EOT
-----BEGIN PUBLIC KEY-----
MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEAqRcOAmRGWvYSP2gloWjz
6czc3S5MUTLUAczkAAJ63xhPfhw+ku0WYnjR4+h3l1JTtSj8i0QTVpzs6rW9wEOA
9a2c7wBeWmtSsAGV3z2Xa5wkwCf7JzX8zoCRXnnyyMTtDvTkKf+clXDh6I+x4sRJ
YII/kSnSPRoi5QouWRF0+I27ShXIvPHIzZ56j341+mpkEssWrHQ+lpavuO+AqxlT
myX1+QrtStU+GUyvUuTKnDHaEwrrTxZsmfjafHcqGzZNJ5OBtFNlVhZLGST4rLb5
coqys266YJBHe9o1AfUttSraPZpfNYvO7zQJMzJWmiBrVUHATJnsTRB9kY09Mi+p
IwIDAQAB
-----END PUBLIC KEY-----
EOT
    },
    {
      name  = "JWT_PRIVATE_KEY"
      value = <<-EOT
-----BEGIN PRIVATE KEY-----
MIIEvgIBADANBgkqhkiG9w0BAQEFAASCBKgwggSkAgEAAoIBAQCpFw4CZEZa9hI/
aCWhaPPpzNzdLkxRMtQBzOQAAnrfGE9+HD6S7RZieNHj6HeXUlO1KPyLRBNWnOzq
tb3AQ4D1rZzvAF5aa1KwAZXfPZdrnCTAJ/snNfzOgJFeefLIxO0O9OQp/5yVcOHo
j7HixElggj+RKdI9GiLlCi5ZEXT4jbtKFci88cjNnnqPfjX6amQSyxasdD6Wlq+4
74CrGVObJfX5Cu1K1T4ZTK9S5MqcMdoTCutPFmyZ+Np8dyobNk0nk4G0U2VWFksZ
JPistvlyirKzbrpgkEd72jUB9S21Kto9ml81i87vNAkzMlaaIGtVQcBMmexNEH2R
jT0yL6kjAgMBAAECggEAKXOPaaKvZKkiPA0J/JHACbbBBi/NYbJ2KqLR2fbBrGNH
SYEfDeG1NRqtSZO5jY0PHEAZ+QINQ5RguAEprTJfMNsIt8Z9WukociFRXlK5BhZX
JAwpE6m2eeEmweRfUjyEaMA8FtekyTXNC7f+QbsgydnkP2/jLDt2BnQCfK8835lp
J/xjNd5NsnYnx+FtGiTyC2zKFuFF4Zwv2gp1dPfxNDuIRpshN+xdz0OSVP2J91hg
Ys8APwkRIYJMV4x4K0xPbw8xkxE3jec+CnpeuYtvHhCv02acqUT3t4fQz9tkVNwv
XQsnHdGpto7CgzEhqRCMFY2kNlDcU5nFtStnBBSYYQKBgQDRAVqjuSC2gW+T/uiI
SiSdlOQojKLAqNwcFSarum+pMUOy/+CQpbtQ2odkgQpnmu22tBeUlmx3CRnPap8K
7YfFTqoqA9F9BLvAFWcef6vfofTH709V9GRNrix2YC71zjdtfaunTj+Zy+Br2Mfx
fGFEA6bosfHvc1/G+NK4xlKQ+QKBgQDPHB9R+jM7xzrhHVxU0GUx2dyEU3SdZpK/
5syRg+/WY7CJ4OxI5sn5Ct3ejagNEsGsMg66mMZBf9zQl+b6HnkLJ98ql2HmzVdr
uWLAtt9Ni6ANkK4I7grAyF01F69FH6MEVC097VcdM4IgLKBNj+2p0aAKXxOpSJ+D
6R1/fW3t+wKBgFH5Hfuo2FO8YG7DQ6Bws/u6MeJVhl/Z2rqI8SnZbYIGeG70PLd+
yQDlNMUOd247LZDDAZydgt0NDLp1LvuyPdX9DHB+HuPRv3GO82ra2CZV9xOToKIt
wElXTsj+4Gw3/TVMXM65uegwNk0WMRVdmyh55jTN1f38WkxHux4NasTBAoGBAIpH
342PfRejjOdzAAvM3FPtfzOGuSzCqKaiReG+cqr1ApD8cSa3mRDDtaF7eUHJTTBY
d8cUbAKdiWRol5pWMEFHjNRWINLGNWFCdPHw56VR3TpRaDGkJd/Tp4/kUWzYk7I3
NcHMLsbbdj1fLmS6/VbOFIn4Mxtq1r5vLffKWlRzAoGBAM6uY7DoXA+eSpUEdcAg
O3nrnDOjYj3ujckQ+TgHR8FpGTyK3fA7CpsxRRST8bvOHXidKuXI0DvIUrgDVgct
ZH/rHBT7Xglx4ZvyQsvmsdfFcHRuBW7yDvBFoaCMNPKNal+eHrgux1F5A3DHz8+b
oeZ6BYXXnFa0zBghZhyNWIBU
-----END PRIVATE KEY-----
EOT
    }
  ]

  tags = {
    Project     = var.project_name
    Environment = var.environment
    ManagedBy   = "Terraform"
  }
}


module "compute_kyc" {
  source = "../../modules/compute"
  project_name = var.project_name
  environment  = var.environment
  name_prefix  = "${var.project_name}-${var.environment}-kyc"


  # ======================================================
  # NETWORK
  # ======================================================
  
  vpc_id   = module.network.vpc_id
  vpc_cidr = var.vpc_cidr
  private_subnet_ids = module.network.private_subnet_ids
  
  # ======================================================
  # ALB / EDGE
  # ======================================================

  alb_security_group_id = module.edge.alb_security_group_id
  target_group_arn      = module.edge.kyc_target_group_arn # You will create this in Step 2
  
  # ======================================================
  # ECS
  # ======================================================

  container_image = "865266771761.dkr.ecr.eu-west-1.amazonaws.com/sentinelpay-dev-kyc-api:latest"
  container_port  = 8002
  desired_count   = var.desired_count

  # ======================================================
  # KMS / REGION
  # ======================================================


  kms_key_arn     = module.kms.key_arn
  aws_region      = var.aws_region

  env_vars = [
    { name = "ENVIRONMENT", value = "development" },
    { name = "DATABASE_URL", value = "postgresql://sentinelpay_admin:${random_password.database.result}@${module.rds.endpoint}:${module.rds.port}/sentinelpay" },
    { name = "REDIS_URL", value = "rediss://:${module.data.redis_password}@${module.data.redis_endpoint}:6379/0" },
    {
      name  = "JWT_PUBLIC_KEY"
      value = <<-EOT
-----BEGIN PUBLIC KEY-----
MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEAqRcOAmRGWvYSP2gloWjz
6czc3S5MUTLUAczkAAJ63xhPfhw+ku0WYnjR4+h3l1JTtSj8i0QTVpzs6rW9wEOA
9a2c7wBeWmtSsAGV3z2Xa5wkwCf7JzX8zoCRXnnyyMTtDvTkKf+clXDh6I+x4sRJ
YII/kSnSPRoi5QouWRF0+I27ShXIvPHIzZ56j341+mpkEssWrHQ+lpavuO+AqxlT
myX1+QrtStU+GUyvUuTKnDHaEwrrTxZsmfjafHcqGzZNJ5OBtFNlVhZLGST4rLb5
coqys266YJBHe9o1AfUttSraPZpfNYvO7zQJMzJWmiBrVUHATJnsTRB9kY09Mi+p
IwIDAQAB
-----END PUBLIC KEY-----
EOT
    }
  ]

  tags = {
    Project     = var.project_name
    Environment = var.environment
    ManagedBy   = "Terraform"
  }
}


resource "random_password" "database" {
  length  = 32
  special = true
}


module "security_iam" {
  source = "../../modules/security-iam"

  project_name = var.project_name
  environment  = var.environment
}


module "kms" {
  source = "../../modules/kms"

  project_name = var.project_name
  environment  = var.environment

  kms_admin_role_arns = [
    module.security_iam.kms_admin_role_arn
  ]

  kms_user_role_arns = [
    module.security_iam.kms_user_role_arn
  ]
}


module "rds" {
  source = "../../modules/rds"

  project_name = var.project_name
  environment  = var.environment

  vpc_id = module.network.vpc_id

  private_subnet_ids = module.network.private_subnet_ids

  application_security_group_id = (
    module.compute_payments.ecs_security_group_id
  )

  kms_key_arn = module.kms.key_arn

  db_name     = "sentinelpay"
  db_username = "sentinelpay_admin"
  db_password = random_password.database.result
}


module "secrets_rotation" {
  source = "../../modules/secrets-rotation"

  project_name = var.project_name
  environment  = var.environment

  vpc_id = module.network.vpc_id

  private_subnet_ids = module.network.private_subnet_ids

  rds_security_group_id = module.rds.security_group_id

  kms_key_arn = module.kms.key_arn

  db_host = module.rds.endpoint
  db_port = module.rds.port

  db_name     = "sentinelpay"
  db_username = "sentinelpay_admin"
  db_password = random_password.database.result

  rotation_lambda_zip = data.archive_file.postgres_rotation.output_path
}
data "archive_file" "postgres_rotation" {
  type        = "zip"
  source_file = "${path.root}/../../lambda/postgres-rotation/lambda_function.py"
  output_path = "${path.root}/../../lambda/postgres-rotation.zip"
}


data "aws_caller_identity" "current" {}

data "aws_region" "current" {}


locals {
  github_deployment_policy = jsonencode({
    Version = "2012-10-17"

    Statement = [
      {
        Sid    = "ECRAuthentication"
        Effect = "Allow"

        Action = [
          "ecr:GetAuthorizationToken"
        ]

        Resource = "*"
      },

      {
        Sid    = "ECRImageManagement"
        Effect = "Allow"

        Action = [
          "ecr:DescribeImages",
          "ecr:DescribeRepositories",
          "ecr:BatchCheckLayerAvailability",
          "ecr:GetDownloadUrlForLayer",
          "ecr:BatchGetImage",
          "ecr:InitiateLayerUpload",
          "ecr:UploadLayerPart",
          "ecr:CompleteLayerUpload",
          "ecr:PutImage"
        ]

        Resource = [
          "arn:aws:ecr:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:repository/${var.project_name}-${var.environment}-payments-api",
          "arn:aws:ecr:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:repository/${var.project_name}-${var.environment}-kyc-api"
        ]
      },

      {
        Sid    = "ECSDeploy"
        Effect = "Allow"

        Action = [
          "ecs:UpdateService",
          "ecs:DescribeServices"
        ]

        Resource = [
          "arn:aws:ecs:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:service/${var.project_name}-${var.environment}/*"
        ]
      },

      {
        Sid    = "ECSTaskDefinitionManagement"
        Effect = "Allow"

        Action = [
          "ecs:RegisterTaskDefinition",
          "ecs:DescribeTaskDefinition"
        ]

        Resource = "*"
      },

      {
        Sid    = "PassECSTaskRoles"
        Effect = "Allow"

        Action = [
          "iam:PassRole"
        ]

        Resource = [
          "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/${var.project_name}-${var.environment}-payments-*",
          "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/${var.project_name}-${var.environment}-kyc-*"
        ]

        Condition = {
          StringEquals = {
            "iam:PassedToService" = "ecs-tasks.amazonaws.com"
          }
        }
      }
    ]
  })
}


module "github_oidc" {
  source = "../../modules/github-oidc"

  project_name           = var.project_name
  environment            = var.environment
  github_organization    = var.github_organization
  github_repository      = var.github_repository
  deployment_policy_json = local.github_deployment_policy
}


#trivy:ignore:AVD-AWS-0089
module "data" { #tfsec:ignore:aws-s3-enable-bucket-logging
  source = "../../modules/data"

  project_name = var.project_name
  environment  = var.environment

  vpc_id = module.network.vpc_id

  private_subnet_ids = module.network.private_subnet_ids

  application_security_group_id = module.compute_payments.ecs_security_group_id

  kms_key_arn = module.kms.key_arn
}


/*module "detection" {
  source = "../../modules/detection"

  project_name = var.project_name
  environment  = var.environment
  aws_region   = var.aws_region

  vpc_id = module.network.vpc_id

  kms_key_arn = module.kms.key_arn

  cloudtrail_retention_days = 365
  private_subnet_ids        = module.network.private_subnet_ids
  enable_eks_guardduty      = false
}
*/

resource "aws_vpc_security_group_ingress_rule" "kyc_to_rds" {
  security_group_id            = module.rds.security_group_id
  referenced_security_group_id = module.compute_kyc.ecs_security_group_id
  from_port   = 5432
  to_port     = 5432
  ip_protocol = "tcp"
  description = "Allow KYC API to access RDS"
}

resource "aws_vpc_security_group_ingress_rule" "kyc_to_redis" {
  security_group_id            = module.data.redis_security_group_id
  referenced_security_group_id = module.compute_kyc.ecs_security_group_id
  from_port   = 6379
  to_port     = 6379
  ip_protocol = "tcp"
  description = "Allow KYC API to access Redis"
}