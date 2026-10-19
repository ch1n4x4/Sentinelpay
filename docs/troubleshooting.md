# SentinelPay: Runbook & Troubleshooting Guide

[← Back to Main Overview](../README.md)

> **Scope:** This runbook documents every engineering roadblock, scanner exception, CI/CD gate failure, AWS OIDC trust error, Terraform static-analysis finding, ECS container crash loop, and OWASP ZAP DAST alert encountered across all four phases of the SentinelPay project, along with the exact root cause and verified remediation:
> 1. **Phase 1 — Application Security (AppSec), Secret Baseline & Dependency Troubleshooting**[cite: 1, 2, 4, 6, 7]
> 2. **Phase 2 — DevSecOps CI/CD, GitHub OIDC, OPA Conftest & Supply-Chain Troubleshooting**[cite: 1, 3, 4, 5, 6]
> 3. **Phase 3 — Cloud Security, Terraform State & Static Analysis (`Checkov` / `tfsec`) Troubleshooting**[cite: 1, 2, 3, 5, 7]
> 4. **Phase 4 — Live ECS Fargate (`503`) & OWASP ZAP DAST Remediation Runbook**[cite: 1, 2, 7]

---

## Table of Contents
- [1. Phase 1: Application Security (AppSec), Secret Baseline & Dependency Troubleshooting](#1-phase-1-application-security-appsec-secret-baseline--dependency-troubleshooting)
- [2. Phase 2: DevSecOps CI/CD, GitHub OIDC, OPA Conftest & Supply-Chain Troubleshooting](#2-phase-2-devsecops-cicd-github-oidc-opa-conftest--supply-chain-troubleshooting)
- [3. Phase 3: Cloud Security, Terraform State & Static Analysis (`Checkov` / `tfsec`) Troubleshooting](#3-phase-3-cloud-security-terraform-state--static-analysis-checkov--tfsec-troubleshooting)
- [4. Phase 4: Live ECS Fargate (`503`) & OWASP ZAP DAST Remediation Runbook](#4-phase-4-live-ecs-fargate-503--owasp-zap-dast-remediation-runbook)

---

## 1. Phase 1: Application Security (AppSec), Secret Baseline & Dependency Troubleshooting

### Issue 1.1: Gitleaks Failing on Historical Commits, Environment Lookups & Intentional Honeytoken References
* **Symptom:** Running `gitleaks detect` across the full Git history blocked the pipeline due to secrets committed in early project setup commits (`scripts/legacy_deploy.sh` containing training Stripe keys, Slack webhooks, and DB passwords; `docker-compose.yml` fallback passwords), `os.environ.get(` lookups in `auth.py`/`documents.py`, and Terraform resource references in `infra/modules/detection/honeytoken.tf`[cite: 1, 4, 6].
* **Root Cause:**
  1. Even after hardcoded secrets are removed from the latest working tree, Git history retains the earlier commits (`fe53a7c`, `2da5fe5`, `8359919`, `b2704d6`)[cite: 1, 4, 6].
  2. The custom rule `sentinelpay-sensitive-env` in `.gitleaks.toml` matched `AWS_ACCESS_KEY_ID = aws_iam_access_key.honeytoken.id` and `AWS_SECRET_ACCESS_KEY = aws_iam_access_key.honeytoken.secret` inside `honeytoken.tf` (commit `bbd6889`) as well as `os.environ.get(` assignments[cite: 1].
* **Resolution:**
  1. Removed hardcoded credentials from active application files and replaced them with environment variables and AWS Secrets Manager references[cite: 1, 2, 3, 5, 7].
  2. Added `.env.example` and `sentinelpay-dev-secret` to the `[allowlist]` in `.gitleaks.toml`[cite: 1].
  3. Recorded the verified historical and false-positive fingerprints in `gitleaks-baseline.json` so Gitleaks scans full Git history while only blocking net-new secret leaks[cite: 1, 4, 6].

### Issue 1.2: Trivy Dependency Scan Flagging Upstream Vendored `pip` Packages
* **Symptom:** Trivy filesystem/container dependency scans flagged `GHSA-6v7p-g79w-8964` (`msgpack`) and `CVE-2025-47273` (`setuptools`) inside Python's internal vendored `pip` directory[cite: 1].
* **Root Cause:** Base Python installations bundle internal vendored copies of `msgpack` and `setuptools` inside `pip/_vendor` that are not directly imported by the runtime Flask application[cite: 1].
* **Resolution:** Upgraded `pip`, `setuptools`, and `wheel` during image build (`RUN pip install --upgrade --no-cache-dir pip setuptools wheel`)[cite: 2, 7] and documented both upstream vendored advisories in `.trivyignore` so the Trivy gate remains fail-closed for all application dependencies[cite: 1].

### Issue 1.3: Preventing Existing User Lockouts During `MD5` -> `Argon2id` Migration (`V-APP-06`)
* **Symptom:** Switching `POST /v1/auth/login` directly to `argon2.PasswordHasher().verify()` would invalidate all existing merchant accounts seeded with legacy `hashlib.md5()` hashes[cite: 2, 7].
* **Resolution:** Implemented a transparent login-time migration in `services/payments-api/app/routes/auth.py`: when a user logs in with a legacy 32-character hex MD5 hash, the handler verifies the MD5 digest against the supplied password, immediately computes a salted `$argon2id$v=19$m=65536,t=3,p=4` hash, and updates `users.password_hash` in PostgreSQL in place[cite: 2, 7].

### Issue 1.4: Preventing Rate-Limit Bypass via Case/Formatting Variations (`V-APP-08`)
* **Symptom:** Scoping `Flask-Limiter` solely by client IP or raw request strings allowed attackers rotating proxies or varying email casing/phone formatting to bypass the `5/minute` threshold on `/v1/auth/login`, `/register`, and `/otp`[cite: 2, 7].
* **Resolution:** Canonicalized account identifiers (lowercasing/stripping email addresses and normalizing phone numbers to E.164 format) and hashed them with SHA-256 before constructing the Redis rate-limit key[cite: 2, 7].

---

## 2. Phase 2: DevSecOps CI/CD, GitHub OIDC, OPA Conftest & Supply-Chain Troubleshooting

### Issue 2.1: AWS OIDC `AssumeRoleWithWebIdentity` Failing After 12 Retries
* **Symptom:** In Cycles 2–3, the `Test AWS OIDC Authentication` job in GitHub Actions failed after 12 retries with `Error: Could not assume role with OIDC: The web identity token provided could not be validated` / `Not authorized to perform sts:AssumeRoleWithWebIdentity`[cite: 3, 4, 5, 6].
* **Root Cause:**
  1. The IAM role trust policy (`infra/modules/github-oidc/main.tf`) had a subject (`token.actions.githubusercontent.com:sub`) condition mismatch that did not match the repository's customized immutable GitHub subject format (`repo:sentinelpay-team@321830913/Sentinelpay@1348603997:...`)[cite: 1, 3, 4, 5, 6].
  2. A workflow condition initially restricted the OIDC test to pushes on `main`, preventing pull requests from validating OIDC authentication[cite: 3, 5].
* **Resolution:**
  1. Updated `infra/modules/github-oidc/main.tf` to validate `token.actions.githubusercontent.com:aud = "sts.amazonaws.com"` and explicitly permit both `repo:${var.github_organization}@321830913/${var.github_repository}@1348603997:ref:refs/heads/main` and `repo:${var.github_organization}@321830913/${var.github_repository}@1348603997:pull_request` (or `:*`), then applied via `terraform apply -target="module.github_oidc"`[cite: 1, 3, 5].
  2. Removed the main-only restriction from the workflow so every PR validates live OIDC role assumption[cite: 3, 5].

### Issue 2.2: `ecr:DescribeImages` AccessDenied During Container Promotion & Digest Lookup
* **Symptom:** After OIDC authentication succeeded, `container-security.yml` failed with `AccessDenied` when querying Amazon ECR image metadata to resolve immutable digests[cite: 3, 4, 5, 6].
* **Root Cause:** Authentication success and authorization success are separate checks: `local.github_deployment_policy` in `infra/environments/dev/main.tf` initially granted write actions (`ecr:PutImage`, `ecr:UploadLayerPart`) but lacked read/describe actions[cite: 1, 3, 4, 5, 6].
* **Resolution:** Added `ecr:DescribeImages` and `ecr:DescribeRepositories` scoped to the `payments-api` and `kyc-api` ECR repository ARNs in `local.github_deployment_policy`[cite: 1, 3, 5].

### Issue 2.3: Conftest Failing with `Error: No configuration files`, S3 Backend Access & Namespace Selection
* **Symptom:** In Cycle 4, `policy-checks.yml` failed during `terraform plan` with `Error: No configuration files`, then failed on S3 backend initialization, and required explicit namespace evaluation for Rego rules[cite: 3, 4, 5, 6].
* **Root Cause:**
  1. The job ran Terraform inside `infra/` instead of the environment root `infra/environments/dev`[cite: 3, 4, 5, 6].
  2. Because `infra/environments/dev/backend.tf` uses an S3 remote backend, `terraform init` and `terraform plan` require AWS credentials even during static policy checks[cite: 1, 4, 6].
  3. Default `conftest test` only checks the `main` namespace unless `--all-namespaces` is passed to evaluate `terraform.s3`, `terraform.network`, `terraform.encryption`, and `terraform.iam`[cite: 1, 4, 6].
* **Resolution:**
  1. Set the working directory in `policy-checks.yml` to `infra/environments/dev` and updated the policy path to `../../../policy/terraform`[cite: 3, 4, 5, 6].
  2. Added the `aws-actions/configure-aws-credentials@v6.2.3` OIDC step to `policy-checks.yml`[cite: 4, 6].
  3. Added `--all-namespaces` to the Conftest command and documented plan-shape caveats (such as stringified IAM JSON in real plans vs. object fixtures)[cite: 4, 6].

### Issue 2.4: Early "Green" Scanner Jobs When Target Files Were Absent
* **Symptom:** Early in the project, `Checkov` and `tfsec` jobs turned green before the Terraform files were merged into the working branch[cite: 4, 6].
* **Root Cause:** Scanners exit with code `0` when a target directory is empty or missing expected files, creating a false sense of security[cite: 4, 6].
* **Resolution:** Treated early green jobs without target artifacts as inconclusive, aligned all IaC and policy workflows to `infra/environments/dev`, and required uploaded JSON/SARIF evidence artifacts on every run[cite: 4, 6].

### Issue 2.5: ECR Tag Immutability Collisions on Re-Runs & Multi-Image Scan Masking
* **Symptom:** Rerunning `container-security.yml` on the same commit failed because the commit SHA tag already existed in Amazon ECR; additionally, if `payments-api` failed its Trivy image scan, the job terminated before scanning `kyc-api`[cite: 4, 6].
* **Resolution:**
  1. Refused to weaken ECR by disabling tag immutability; instead, adapted the pipeline to resolve `@sha256:<digest>` references for Cosign signing, CycloneDX SBOM attestation, and verification[cite: 4, 6].
  2. Allowed both `trivy_payments` and `trivy_kyc` scan steps to finish and upload reports before a final `Enforce Trivy image security gate` (`if: always()`) step fails the build if either image failed[cite: 4, 6].

---

## 3. Phase 3: Cloud Security, Terraform State & Static Analysis (`Checkov` / `tfsec`) Troubleshooting

### Issue 3.1: `Bootstrap/` State Initialization Error
* **Symptom:** Running `terraform apply` in `Bootstrap/` initially failed prior to initializing the provider lockfile and backend state[cite: 1, 2, 7].
  ![Bootstrap Apply Error](../assets/images/bootstrap%20apply%20error.png)
* **Resolution:** Executed `terraform init` in `Bootstrap/`, ran `terraform apply -auto-approve` to create `sentinelpay-terraform-locks` and `sentinelpay-terraform-state-*`, and updated `infra/environments/dev/backend.tf` with the exact S3 bucket name[cite: 1, 2, 3, 5, 7].

### Issue 3.2: Remediating `Checkov` (`CKV_AWS_*`) & `tfsec` Static Analysis Findings
Static analysis across `infra/` surfaced 11 cloud security findings that were remediated in HCL (or documented with architectural justifications where required by AWS service mechanics), achieving **207 passed `tfsec` checks with 0 Critical, 0 High, 0 Medium, and 0 Low findings**[cite: 1, 3, 5]:

| Check ID | Static Analysis Finding | Engineered Terraform Fix / Documented Exception |
| :--- | :--- | :--- |
| **`CKV_AWS_65`** | ECS Cluster Container Insights disabled | Enabled `setting { name = "containerInsights", value = "enabled" }` in `infra/modules/compute/main.tf`[cite: 1, 3, 5]. |
| **`CKV_AWS_130`** | VPC subnets auto-assigning public IPs | Set `map_public_ip_on_launch = false` on all public and private subnets in `infra/modules/network/main.tf`[cite: 1, 3, 5]. |
| **`CKV_AWS_260` & `CKV2_AWS_20`** | Port 80 open to `0.0.0.0/0` & missing HTTPS redirect | Configured `aws_lb_listener.http` on port `80` exclusively as an `HTTP_301` redirect to HTTPS port `443`[cite: 1, 3, 5]. |
| **`CKV_AWS_103`** | ALB listener not using modern TLS 1.2/1.3 policy | Enforced `ssl_policy = "ELBSecurityPolicy-TLS13-1-2-2021-06"` on `aws_lb_listener.https`[cite: 1, 3, 5]. |
| **`CKV_AWS_23`** | Security group rules missing descriptions | Added explicit `description` attributes to every security group and ingress/egress rule across all modules[cite: 1, 3, 5]. |
| **`CKV_AWS_158` & `CKV_AWS_338`** | CloudWatch Log Groups unencrypted & retained `< 365 days` | Configured `retention_in_days = 365` and `kms_key_id = var.kms_key_arn` on VPC Flow Logs, WAF, ECS, and CloudTrail log groups[cite: 1, 3, 5]. |
| **`CKV_AWS_252`** | CloudTrail missing SNS notification topic | Provisioned KMS-encrypted `aws_sns_topic.cloudtrail` and attached `sns_topic_name` to `aws_cloudtrail.this`[cite: 1, 3, 5]. |
| **`CKV_AWS_145` & `CKV_AWS_18`** | S3 Access-Log destination bucket using `AES256` & not logging to itself | Documented intentional exception in `detection/cloudtrail.tf`: AWS S3 server access-log delivery requires `AES256` (`SSE-S3`) rather than `SSE-KMS`, and logging an access-log bucket to itself would cause infinite recursive logging[cite: 1]. |
| **`CKV_AWS_144`** | S3 Cross-Region Replication (CRR) disabled in `dev` | Scoped as a development-only exception; production DR replication is tracked as a post-capstone enhancement[cite: 1, 3, 5]. |
| **`CKV_AWS_115`** | Lambda reserved concurrency (`reserved_concurrent_executions = 5`) | Triggered an AWS account minimum-unreserved-capacity error in constrained accounts; adjusted concurrency settings to match account limits[cite: 1, 2, 3, 5, 7]. |
| **`CKV_AWS_109`, `111` & `356`** | KMS key policy using `resources = ["*"]` | In AWS KMS key policies, `Resource: "*"` refers strictly to the KMS key to which the policy is attached; scoped all statements with explicit `Principal` ARNs, `kms:ViaService`, `aws:SourceArn`, and `kms:EncryptionContext` conditions[cite: 1, 3, 5]. |

### Issue 3.3: AWS Sandbox Quotas & KMS / RDS / Lambda Adjustments
* **KMS CloudWatch Logs Condition (`AllowCloudWatchLogsUse`):** Originally restricted `kms:EncryptionContext:aws:logs:arn` to `/ecs/sentinelpay-dev*` in `infra/modules/kms/main.tf`, blocking KMS encryption on VPC Flow Logs and WAF logs; expanded the condition to allow regional log groups in the account[cite: 1, 2, 7].
* **RDS Parameter Group Family Mismatch:** `infra/modules/rds/variables.tf` defaulted `postgres_version = "17"` while `postgres_parameter_group_family` defaulted to `"postgres16"`; aligned the family to `postgres17` and set `backup_retention_period = 0` where required by sandbox quotas[cite: 1, 2, 7].
* **Lambda Code Signing Enforcement:** Relaxed `untrusted_artifact_on_deployment` from `"Enforce"` to `"Warn"` during local zip packaging in sandbox environments[cite: 1, 2, 7].

### Issue 3.4: Operational Safeguards During Updates & Teardown (KMS, ALB, RDS & S3 Object Lock)
* **Recovering a KMS Key Scheduled for Deletion:** During environment testing, the customer-managed KMS key (`7ed9b7e5-c6f9-4ea5-a4a9-aa4c177d3a19`) was placed in pending deletion, blocking Secrets Manager access[cite: 3, 5]. Restored via:
  ```powershell
  aws kms cancel-key-deletion --key-id 7ed9b7e5-c6f9-4ea5-a4a9-aa4c177d3a19
  aws kms enable-key --key-id 7ed9b7e5-c6f9-4ea5-a4a9-aa4c177d3a19
  ```
* **ALB Deletion Protection, RDS Parameter Groups & S3 Object Lock:** `enable_deletion_protection = true` on the ALB, attached DB instances on `aws_db_parameter_group`, and S3 Object Lock (`COMPLIANCE` on CloudTrail; `GOVERNANCE` on KYC) intentionally block accidental `terraform destroy` operations unless explicitly sequenced through controlled change[cite: 1, 3, 5].

---

## 4. Phase 4: Live ECS Fargate (`503`) & OWASP ZAP DAST Remediation Runbook

### Issue 4.1: Public ALB Returning `503 Service Temporarily Unavailable` (ECS Tasks Crash-Looping)
* **Symptom:** After building and pushing `payments-api` and `kyc-api` to Amazon ECR, requests to `http://sentinelpay-dev-alb-2097557956.eu-west-1.elb.amazonaws.com` returned `503 Service Temporarily Unavailable` because the ECS Fargate tasks repeatedly failed health checks and exited[cite: 2, 7].
* **Four Root Causes & Engineered Fixes:**
  1. **ALB Scheme & Pre-TLS Listener:** `aws_lb.this` in `infra/modules/edge/main.tf` had `internal = true` and only created listeners when `acm_certificate_arn != null`[cite: 1, 2, 7]. Changed `internal = false` and added a conditional HTTP listener (`aws_lb_listener.http_forward`) with path-based routing (`:8001` default for `payments-api`; `/v1/verify*` and `/v1/documents*` to `:8002` for `kyc-api`)[cite: 2, 7].
  2. **ALB-to-ECS Security Group Egress Port Mismatch:** `alb_to_ecs` in `infra/modules/edge/main.tf` only allowed outbound traffic to `var.container_port` (port `80`)[cite: 1, 2, 7]. Updated `alb_to_ecs` egress to allow TCP ports `8001` through `8002` across `var.vpc_cidr`[cite: 2, 7].
  3. **ECS Security Group HTTPS Egress Blocked for NAT Gateway Routing:** `ecs_https` in `infra/modules/compute/main.tf` restricted outbound TCP port `443` to `var.vpc_cidr` (`10.0.0.0/16`)[cite: 1, 2, 7]. Because outbound traffic traversed the NAT Gateway rather than interface endpoints, Fargate tasks could not reach Amazon ECR to pull images or CloudWatch to stream logs[cite: 2, 7]. Updated `cidr_ipv4` on `ecs_https` to `"0.0.0.0/0"` on port `443`[cite: 2, 7].
  4. **Missing Container Environment Variable Injection (`KeyError` on Startup):** `aws_ecs_task_definition.this` lacked an `environment` block, causing Flask to crash with `KeyError` on startup[cite: 1, 2, 7]. Added a typed `env_vars` variable to `infra/modules/compute/variables.tf` and wired it into `aws_ecs_task_definition.this`[cite: 2, 7].

![Container Environment Variables](../assets/images/env%20variables.png)
*Figure 4.1: Wiring runtime environment variables into the ECS task definitions, stabilizing `/health` (`200 OK`) and `/v1/verify/lookup` (`401 UNAUTHORIZED`)[cite: 1, 2, 7].*

---

### Issue 4.2: AWS `DuplicateListener` Conflict on Port 80 During HTTPS Cutover (ZAP Plugin `10106`)
* **Symptom:** OWASP ZAP Active Scan flagged **Plugin 10106 (HTTP Only Site — Medium / CWE-311)** because port `443` was closed prior to ACM certificate import[cite: 2, 7]. When `acm_certificate_arn` was added to provision `aws_lb_listener.https` (`:443`) and `aws_lb_listener.http` (`:80` -> `:443` `HTTP_301` redirect), Terraform failed with `DuplicateListener` on port `80` against the temporary `aws_lb_listener.http_forward` resource[cite: 2, 7].
* **Resolution:**
  1. Generated a 2048-bit RSA key and X.509 certificate with OpenSSL (`-subj "/CN=sentinelpay-dev.local"`) and imported it into AWS ACM (`eu-west-1`)[cite: 2, 7].
  2. Set `acm_certificate_arn` in `infra/environments/dev/terraform.tfvars`[cite: 2, 7].
  3. Removed `aws_lb_listener.http_forward` and added `depends_on = [aws_lb_listener.http_forward]` to `aws_lb_listener.http` in `infra/modules/edge/main.tf` so Terraform destroyed the port 80 forward listener before creating the port 80 `HTTP_301` redirect listener[cite: 2, 7].

---

### Issue 4.3: Unmapped Routes Returning `500 Internal Server Error` During DAST (ZAP Plugins `90022` & `10023`)
* **Symptom:** During the OWASP ZAP Active Scan, **80% of responses returned `HTTP/1.1 500 INTERNAL SERVER ERROR`** with body `{"error": "internal server error"}` whenever ZAP probed unmapped paths (`/`, `/robots.txt`, `/sitemap.xml`), triggering **Plugin 90022 (Application Error Disclosure — Low / CWE-550)** and **Plugin 10023 (Information Disclosure - Debug Error Messages — Low / CWE-1295)**[cite: 2, 7].
* **Root Cause:** In both `services/payments-api/app/main.py` and `services/kyc-api/app/main.py`, the global `@app.errorhandler(Exception)` intercepted all Python exceptions—including Werkzeug `HTTPException` subclasses like `404 Not Found` and `405 Method Not Allowed`—turning normal 404s into 500s[cite: 2, 7].
* **Resolution:** Registered a dedicated `@app.errorhandler(HTTPException)` handler **before** `@app.errorhandler(Exception)` in both services to preserve `404`/`405` status codes (`{"error": "resource not found"}`) and changed the fallback 500 string from `"internal server error"` to `"request could not be processed"`[cite: 2, 7].

---

### Issue 4.4: Missing Browser Security Headers, Storable Responses & Server Version Leakage (ZAP Plugins `10038`, `10063`, `10021`, `90004`, `10049` & `10036`)
* **Symptom:** OWASP ZAP Baseline and Active scans flagged six header and caching alerts across `/`, `/health`, `/robots.txt`, and `/sitemap.xml`[cite: 2, 7]:
  * **`10038` (Medium — CWE-693):** Content Security Policy (CSP) Header Not Set[cite: 2, 7]
  * **`10036` (Low — CWE-497):** Server Leaks Version Information (`Werkzeug/3.1.9 Python/3.11.17`)[cite: 2, 7]
  * **`10063` (Low — CWE-693):** Permissions Policy Header Not Set[cite: 2, 7]
  * **`10021` (Low — CWE-693):** `X-Content-Type-Options` Header Missing[cite: 2, 7]
  * **`90004` (Low — CWE-693):** `Cross-Origin-Resource-Policy` Header Missing or Invalid[cite: 2, 7]
  * **`10049` (Informational — CWE-524):** Storable and Cacheable Content[cite: 2, 7]
* **Resolution:**
  1. Updated both Dockerfiles from `CMD ["python", "-m", "app.main"]` to run production **Gunicorn** workers (`CMD ["gunicorn", "--bind", "0.0.0.0:8001", "--workers", "2", "app.main:create_app()"]` and port `8002` for `kyc-api`)[cite: 2, 7].
  2. Added an `@app.after_request` middleware hook in both `payments-api/app/main.py` and `kyc-api/app/main.py` injecting `Content-Security-Policy: default-src 'none'; frame-ancestors 'none'`, `X-Content-Type-Options: nosniff`, `Cross-Origin-Resource-Policy: same-origin`, `Permissions-Policy: geolocation=(), microphone=(), camera=()`, `Cache-Control: no-store, no-cache, must-revalidate, private`, `Pragma: no-cache`, `Expires: 0`, and `Server: SentinelPay`[cite: 2, 7]. *(Note: `Server: awselb/2.0` on perimeter `403 Forbidden` responses is injected directly by the AWS ALB when AWS WAF blocks a request and is documented as expected cloud-provider behavior[cite: 2, 7]).*

![Content Header Check](../assets/images/content%20header%20check.png)
*Figure 4.2: Post-remediation `curl.exe -i -k` verification against `https://sentinelpay-dev-alb-2097557956.eu-west-1.elb.amazonaws.com` confirming Gunicorn execution, all defensive security and anti-caching headers, and `404 NOT FOUND` on `/robots.txt`[cite: 1, 2, 7].*