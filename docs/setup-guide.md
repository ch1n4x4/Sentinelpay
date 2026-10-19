# 02. Step-by-Step Setup & Deployment Guide

[← Back to Main Overview](../README.md)

> **Scope:** This guide provides the complete, reproducible instructions for setting up local security tooling, bootstrapping Terraform remote state, deploying the SentinelPay AWS environment (`eu-west-1`), configuring keyless GitHub OIDC federation, building and signing container artifacts with Syft and Cosign, and running live OWASP ZAP DAST scans.

---

## 1. Prerequisites & Local Security Tooling

Install and verify the following tools locally to mirror the Cycle 1–5 DevSecOps and CloudSec environment:
* **Cloud & IaC:** AWS CLI v2 (`eu-west-1`), Terraform `>= 1.7.0` (`hashicorp/aws` `v6.62.0`, `hashicorp/random` `v3.9.0`, `hashicorp/archive` `v2.8.0`), OpenSSL.
* **Containers & Supply Chain:** Docker Engine / Desktop, **Syft** (CycloneDX SBOM generator), **Cosign** (Sigstore keyless signing & verification).
* **Security Scanners & Policy:** **Gitleaks**, **Bandit**, **Semgrep**, **Trivy**, **Checkov**, **tfsec**, and **Conftest** (Open Policy Agent).

---

## 2. Phase 1: Bootstrap Terraform Remote State (`Bootstrap/`)

Provision the encrypted Amazon S3 remote state bucket and DynamoDB state-locking table first to avoid circular backend dependencies:

```powershell
cd Bootstrap

# Initialize Terraform providers
terraform init

# Provision the encrypted S3 state bucket and DynamoDB lock table
terraform apply -auto-approve
```

![Bootstrap Apply Success](../assets/images/bootstrap%20apply.png)
*Figure 1: Successful execution of `terraform apply -auto-approve` in `Bootstrap/`, creating `sentinelpay-terraform-locks` and `sentinelpay-terraform-state-*`.*

Verify that the DynamoDB lock table has KMS server-side encryption and 35-day Point-in-Time Recovery (PITR) enabled, and ensure the output bucket name matches `infra/environments/dev/backend.tf`:

```powershell
aws dynamodb describe-table --table-name sentinelpay-terraform-locks --region eu-west-1
aws dynamodb describe-continuous-backups --table-name sentinelpay-terraform-locks --region eu-west-1
```

---

## 3. Phase 2: Validate & Provision the AWS `dev` Environment (`infra/environments/dev/`)

### Step 1: Configure Environment Variables (`terraform.tfvars`)
Create `infra/environments/dev/terraform.tfvars` (ignored by Git via `.gitignore`):

```hcl
aws_region           = "eu-west-1"
project_name         = "sentinelpay"
environment          = "dev"
vpc_cidr             = "10.0.0.0/16"
public_subnet_cidrs  = ["10.0.1.0/24", "10.0.2.0/24"]
private_subnet_cidrs = ["10.0.10.0/24", "10.0.11.0/24"]
availability_zones   = ["eu-west-1a", "eu-west-1b"]
github_organization  = "sentinelpay-team"
github_repository    = "Sentinelpay"
```

### Step 2: Run Static IaC Scanners & OPA Conftest Policy Checks
Always run Terraform commands from `infra/environments/dev` (running from `infra/` will fail with `Error: No configuration files`):

```powershell
cd ../infra/environments/dev

# 1. Initialize remote S3 backend and child modules
terraform init

# 2. Validate HCL syntax
terraform validate

# 3. Run Checkov and tfsec static analysis across the infrastructure
checkov -d ..\..\ --framework terraform --compact
tfsec ..\..\

# 4. Test OPA Rego policies against local secure/insecure fixtures
conftest test ..\..\..\policy-tests\s3\secure.json -p ..\..\..\policy\terraform --all-namespaces
conftest test ..\..\..\policy-tests\encryption\secure.json -p ..\..\..\policy\terraform --all-namespaces

# 5. Generate live Terraform plan JSON and evaluate with Conftest
terraform plan -out=tfplan
terraform show -json tfplan > tfplan.json
conftest test tfplan.json -p ..\..\..\policy\terraform --all-namespaces

# 6. Apply the infrastructure
terraform apply tfplan
```

---

## 4. Phase 3: Verify KMS, Secrets Manager, CloudTrail & GitHub OIDC

