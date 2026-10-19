# 03. Runbook & Troubleshooting Guide

[← Back to Main Overview](../README.md)

> **Scope:** This runbook consolidates every operational roadblock, CI/CD gate failure, OIDC federation error, Terraform static-analysis finding, container crash loop, and OWASP ZAP DAST alert encountered across the SentinelPay project, alongside the exact root cause and engineered resolution.

---

## 1. DevSecOps CI/CD, GitHub OIDC & Supply-Chain Troubleshooting

### Issue 1.1: GitHub Actions OIDC `AssumeRoleWithWebIdentity` Denied After 12 Retries
* **Symptom:** Early runs of `Test AWS OIDC Authentication` in GitHub Actions failed after 12 retries with `Error: Could not assume role with OIDC: Not authorized to perform sts:AssumeRoleWithWebIdentity`.
* **Root Cause:**
  1. The IAM role trust policy (`infra/modules/github-oidc/main.tf`) did not match the repository's customized immutable GitHub OIDC subject (`sub`) claim format (`repo:sentinelpay-team@321830913/Sentinelpay@1348603997:...`).
  2. A workflow-level `if` condition initially restricted the OIDC test job to pushes on `main`, skipping validation on pull requests.
* **Resolution:**
  1. Updated `token.actions.githubusercontent.com:sub` in `infra/modules/github-oidc/main.tf` to explicitly authorize both `repo:${var.github_organization}@321830913/${var.github_repository}@1348603997:ref:refs/heads/main` and `repo:${var.github_organization}@321830913/${var.github_repository}@1348603997:pull_request` (or wildcard `:*` within the scoped repo identity) and applied via `terraform apply -target="module.github_oidc"`.
  2. Removed the branch-restricting workflow condition so PR runs validate OIDC role assumption before merge.

### Issue 1.2: `ecr:DescribeImages` AccessDenied During Container Promotion & Digest Resolution
* **Symptom:** After OIDC authentication succeeded, `container-security.yml` failed when querying image metadata in Amazon ECR.
* **Root Cause:** The `github_deployment_policy` IAM policy attached to `sentinelpay-dev-github-actions` included ECR layer upload actions (`ecr:PutImage`, `ecr:UploadLayerPart`) but omitted read/describe metadata actions required to resolve immutable `sha256` digests.
* **Resolution:** Added `ecr:DescribeImages` and `ecr:DescribeRepositories` to `local.github_deployment_policy` in `infra/environments/dev/main.tf`.

### Issue 1.3: Conftest Job Failing with `Error: No configuration files` & S3 Remote Backend Access Denied
* **Symptom:** `policy-checks.yml` initially failed during `terraform plan` with `Error: No configuration files`, and subsequently failed during `terraform init` when accessing the S3 state bucket.
* **Root Cause:**
  1. The workflow executed Terraform from the top-level `infra/` directory instead of the environment root `infra/environments/dev`.
  2. `infra/environments/dev/backend.tf` uses an S3 remote backend (`sentinelpay-terraform-state-*`), requiring AWS credentials even for static plan generation in CI.
  3. Running `conftest test` without explicit namespace flags risked skipping custom Rego packages (`package terraform.s3`, `package terraform.encryption`, `package terraform.iam`, `package terraform.network`).
* **Resolution:**
  1. Aligned `working-directory` in `policy-checks.yml` to `infra/environments/dev` and adjusted the policy path to `../../../policy/terraform`.
  2. Added the `aws-actions/configure-aws-credentials@v6.2.3` OIDC step to `policy-checks.yml` so `terraform init` and `terraform plan` can read remote state.
  3. Invoked Conftest with `--all-namespaces` to guarantee all four Rego policy packages are evaluated against the real Terraform plan JSON.

### Issue 1.4: Amazon ECR Tag Immutability Conflict on Workflow Re-Runs & Multi-Image Scan Masking
* **Symptom:** Rerunning `container-security.yml` for the same Git commit failed because the commit SHA image tag already existed in ECR; additionally, if `payments-api` failed its Trivy scan, the workflow exited before scanning `kyc-api`.
* **Resolution:**
  1. Preserved ECR tag immutability as an intentional supply-chain control and updated the workflow to resolve and operate on `sha256` digest-qualified image references (`@sha256:...`) for Cosign signing and CycloneDX SBOM attestation.
  2. Configured both `trivy_payments` and `trivy_kyc` scan steps to complete and upload their JSON evidence before a dedicated `Enforce Trivy image security gate` (`if: always()`) step checks both outcomes and fails closed if either image contains `CRITICAL` vulnerabilities.