After `terraform apply` completes, run the runtime verification checks from `infra/environments/dev`:

```powershell
# 1. Verify Secrets Manager secrets are encrypted with the customer-managed KMS key
aws secretsmanager describe-secret --secret-id "sentinelpay/dev/redis/auth" --query "{Name:Name,KmsKeyId:KmsKeyId}" --output table
aws secretsmanager describe-secret --secret-id "sentinelpay/dev/honeytoken" --query "{Name:Name,KmsKeyId:KmsKeyId}" --output table
aws secretsmanager describe-secret --secret-id "sentinelpay/dev/database" --query "{Name:Name,KmsKeyId:KmsKeyId}" --output table

# 2. Verify CloudTrail S3 bucket Versioning, Encryption, and Object Lock
aws s3api get-bucket-versioning --bucket <CLOUDTRAIL_BUCKET_NAME>
aws s3api get-bucket-encryption --bucket <CLOUDTRAIL_BUCKET_NAME>
aws s3api get-object-lock-configuration --bucket <CLOUDTRAIL_BUCKET_NAME>

# 3. Verify GitHub OIDC IAM Role and AssumeRolePolicyDocument
aws iam get-role --role-name sentinelpay-dev-github-actions --query "Role.Arn" --output text
aws iam get-role --role-name sentinelpay-dev-github-actions --query "Role.AssumeRolePolicyDocument" --output json
```

Configure the output `github_actions_role_arn` (`arn:aws:iam::105045466108:role/sentinelpay-dev-github-actions`) as the `AWS_ROLE_ARN` repository variable in GitHub so `.github/workflows/infrastructure-security.yml`, `container-security.yml`, and `policy-checks.yml` can authenticate keylessly via `aws-actions/configure-aws-credentials@v6.2.3`.

---

## 5. Phase 4: Build Containers, Generate SBOMs, Push to ECR & Sign with Cosign

### Step 1: Authenticate to Amazon ECR & Build Hardened Alpine Images
Both `services/payments-api/Dockerfile` and `services/kyc-api/Dockerfile` enforce `python:3.11-alpine`, non-root `USER appuser`, native `HEALTHCHECK` probes, and Gunicorn workers:

```powershell
# Authenticate Docker CLI to Amazon ECR (eu-west-1)
aws ecr get-login-password --region eu-west-1 | docker login --username AWS --password-stdin <ACCOUNT_ID>.dkr.ecr.eu-west-1.amazonaws.com

# Build payments-api and kyc-api images
docker build -t sentinelpay-dev-payments-api:latest ./services/payments-api
docker build -t sentinelpay-dev-kyc-api:latest ./services/kyc-api
```

![AWS ECR Create Repo](../assets/images/aws%20ecr%20create%20repo.png)
![AWS Docker Login](../assets/images/aws%20docker%20login.png)
![Container Build](../assets/images/container%20build.png)
*Figure 2: Creating the ECR repositories, logging in via Docker CLI, and building the hardened Alpine images.*

### Step 2: Generate CycloneDX SBOMs (`Syft`) & Scan Images (`Trivy`)

```bash
# Generate CycloneDX JSON SBOMs for both images
syft sentinelpay-dev-payments-api:latest -o cyclonedx-json=payments-sbom.cdx.json
syft sentinelpay-dev-kyc-api:latest -o cyclonedx-json=kyc-sbom.cdx.json

# Scan both images for CRITICAL vulnerabilities
trivy image --severity CRITICAL --exit-code 1 sentinelpay-dev-payments-api:latest
trivy image --severity CRITICAL --exit-code 1 sentinelpay-dev-kyc-api:latest
```

### Step 3: Push to Immutable ECR & Execute Keyless Cosign Signing/Verification

```bash
# Tag and push images to Amazon ECR
docker tag sentinelpay-dev-payments-api:latest <ACCOUNT_ID>[.dkr.ecr.eu-west-1.amazonaws.com/sentinelpay-dev-payments-api:latest](https://.dkr.ecr.eu-west-1.amazonaws.com/sentinelpay-dev-payments-api:latest)
docker push <ACCOUNT_ID>[.dkr.ecr.eu-west-1.amazonaws.com/sentinelpay-dev-payments-api:latest](https://.dkr.ecr.eu-west-1.amazonaws.com/sentinelpay-dev-payments-api:latest)

docker tag sentinelpay-dev-kyc-api:latest <ACCOUNT_ID>[.dkr.ecr.eu-west-1.amazonaws.com/sentinelpay-dev-kyc-api:latest](https://.dkr.ecr.eu-west-1.amazonaws.com/sentinelpay-dev-kyc-api:latest)
docker push <ACCOUNT_ID>[.dkr.ecr.eu-west-1.amazonaws.com/sentinelpay-dev-kyc-api:latest](https://.dkr.ecr.eu-west-1.amazonaws.com/sentinelpay-dev-kyc-api:latest)

# Resolve immutable sha256 digest and sign/attest keylessly with Cosign (executed automatically in container-security.yml)
cosign sign --yes <ACCOUNT_ID>[.dkr.ecr.eu-west-1.amazonaws.com/sentinelpay-dev-payments-api@sha256](https://.dkr.ecr.eu-west-1.amazonaws.com/sentinelpay-dev-payments-api@sha256):<IMAGE_DIGEST>
cosign attest --yes --predicate payments-sbom.cdx.json --type cyclonedx <ACCOUNT_ID>[.dkr.ecr.eu-west-1.amazonaws.com/sentinelpay-dev-payments-api@sha256](https://.dkr.ecr.eu-west-1.amazonaws.com/sentinelpay-dev-payments-api@sha256):<IMAGE_DIGEST>

# Verify supply-chain signature and SBOM attestation prior to deployment
./Amdari-Project--02/scripts/verify_supply_chain.sh
```

![Container Push to AWS ECR](../assets/images/container%20push%20to%20aws.png)
*Figure 3: Pushing validated `payments-api` and `kyc-api` images to Amazon ECR.*

---

## 6. Phase 5: Enable ALB HTTPS (ACM) & Execute OWASP ZAP DAST Scans

### Step 1: Generate & Import TLS Certificate into AWS ACM
To enable the HTTPS (`:443`) listener and HTTP-to-HTTPS (`301`) redirect on the ALB, generate a 2048-bit RSA certificate and import it into ACM (`eu-west-1`):

```powershell
openssl req -x509 -nodes -days 365 -newkey rsa:2048 `
  -keyout alb-private.key -out alb-cert.pem `
  -subj "/CN=sentinelpay-dev.local"

aws acm import-certificate `
  --certificate fileb://alb-cert.pem `
  --private-key fileb://alb-private.key `
  --region eu-west-1
```

![Import Certificate into ACM](../assets/images/import%20certificate.png)
*Figure 4: Generating and importing the X.509 certificate into AWS ACM (`eu-west-1`).*

Update `acm_certificate_arn` in `infra/environments/dev/terraform.tfvars` and run `terraform apply`.

### Step 2: Local & Live Smoke Testing
Verify authentication, wallet credits/debits, JWT verification, and structured `sentinelpay.audit` logging locally, then verify live HTTPS headers on the AWS ALB:

![Initial Login](../assets/images/initial_login.png)
![Initial Login and Credit Wallet](../assets/images/initial%20login%20and%20credit%20wallet.png)
![JWT Token Check](../assets/images/jwt%20token%20check.png)
![Audit Log Population](../assets/images/audit%20log%20population.png)
*Figure 5: Verifying user login, wallet credit, JWT claims, and structured audit log emission.*

### Step 3: Run Containerized OWASP ZAP (`v2.17.0`) Baseline & Active Scans

```powershell
mkdir zap-reports

# 1. Passive Baseline Scan
docker run --rm -v "${PWD}/zap-reports:/zap/wrk/:rw" `
  -t ghcr.io/zaproxy/zaproxy:stable zap-baseline.py `
  -t "[https://sentinelpay-dev-alb-2097557956.eu-west-1.elb.amazonaws.com](https://sentinelpay-dev-alb-2097557956.eu-west-1.elb.amazonaws.com)" `
  -r zap_baseline_report.html `
  -J zap_baseline_report.json

# 2. Active Full Scan
docker run --rm -v "${PWD}/zap-reports:/zap/wrk/:rw" `
  -t ghcr.io/zaproxy/zaproxy:stable zap-full-scan.py `
  -t "[https://sentinelpay-dev-alb-2097557956.eu-west-1.elb.amazonaws.com](https://sentinelpay-dev-alb-2097557956.eu-west-1.elb.amazonaws.com)" `
  -r zap_active_report.html `
  -J zap_active_report.json
```