---

## 2. Cloud Security, Terraform & Static Analysis Troubleshooting

### Issue 2.1: `Bootstrap/` State Initialization Error
* **Symptom:** Initial execution of `terraform apply` in `Bootstrap/` failed prior to provider lock and state initialization.
  ![Bootstrap Apply Error](../assets/images/bootstrap%20apply%20error.png)
* **Resolution:** Ran `terraform init` in `Bootstrap/`, provisioned `sentinelpay-terraform-locks` and `sentinelpay-terraform-state-*` via `terraform apply -auto-approve`, and synchronized the state bucket name in `infra/environments/dev/backend.tf`.

### Issue 2.2: Remediation of Checkov (`CKV_AWS_*`) & `tfsec` Static Analysis Findings
During infrastructure validation, Checkov and `tfsec` surfaced 11 cloud misconfigurations that were systematically remediated to achieve **207 passed `tfsec` checks with 0 Critical/High/Medium/Low findings**:

| Check ID | Finding Description | Engineered Terraform Remediation |
| :--- | :--- | :--- |
| **`CKV_AWS_65`** | ECS Cluster Container Insights disabled | Enabled `setting { name = "containerInsights", value = "enabled" }` in `infra/modules/compute/main.tf`. |
| **`CKV_AWS_260` & `CKV2_AWS_20`** | `0.0.0.0/0` HTTP ingress on port 80 & missing HTTPS redirect | Restricted port 80 (`aws_lb_listener.http`) exclusively to `HTTP_301` redirection to HTTPS port 443. |
| **`CKV_AWS_103`** | ALB listener using legacy TLS policy | Enforced `ssl_policy = "ELBSecurityPolicy-TLS13-1-2-2021-06"` on `aws_lb_listener.https`. |
| **`CKV_AWS_23`** | Missing descriptions on Security Group rules | Added explicit `description` attributes to every security group and ingress/egress rule. |
| **`CKV_AWS_158` & `CKV_AWS_338`** | CloudWatch Log Groups unencrypted & retained `< 1 year` | Set `retention_in_days = 365` and attached `kms_key_id = var.kms_key_arn` across VPC Flow Logs, WAF, ECS, and CloudTrail log groups. |
| **`CKV_AWS_252`** | CloudTrail missing SNS topic notification | Added KMS-encrypted `aws_sns_topic.cloudtrail` and wired `sns_topic_name` into `aws_cloudtrail.this`. |
| **`CKV_AWS_115`** | Lambda reserved concurrency (`reserved_concurrent_executions = 5`) | Triggered an AWS account minimum-unreserved-capacity error in sandbox/dev environments; adjusted concurrency settings to fit account quotas. |
| **`CKV_AWS_109` & `CKV_AWS_111`** | KMS key policy wildcard resource permissions | Scoped KMS policy statements with explicit `Principal` ARNs, `kms:ViaService`, `aws:SourceArn`, and `kms:EncryptionContext` conditions. |

### Issue 2.3: Operational Safeguards During Teardown & Updates (KMS, ALB, RDS & S3 Object Lock)
* **KMS Key Scheduled for Deletion:** When the customer-managed KMS key (`7ed9b7e5-c6f9-4ea5-a4a9-aa4c177d3a19`) entered a pending-deletion/disabled state during testing, dependent Secrets Manager operations failed. Resolved via `aws kms cancel-key-deletion --key-id 7ed9b7e5-c6f9-4ea5-a4a9-aa4c177d3a19` followed by `aws kms enable-key`.
* **ALB Deletion Protection & RDS Parameter Group Attachment:** `enable_deletion_protection = true` on the ALB and active DB instance associations on `aws_db_parameter_group` intentionally block destructive Terraform actions unless disabled or sequenced through controlled change.
* **Versioned & Object-Locked S3 Buckets:** Because CloudTrail (`COMPLIANCE`) and KYC (`GOVERNANCE`) buckets enforce S3 Object Lock and Versioning, standard bucket deletion is blocked by design to protect audit evidence.

---

## 3. Container Runtime & Networking Troubleshooting (`503 Service Temporarily Unavailable`)

### Symptom
Initial HTTP requests to the deployed public ALB (`http://sentinelpay-dev-alb-2097557956.eu-west-1.elb.amazonaws.com`) returned `503 Service Temporarily Unavailable` because the ECS Fargate tasks failed health checks and entered a crash loop.

### Root Causes & Fixes
1. **ALB Internal Scheme & Port Egress Mismatch:**
   * *Cause:* `aws_lb.this` defaulted to `internal = true`, and `alb_to_ecs` security group egress restricted traffic to `var.container_port` (port `80`) rather than the microservice ports (`8001` and `8002`).
   * *Fix:* Set `internal = false` on the ALB, added path-based routing (`:8001` default for `payments-api`; `/v1/verify*` and `/v1/documents*` to `:8002` for `kyc-api`), and updated `alb_to_ecs` egress to allow TCP ports `8001–8002` across `var.vpc_cidr`.
2. **ECS HTTPS Egress Blocked for NAT Gateway Routing:**
   * *Cause:* `ecs_https` in `infra/modules/compute/main.tf` restricted outbound TCP port `443` to `var.vpc_cidr` (`10.0.0.0/16`). When routing through the NAT Gateway without interface endpoints, Fargate tasks could not pull images from ECR or push startup logs to CloudWatch.
   * *Fix:* Updated `ecs_https` egress `cidr_ipv4` to `"0.0.0.0/0"` on port `443`.
3. **Missing Container Environment Variable Injection (`KeyError` on Startup):**
   * *Cause:* `aws_ecs_task_definition.this` lacked an `environment` block, causing Flask to crash with `KeyError` on startup.
   * *Fix:* Added a typed `env_vars` variable to `infra/modules/compute/variables.tf` and wired it into `aws_ecs_task_definition.this`.

![Container Environment Variables](../assets/images/env%20variables.png)
*Figure 1: Wiring container environment variables into the ECS task definitions, bringing `/health` to `200 OK`.*

---

## 4. OWASP ZAP DAST Findings & Remediation Runbook

Running `zap-baseline.py` and `zap-full-scan.py` (`OWASP ZAP v2.17.0`) against the live ALB confirmed **0 High-severity vulnerabilities** and surfaced 9 Medium, Low, and Informational findings that were fully remediated:

| ZAP Plugin ID | Alert Name & Risk | Root Cause | Engineered Fix |
| :--- | :--- | :--- | :--- |
| **`10106`** | **HTTP Only Site** (Medium — `CWE-311`) | ALB deployed with `acm_certificate_arn = null` (port 80 only); switching directly from `http_forward` to `http` caused an AWS `DuplicateListener` error. | Generated a 2048-bit RSA cert via OpenSSL, imported into AWS ACM, provisioned `aws_lb_listener.https` (`:443`), and sequenced `http_forward` removal via `depends_on` to enforce `HTTP_301` redirect on `:80`. |
| **`90022` & `10023`** | **Application Error Disclosure & Debug Error Messages** (Low — `CWE-550` / `CWE-1295`) | Global `@app.errorhandler(Exception)` caught Werkzeug `HTTPException` (`404 Not Found`) on `/`, `/robots.txt`, and `/sitemap.xml`, returning `500 INTERNAL SERVER ERROR` with `{"error": "internal server error"}`. | Registered `@app.errorhandler(HTTPException)` before `@app.errorhandler(Exception)` in both services to return `404` (`{"error": "resource not found"}`) and changed the generic 500 fallback message to `"request could not be processed"`. |
| **`10038`, `10063`, `10021`, `90004`, `10049`** | **Missing CSP, Permissions-Policy, `nosniff`, CORP & Anti-Caching Headers** (Medium / Low / Info) | Flask responses lacked defensive browser security policies and explicit `Cache-Control: no-store` directives. | Added an `@app.after_request` hook in both `payments-api/app/main.py` and `kyc-api/app/main.py` injecting `Content-Security-Policy: default-src 'none'; frame-ancestors 'none'`, `X-Content-Type-Options: nosniff`, `Cross-Origin-Resource-Policy: same-origin`, `Permissions-Policy: geolocation=(), microphone=(), camera=()`, `Cache-Control: no-store, no-cache, must-revalidate, private`, `Pragma: no-cache`, and `Expires: 0`. |
| **`10036`** | **Server Version Leak via `"Server"` Header** (Low — `CWE-497`) | Dockerfiles ran `CMD ["python", "-m", "app.main"]`, exposing `Werkzeug/3.1.9 Python/3.11.17` in the `Server` header. | Switched both Dockerfiles to production **Gunicorn** workers and set `response.headers["Server"] = "SentinelPay"` in `@app.after_request`. |

![Content Header Check](../assets/images/content%20header%20check.png)
*Figure 2: Live `curl.exe -i -k` verification against the HTTPS ALB confirming Gunicorn, defensive headers, and clean `404 NOT FOUND` responses.*