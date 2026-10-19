# SentinelPay: Securing a Pan-African Payments Platform on AWS

![Project Status](https://img.shields.io/badge/Status-Completed-success?style=flat-square)
![Environment](https://img.shields.io/badge/Platform-AWS%20(eu--west--1)%20%7C%20ECS%20Fargate%20%7C%20Terraform-FF9900?style=flat-square)
![CI/CD](https://img.shields.io/badge/DevSecOps-GitHub%20Actions%20%7C%20OIDC%20%7C%20OPA%20%7C%20Cosign-2088FF?style=flat-square)
![Frameworks](https://img.shields.io/badge/Compliance-SOC%202%20%7C%20NIST%20CSF%20%7C%20CIS%20%7C%20SABSA%20%7C%20OWASP-blue?style=flat-square)

> **Executive Summary:** SentinelPay Technologies Ltd is a pan-African fintech platform processing card and bank-transfer payments for ~1,400 merchants across Nigeria, Ghana, Kenya, and Rwanda. Following an external disclosure of a production Insecure Direct Object Reference (IDOR) vulnerability, our five-person security engineering team executed a comprehensive, four-phase security transformation across the application, CI/CD pipeline, cloud infrastructure, and runtime edge layers. We remediated all 11 application vulnerability classes (`V-APP-01` through `V-APP-11`) and hardened the microservice containers (`payments-api` and `kyc-api`), built a fail-closed GitHub Actions DevSecOps pipeline with keyless AWS OIDC authentication, OPA/Conftest policy-as-code, Syft CycloneDX SBOMs, and Cosign container signing, provisioned a private-by-default Multi-AZ AWS architecture in `eu-west-1` via modular Terraform, and verified the live deployment with OWASP ZAP (`v2.17.0`) Dynamic Application Security Testing (DAST).

---

## Table of Contents
- [Tools Used](#tools-used)
- [Skills Learned](#skills-learned)
- [1. Problem Statement & Objectives](#1-problem-statement--objectives)
- [2. Architecture & Design Overview](#2-architecture--design-overview)
- [3. Technology Stack & Tooling](#3-technology-stack--tooling)
- [4. Full Documentation Index](#4-full-documentation-index)
- [5. Four-Phase Implementation Walkthrough](#5-four-phase-implementation-walkthrough)
- [6. Validation, Testing & Proof of Work](#6-validation-testing--proof-of-work)
- [7. Key Challenges & Trade-Offs](#7-key-challenges--trade-offs)
- [8. Future Enhancements](#8-future-enhancements)

---

## Tools Used

**Application, Containers & Databases**  
![Python 3.11](https://img.shields.io/badge/Python_3.11-3776AB?style=for-the-badge&logo=python&logoColor=white)
![Flask](https://img.shields.io/badge/Flask-000000?style=for-the-badge&logo=flask&logoColor=white)
![Gunicorn](https://img.shields.io/badge/Gunicorn-499848?style=for-the-badge&logo=gunicorn&logoColor=white)
![PostgreSQL 17](https://img.shields.io/badge/PostgreSQL_17-4169E1?style=for-the-badge&logo=postgresql&logoColor=white)
![Redis](https://img.shields.io/badge/Redis-DC382D?style=for-the-badge&logo=redis&logoColor=white)
![Docker](https://img.shields.io/badge/Docker-2496ED?style=for-the-badge&logo=docker&logoColor=white)
![Alpine Linux](https://img.shields.io/badge/Alpine_Linux-0D597F?style=for-the-badge&logo=alpinelinux&logoColor=white)

**Cloud Infrastructure & Detection (AWS `eu-west-1`)**  
![AWS](https://img.shields.io/badge/AWS_(eu--west--1)-232F3E?style=for-the-badge&logo=amazonwebservices&logoColor=FF9900)
![Terraform](https://img.shields.io/badge/Terraform-844FBA?style=for-the-badge&logo=terraform&logoColor=white)
![Amazon ECS Fargate](https://img.shields.io/badge/ECS_Fargate-FF9900?style=for-the-badge&logo=amazonecs&logoColor=white)
![Amazon RDS](https://img.shields.io/badge/Amazon_RDS-527FFF?style=for-the-badge&logo=amazonrds&logoColor=white)
![Amazon S3](https://img.shields.io/badge/Amazon_S3_Object_Lock-569A31?style=for-the-badge&logo=amazons3&logoColor=white)
![AWS KMS & Secrets Manager](https://img.shields.io/badge/KMS_%26_Secrets_Manager-DD344C?style=for-the-badge&logo=amazonaws&logoColor=white)
![AWS WAFv2 & ALB](https://img.shields.io/badge/AWS_WAFv2_%26_ALB-8C4FFF?style=for-the-badge&logo=amazonaws&logoColor=white)
![GuardDuty & Security Hub](https://img.shields.io/badge/GuardDuty_%7C_Security_Hub_%7C_CloudTrail-DD344C?style=for-the-badge&logo=amazonaws&logoColor=white)

**DevSecOps, Supply Chain, DAST & Analytics**  
![GitHub Actions](https://img.shields.io/badge/GitHub_Actions-2088FF?style=for-the-badge&logo=githubactions&logoColor=white)
![AWS OIDC](https://img.shields.io/badge/AWS_OIDC_Federation-FF9900?style=for-the-badge&logo=openid&logoColor=white)
![OPA Conftest](https://img.shields.io/badge/OPA_Rego_%26_Conftest-7D9199?style=for-the-badge&logo=openpolicyagent&logoColor=white)
![Semgrep](https://img.shields.io/badge/Semgrep-17B585?style=for-the-badge)
![Bandit](https://img.shields.io/badge/Bandit_SAST-FFD43B?style=for-the-badge&logo=python&logoColor=black)
![Gitleaks](https://img.shields.io/badge/Gitleaks-E34F26?style=for-the-badge&logo=git&logoColor=white)
![Trivy](https://img.shields.io/badge/Trivy_SCA_%26_Image-1904DA?style=for-the-badge&logo=aquasecurity&logoColor=white)
![Checkov & tfsec](https://img.shields.io/badge/Checkov_%26_tfsec-6B4FBB?style=for-the-badge)
![Syft & Cosign](https://img.shields.io/badge/Syft_SBOM_%26_Cosign-4B32C3?style=for-the-badge)
![OWASP ZAP](https://img.shields.io/badge/OWASP_ZAP_v2.17.0-00549E?style=for-the-badge&logo=owasp&logoColor=white)
![Power BI](https://img.shields.io/badge/Power_BI-F2C811?style=for-the-badge&logo=powerbi&logoColor=black)
![OpenSSL](https://img.shields.io/badge/OpenSSL-721412?style=for-the-badge&logo=openssl&logoColor=white)

---

## Skills Learned

**Application Security (AppSec) & API Penetration Testing**  
![SQLi Remediation](https://img.shields.io/badge/SQLi_Parameterized_Queries-Critical_Fix-critical?style=flat-square)
![Asymmetric JWT](https://img.shields.io/badge/RS256_Asymmetric_JWT-Auth_Hardening-critical?style=flat-square)
![IDOR Prevention](https://img.shields.io/badge/IDOR_Ownership_Enforcement-Access_Control-orange?style=flat-square)
![SSRF Mitigation](https://img.shields.io/badge/SSRF_DNS_%26_IP_Validation-Network_Filter-orange?style=flat-square)
![TOCTOU Locking](https://img.shields.io/badge/PostgreSQL_Row--Level_Locking-Race_Condition_Fix-critical?style=flat-square)
![Argon2id Hashing](https://img.shields.io/badge/Argon2id_Zero--Downtime_Migration-Cryptography-blue?style=flat-square)
![Secure Serialization](https://img.shields.io/badge/Signed_JSON_Serialization-RCE_Prevention-critical?style=flat-square)
![Redis Rate Limiting](https://img.shields.io/badge/Redis_Canonical_Rate_Limiting-Brute--Force_Defense-yellow?style=flat-square)
![Structured Audit Logging](https://img.shields.io/badge/Secret--Masked_JSON_Audit_Logs-SOC_2_Compliance-success?style=flat-square)
![Container Hardening](https://img.shields.io/badge/Non--Root_Alpine_Containers-Gunicorn_%2B_HEALTHCHECK-0D597F?style=flat-square)
![Live OWASP ZAP DAST](https://img.shields.io/badge/Live_OWASP_ZAP_DAST-ACM_TLS_%2B_Security_Headers-00549E?style=flat-square)

**DevSecOps CI/CD, Policy as Code & Software Supply-Chain Security**  
![Reusable Workflows](https://img.shields.io/badge/Reusable_GitHub_Actions-Modular_CI%2FCD-2088FF?style=flat-square)
![Keyless AWS OIDC](https://img.shields.io/badge/Keyless_AWS_OIDC-Workload_Identity_Federation-FF9900?style=flat-square)
![OPA Rego Policy](https://img.shields.io/badge/OPA_Rego_%26_Conftest-Policy_as_Code-7D9199?style=flat-square)
![CycloneDX SBOM](https://img.shields.io/badge/Syft_CycloneDX_SBOM-Software_Transparency-informational?style=flat-square)
![Cosign Provenance](https://img.shields.io/badge/Sigstore_Cosign_Keyless_Signing-Supply_Chain_Security-4B32C3?style=flat-square)
![Immutable ECR Digests](https://img.shields.io/badge/Immutable_ECR_SHA256_Digests-Artifact_Integrity-success?style=flat-square)
![Git History Secret Baselining](https://img.shields.io/badge/Gitleaks_History_Baselining-Secret_Governance-E34F26?style=flat-square)

**Cloud Security Architecture, Detection Engineering & DAST**  
![Modular Terraform](https://img.shields.io/badge/Modular_Terraform_IaC-S3_%26_DynamoDB_State_Locking-844FBA?style=flat-square)
![Zero-Trust VPC](https://img.shields.io/badge/Multi--AZ_Private_Subnets-SG_Reference_Chaining-232F3E?style=flat-square)
![KMS Envelope Encryption](https://img.shields.io/badge/Customer--Managed_KMS-Split_Admin%2FUser_Roles-DD344C?style=flat-square)
![Automated Secret Rotation](https://img.shields.io/badge/30--Day_RDS_Secret_Rotation-Code--Signed_Lambda-success?style=flat-square)
![S3 Object Lock](https://img.shields.io/badge/S3_Object_Lock-COMPLIANCE_%26_GOVERNANCE-569A31?style=flat-square)
![Deception Engineering](https://img.shields.io/badge/IAM_Honeytoken_Tripwire-CloudTrail_%2B_EventBridge-critical?style=flat-square)
![Automated SOAR Containment](https://img.shields.io/badge/GuardDuty_Auto--Quarantine-ENI_Isolation_Lambda-important?style=flat-square)

---

## 1. Problem Statement & Objectives

### Background & Risk / Bottleneck
After two years of rapid feature delivery without dedicated security engineering, an external researcher disclosed a production IDOR vulnerability. A full-stack security audit uncovered critical exposures across four operational layers:
* **Phase 1 Risk — Application & Container Vulnerabilities:** Automated static scanning (`Semgrep`, `Gitleaks`, `Bandit`) surfaced **36 Critical**, **3 High**, **20 Medium**, and **5 Low** findings. Manual code review confirmed active exposure to SQL Injection (`V-APP-01`), forgeable `alg: none` JWTs (`V-APP-02`), horizontal IDOR (`V-APP-03`), SSRF (`V-APP-04`), wallet double-spend race conditions (`V-APP-05`), weak MD5 password hashes (`V-APP-06`), mass assignment (`V-APP-07`), unthrottled auth endpoints (`V-APP-08`), verbose stack traces (`V-APP-09`), `pickle` Remote Code Execution (`V-APP-10`), missing compliance audit logs (`V-APP-11`), and root-privileged Docker containers running the development Werkzeug server.
* **Phase 2 Risk — Unverified CI/CD & Software Supply Chain:** Uncontrolled pushes to `main`, fragmented CI logic, static cloud access keys, lack of executable infrastructure policy, mutable container tags, and unsigned images allowed vulnerable code and unverified artifacts to progress toward deployment.
* **Phase 3 Risk — Cloud Configuration Drift & Detection Blind Spots:** Ad-hoc cloud provisioning risked public exposure of compute and database tiers, unencrypted data stores and logs, unrotated database credentials, and the absence of centralized threat detection or automated containment.
* **Phase 4 Risk — Runtime Edge & Transport Exposure:** Live container deployments required public ALB path-based routing, NAT Gateway egress tuning, TLS 1.3/1.2 termination, HTTP-to-HTTPS redirection, separated HTTP exception boundaries, and defensive browser security headers to withstand active DAST probing.

### Core Objectives
* **Objective 1 (Phase 1 — AppSec Code Remediation & Container Hardening):** Remediate and exploit-verify all 11 application vulnerabilities (`V-APP-01` to `V-APP-11`) across `payments-api` (`:8001`) and `kyc-api` (`:8002`), and refactor Dockerfiles to minimal `python:3.11-alpine` images running as non-root `appuser` with Gunicorn workers and native `HEALTHCHECK` probes.
* **Objective 2 (Phase 2 — DevSecOps CI/CD, Policy as Code & Supply Chain):** Protect `main` via pull-request governance, orchestrate four reusable GitHub Actions workflows (`ci.yml`), replace static AWS keys with short-lived GitHub OIDC credentials, enforce OPA/Conftest Rego policies against Terraform plans, and bind Syft CycloneDX SBOMs and keyless Cosign signatures to immutable Amazon ECR image digests.
* **Objective 3 (Phase 3 — Cloud Security & Modular Terraform Infrastructure):** Provision a modular AWS platform in `eu-west-1` with S3/DynamoDB remote state locking, Multi-AZ public/private subnets, VPC endpoints, customer-managed KMS encryption, 30-day Secrets Manager rotation, S3 Object Lock, CloudTrail, GuardDuty, Security Hub, AWS Config, an IAM honeytoken, and automated high-severity ENI quarantine.
* **Objective 4 (Phase 4 — Live Cloud Deployment & OWASP ZAP DAST Remediation):** Deploy the hardened containers to AWS ECS Fargate behind an AWS WAFv2-protected Application Load Balancer, execute passive and active OWASP ZAP (`v2.17.0`) scans, enable ACM HTTPS (`:443`) + HTTP `301` redirects, and inject defensive HTTP security headers.

### Team Structure & Engineering Tracks

| Role | Owner | Track & Responsibilities |
| :--- | :--- | :--- |
| **Team Lead** | Tega | STRIDE threat modelling, PR review, 5-plane constraint verification, and attack-simulation coordination. |
| **Lead AppSec Engineer** | Chinaza Nnamani | Vulnerability scanning (`security_scan.py`), Power BI triage dashboard, manual code review, `V-APP-01`–`V-APP-11` fixes, Alpine/Gunicorn container hardening, and live OWASP ZAP DAST remediation. |
| **Cloud Engineer — Network & Compute** | Femi | Multi-AZ VPC, public/private subnet isolation, NAT, VPC endpoints, ECS Fargate, ALB, AWS WAFv2, and IAM roles. |
| **Cloud Engineer — Data, Identity & Detection** | Ben / Sunday Abiodun | Customer-managed KMS, Multi-AZ RDS PostgreSQL, ElastiCache Redis, S3 Object Lock, Secrets Manager rotation, GuardDuty, CloudTrail, Security Hub, AWS Config, IAM honeytokens, and quarantine automation. |
| **DevSecOps Engineer** | Mohammed / Muhammad Asif Salaudeen | Reusable GitHub Actions CI/CD architecture, GitHub-to-AWS OIDC federation, OPA/Conftest policy-as-code, Syft CycloneDX SBOMs, and Cosign keyless signing/verification. |

---

## 2. Architecture & Design Overview

![High-Level Architecture Diagram](./assets/images/architecture.png)

### Four-Phase End-to-End Architecture Diagram

```mermaid
graph TB
    subgraph Phase1["Phase 1: Hardened Application & Containers"]
        AppCode[Flask Microservices: payments-api :8001 & kyc-api :8002<br/>Parameterized SQL + RS256 JWT + SELECT FOR UPDATE<br/>+ Argon2id + Redis Limiter + itsdangerous + Audit Logger]
        Docker[Hardened Dockerfiles: python:3.11-alpine<br/>Non-Root appuser + HEALTHCHECK + Gunicorn Workers]
        AppCode --> Docker
    end

    subgraph Phase2["Phase 2: DevSecOps CI/CD & Supply Chain (.github/workflows/ci.yml)"]
        Docker --> SecWf[security-scans.yml<br/>Gitleaks + Bandit + Semgrep + Trivy FS]
        Docker --> InfraWf[infrastructure-security.yml<br/>Checkov + tfsec + AWS OIDC Test]
        Docker --> PolWf[policy-checks.yml<br/>OIDC + Terraform Plan JSON + OPA Conftest]
        Docker --> ContWf[container-security.yml<br/>Trivy Image Gate + Syft CycloneDX SBOM]
        ContWf -->|OIDC AssumeRoleWithWebIdentity| ECR[(Amazon ECR<br/>Immutable Tags & SHA256 Digests)]
        ECR --> Cosign[Cosign Keyless Sign + SBOM Attest<br/>+ verify_supply_chain.sh]
    end

    subgraph Phase3["Phase 3: AWS Cloud Infrastructure & Detection (eu-west-1)"]
        subgraph PrivateVPC["Private Subnets (eu-west-1a / 1b) + VPC Endpoints"]
            PayECS[ECS Fargate: payments-api :8001]
            KycECS[ECS Fargate: kyc-api :8002]
            RDS[(RDS PostgreSQL 17 Multi-AZ<br/>force_ssl=1 / KMS / IAM Auth)]
            Redis[(ElastiCache Redis 2-Node<br/>At-Rest KMS & In-Transit TLS)]
            PayECS --> RDS & Redis
            KycECS --> RDS & Redis
        end
        S3KYC[(S3 KYC Bucket<br/>KMS + Object Lock GOVERNANCE)]
        RotLambda[Secrets Manager Rotation Lambda<br/>30-Day Auto Rotation]
        Detect[CloudTrail COMPLIANCE + GuardDuty<br/>+ Security Hub + Config + Honeytoken] -->|EventBridge Severity >= 7| QuarLambda[Quarantine Lambda<br/>Isolates Compromised ENIs]
        KycECS --> S3KYC
        RotLambda <--> RDS
    end

    subgraph Phase4["Phase 4: Live Edge Routing & OWASP ZAP DAST"]
        ZAP([Clients / OWASP ZAP v2.17.0]) -->|HTTPS :443 / HTTP :80 301 Redirect| WAF[AWS WAFv2 Regional Web ACL<br/>Common & KnownBadInputs RuleSets]
        WAF --> ALB[Public Application Load Balancer<br/>ACM TLS 1.3/1.2 + Security Headers]
        ALB -->|Default :8001| PayECS
        ALB -->|/v1/verify* & /v1/documents* :8002| KycECS
    end

    Cosign -.->|Deploys Verified Digest| PayECS & KycECS
```

### Key Design Decisions Across the Four Phases
1. **Phase 1 — Defense-in-Depth Application & Container Hardening:** Replaced string-interpolated SQL with `psycopg2` parameterized `%s` queries (`V-APP-01`), upgraded JWTs from symmetric `HS256` to asymmetric `RS256` (`V-APP-02`), enforced SQL/S3 caller ownership checks (`V-APP-03`), locked wallet rows during debits via `SELECT ... FOR UPDATE` (`V-APP-05`), and migrated containers to non-root `python:3.11-alpine` images running Gunicorn.
2. **Phase 2 — Reusable Fail-Closed CI/CD & Digest-Bound Supply Chain:** Separated CI orchestration (`ci.yml`) into four specialist reusable workflows with 5-minute timeouts, eliminated static AWS keys via GitHub OIDC (`sts:AssumeRoleWithWebIdentity`), enforced custom OPA Rego policies via Conftest (`--all-namespaces`), scanned both service images before enforcing the Trivy gate (`if: always()`), and bound Syft CycloneDX SBOMs and keyless Cosign signatures directly to immutable ECR `sha256` digests.
3. **Phase 3 — Private-by-Default Cloud Architecture & Automated Containment:** Isolated ECS Fargate, Multi-AZ RDS PostgreSQL 17, and ElastiCache Redis inside private subnets with security-group-reference-only ingress, customer-managed KMS encryption (with separated `kms-admin` and `kms-user` roles), 30-day signed Lambda secret rotation, S3 Object Lock (`COMPLIANCE` on CloudTrail; `GOVERNANCE` on KYC), an IAM honeytoken tripwire, and a GuardDuty (`severity >= 7`) Quarantine Lambda.
4. **Phase 4 — TLS 1.3/1.2 Edge Enforcement & DAST Response Hardening:** Configured path-based ALB routing (`:8001` default for `payments-api`; `/v1/verify*` and `/v1/documents*` to `:8002` for `kyc-api`), imported an X.509 certificate into AWS ACM for HTTPS (`:443`) + HTTP `301` redirects, separated `@app.errorhandler(HTTPException)` from `Exception` to stop `404` routes from returning `500`, and injected strict `@app.after_request` browser security and anti-caching headers.

---

## 3. Technology Stack & Tooling

| Phase | Tool / Platform | Role in SentinelPay | Why It Was Chosen |
| :--- | :--- | :--- | :--- |
| **Phase 1: AppSec & Containers** | Python 3.11 (`alpine`), Flask, Gunicorn, `psycopg2`, `argon2-cffi`, `itsdangerous`, `Flask-Limiter`, Power BI | Core microservices (`:8001`, `:8002`), vulnerability triage, and runtime hardening | Enforces parameterized SQL, Argon2id hashing, signed sessions, Redis rate limiting, non-root execution, and deduplicated triage. |
| **Phase 2: DevSecOps & Supply Chain** | GitHub Actions, AWS OIDC, Gitleaks, Bandit, Semgrep, Trivy, Checkov, tfsec, OPA Conftest, Syft, Cosign | Automated PR security gates, policy-as-code, CycloneDX SBOMs, and keyless image signing | Enforces fail-closed shift-left security, removes long-lived cloud keys, and verifies immutable ECR image provenance. |
| **Phase 3: Cloud & Detection** | AWS (`eu-west-1`), Terraform, VPC, ECS Fargate, RDS PostgreSQL 17, Redis, S3, KMS, Secrets Manager, CloudTrail, GuardDuty, Security Hub, Config, EventBridge, Lambda | Modular cloud infrastructure, envelope encryption, secret rotation, compliance, and ENI quarantine | Eliminates configuration drift, isolates workloads in private subnets, and automates threat detection and response. |
| **Phase 4: Edge & DAST** | AWS ALB, AWS WAFv2, AWS ACM, OpenSSL, OWASP ZAP (`v2.17.0`), `curl` | Public ingress filtering, TLS termination, and live dynamic security scanning | Validates live endpoints against injection, transport, and header weaknesses behind AWS WAFv2. |

---

## 4. Full Documentation Index

Browse the deep-dive engineering documentation in the [`/docs`](./docs) directory, where every guide is organized across the exact same four phases:

| Document | Description |
| :--- | :--- |
| [**01. System Architecture & Security Controls**](./docs/architecture.md) | 4-phase architectural blueprint covering microservice routes (`V-APP-01`–`V-APP-11`), reusable CI/CD workflows & OPA Rego policies, the 10 Terraform cloud modules, and DAST edge routing. |
| [**02. End-to-End Setup & Implementation Guide**](./docs/setup-guide.md) | 4-phase step-by-step implementation guide with exact commands and code snippets from AppSec remediation to CI/CD gating, Terraform provisioning, and OWASP ZAP DAST remediation. |
| [**03. Runbook & Troubleshooting Guide**](./docs/troubleshooting.md) | 4-phase troubleshooting runbook detailing root causes and fixes for secret baselines, OIDC trust errors, Conftest namespaces, Checkov/tfsec findings, ECS `503` crash loops, and ZAP alerts. |

---

## 5. Four-Phase Implementation Walkthrough

### Phase 1: Application Security (AppSec) Code Remediation & Container Hardening
1. **Mapping, Scanning & Power BI Triage:** Mapped all 20 routes across `payments-api` (`:8001`) and `kyc-api` (`:8002`), executed `security_scan.py` (`Semgrep`, `Bandit`, `Gitleaks`), and built a **Microsoft Power BI Vulnerability Dashboard** to deduplicate and prioritize the **36 Critical**, **3 High**, **20 Medium**, and **5 Low** findings across the codebase.
2. **Critical Path Code Remediation (`V-APP-01` – `V-APP-11`):**
   * **`V-APP-01` (SQLi — Critical):** Replaced string interpolation with `psycopg2` parameterized `%s` queries in `/v1/transactions/search` and `/v1/verify/lookup`.
   * **`V-APP-02` (JWT — Critical):** Migrated from `HS256`/`alg: none` to asymmetric `RS256` (`JWT_PRIVATE_KEY` / `JWT_PUBLIC_KEY`) with 15-minute expiry and refresh-token rotation.
   * **`V-APP-03` (IDOR — High):** Enforced `WHERE id = %s AND user_id = %s` on account/wallet queries and restricted S3 KYC keys to `users/{user_id}/`.
   * **`V-APP-04` (SSRF — High):** Built `validate_callback_url` to enforce `HTTPS`, block private/loopback/link-local/metadata IPs, disable redirects (`allow_redirects=False`), and hardcode BVN provider URLs.
   * **`V-APP-05` (Race Condition — Critical):** Wrapped wallet debits in a transaction block with PostgreSQL `SELECT ... FOR UPDATE` row-level locking.
   * **`V-APP-06` (Hashing — High):** Upgraded from `hashlib.md5()` to `Argon2id` (`argon2-cffi`) with transparent login-time migration for legacy MD5 hashes.
   * **`V-APP-07` (Mass Assignment — High):** Whitelisted only `account_number` and `currency` on `PUT /v1/accounts/<account_id>/profile`.
   * **`V-APP-08` (Rate Limiting — Medium):** Deployed Redis-backed `Flask-Limiter` (`5/minute`) keyed by IP and hashed canonical email/E.164 phone identifiers.
   * **`V-APP-09` (Verbose Errors — Low):** Set `debug=False` and registered global error handlers returning sanitized JSON while logging tracebacks server-side.
   * **`V-APP-10` (Deserialization — Critical):** Replaced `pickle.loads()` on `/v1/admin/session/restore` with `itsdangerous.URLSafeTimedSerializer`.
   * **`V-APP-11` (Audit Logging — Medium):** Engineered the secret-masking `sentinelpay.audit` structured JSON logger for all wallet and KYC state changes.
3. **Container Hardening (`Dockerfile`):** Refactored both Dockerfiles to `python:3.11-alpine`, upgraded OS packages (`apk update && apk upgrade --no-cache`), removed lock/backup files, enforced non-root `USER appuser`, added native `HEALTHCHECK` probes, and launched production **Gunicorn** workers.

### Phase 2: DevSecOps CI/CD Pipeline, Policy as Code & Supply-Chain Security
1. **Repository Governance & Reusable Workflows:** Protected `main` with PR review and status-check requirements and refactored `.github/workflows/ci.yml` to orchestrate four domain-specific reusable workflows (`security-scans.yml`, `infrastructure-security.yml`, `container-security.yml`, and `policy-checks.yml`) with 5-minute fail-closed timeouts.
2. **Keyless AWS OIDC Federation:** Configured GitHub Actions to assume `arn:aws:iam::105045466108:role/sentinelpay-dev-github-actions` via `token.actions.githubusercontent.com` (`sts:AssumeRoleWithWebIdentity`) locked to the repository's `main` and `pull_request` subjects.
3. **Executable Policy as Code (`OPA / Conftest`):** Authored four Rego policy packages (`s3_public.rego`, `network_ingress.rego`, `encryption.rego`, `iam_wildcard.rego`), validated them against paired fixtures in `policy-tests/`, and wired `policy-checks.yml` to evaluate live Terraform plan JSON from `infra/environments/dev` using `--all-namespaces`.
4. **Combined Trivy Image Gate, Syft SBOMs & Cosign Provenance:** Configured `container-security.yml` to scan both `payments-api` and `kyc-api` images before enforcing a combined `if: always()` CRITICAL gate, generate CycloneDX SBOMs (`payments-sbom.cdx.json`, `kyc-sbom.cdx.json`) with **Syft**, push to immutable **Amazon ECR** repositories, resolve `@sha256` digests, sign and attest both digests keylessly with **Cosign**, and verify provenance via `verify_supply_chain.sh`.

### Phase 3: Cloud Security & Modular Terraform Infrastructure Provisioning (`eu-west-1`)
1. **Encrypted Remote State Bootstrap (`Bootstrap/`):** Provisioned a versioned, encrypted S3 state bucket (`sentinelpay-terraform-state-*`, `prevent_destroy = true`) and a DynamoDB lock table (`sentinelpay-terraform-locks`) with KMS server-side encryption and 35-day Point-in-Time Recovery (PITR).
2. **Multi-AZ Network, Edge & Compute (`network`, `edge`, `compute`):** Provisioned a custom VPC across `eu-west-1a/1b` with 2 public subnets, 2 private subnets (`map_public_ip_on_launch = false`), NAT Gateways, VPC Endpoints (S3, ECR, Secrets Manager, KMS, CloudWatch), an empty `default-deny` default security group, 365-day KMS-encrypted VPC Flow Logs, an ECS Fargate cluster with `ContainerInsights` enabled, and an ALB protected by AWS WAFv2 (`CommonRuleSet` & `KnownBadInputsRuleSet`).
3. **Encrypted Data Stores & 30-Day Secret Rotation (`kms`, `rds`, `data`, `secrets-rotation`):** Created a customer-managed KMS key (`enable_key_rotation = true`) with separated `kms-admin` and `kms-user` roles. Deployed Multi-AZ RDS PostgreSQL 17 (`rds.force_ssl = 1`, IAM auth, Enhanced Monitoring), a 2-node ElastiCache Redis replication group (at-rest KMS + in-transit TLS + AUTH token), an S3 KYC bucket with Object Lock (`GOVERNANCE`, 90 days), and a code-signed Python 3.13 Lambda rotating PostgreSQL credentials every 30 days.
4. **Threat Detection, Compliance & Automated Quarantine (`detection`, `identity-center`):** Enabled multi-region CloudTrail (S3 Object Lock `COMPLIANCE` for 365 days, KMS, SNS notifications), GuardDuty (S3, EBS malware, RDS login, Lambda network monitoring), Security Hub (**FSBP v1.0.0** & **CIS v5.0.0**), and an AWS Config **CIS v1.4 Level 2 Conformance Pack**. Deployed an unprivileged IAM Honeytoken (`sentinelpay-dev-honeytoken`) wired to EventBridge and a Quarantine Lambda (`sentinelpay-dev-quarantine`) that isolates compromised ENIs on GuardDuty findings with `severity >= 7`.

### Phase 4: Live Container Deployment, OWASP ZAP DAST Execution & Remediation
1. **ECS Fargate Stabilization (Fixing `503 Service Temporarily Unavailable`):** Configured public ALB path-based routing (`:8001` default for `payments-api`; `/v1/verify*` and `/v1/documents*` to `:8002` for `kyc-api`), updated `alb_to_ecs` security group egress to allow ports `8001–8002`, opened `ecs_https` egress (`0.0.0.0/0` on `:443`) for NAT Gateway access to ECR and CloudWatch, and injected runtime `env_vars` into the ECS task definitions to bring `/health` to `200 OK`.
2. **OWASP ZAP (`v2.17.0`) Baseline & Active Scanning:** Executed `zap-baseline.py` and `zap-full-scan.py` against `http://sentinelpay-dev-alb-2097557956.eu-west-1.elb.amazonaws.com`, confirming **0 High-severity vulnerabilities** while identifying 9 Medium/Low/Informational transport, error-handling, and header findings.
3. **Full DAST Remediation:**
   * **ACM TLS 1.3/1.2 & HTTP `301` Redirect (Fixes Plugin `10106`):** Generated a 2048-bit RSA X.509 certificate via OpenSSL, imported it into AWS ACM (`eu-west-1`), provisioned `aws_lb_listener.https` (`:443`), and sequenced removal of `http_forward` via `depends_on` to enforce `HTTP_301` redirects on port `80`.
   * **HTTP Exception Boundary (Fixes Plugins `90022` & `10023`):** Registered `@app.errorhandler(HTTPException)` before `@app.errorhandler(Exception)` in both services so unmapped routes (`/`, `/robots.txt`, `/sitemap.xml`) return clean `404 Not Found` (`{"error": "resource not found"}`) instead of `500 Internal Server Error`, and updated the 500 fallback message to `"request could not be processed"`.
   * **Defensive Security Headers & Banner Suppression (Fixes Plugins `10038`, `10063`, `10021`, `90004`, `10049` & `10036`):** Switched Dockerfiles to **Gunicorn** and added an `@app.after_request` hook injecting `Content-Security-Policy`, `X-Content-Type-Options: nosniff`, `Cross-Origin-Resource-Policy: same-origin`, `Permissions-Policy`, `Cache-Control: no-store, no-cache, must-revalidate, private`, `Pragma: no-cache`, `Expires: 0`, and `Server: SentinelPay`.

---

## 6. Validation, Testing & Proof of Work

### Four-Phase Baseline vs. Post-Implementation Results

| Phase | Metric / Security Control | Baseline (Before) | Post-Implementation (After) | Status |
| :--- | :--- | :--- | :--- | :--- |
| **Phase 1: AppSec** | **Application Vulnerabilities (`V-APP-01`–`V-APP-11`)** | 36 Critical, 3 High, 20 Medium, 5 Low (SQLi, `alg: none` JWT, IDOR, SSRF, TOCTOU Race, MD5, Mass Assignment, RCE) | **0 Critical, 0 High**; parameterized SQL, `RS256` JWT, `SELECT ... FOR UPDATE`, `Argon2id`, `itsdangerous`, Redis rate limit, & JSON audit logs verified | Passed |
| **Phase 1: Containers** | **Dockerfile & Runtime Hardening** | Root `python:3.11` base image running Werkzeug dev server (`python -m app.main`) without health checks | Minimal `python:3.11-alpine`, non-root `USER appuser`, native `HEALTHCHECK`, and production **Gunicorn** workers | Passed |
| **Phase 2: CI/CD** | **Pull-Request Security Gates (`ci.yml`)** | Failing SAST/Secret/SCA/Container scans and failing `sts:AssumeRoleWithWebIdentity` OIDC | **All 10 CI jobs passing** (`test-workflow`, `Gitleaks`, `Bandit`, `Semgrep`, `Trivy FS`, `Checkov`, `tfsec`, `Trivy Image`, `AWS OIDC`, `OPA Conftest`) | Passed |
| **Phase 2: Supply Chain** | **Artifact Provenance (`Syft` + `Cosign` + `ECR`)** | Mutable tags with no SBOMs, no signatures, and no pre-deployment verification | Immutable ECR tags resolved to `@sha256` digests, CycloneDX SBOMs attested, and keyless Cosign signatures verified via `verify_supply_chain.sh` | Passed |
| **Phase 3: CloudSec** | **Terraform IaC Security (`Checkov` & `tfsec`)** | Unencrypted logs, `<1 yr` retention, missing CloudTrail SNS, open HTTP, missing SG descriptions | **`tfsec`: 207 passed, 0 Critical/High/Medium/Low**; Checkov controls passed; 365-day KMS logs, Multi-AZ RDS/Redis, S3 Object Lock, & VPC Endpoints active | Passed |
| **Phase 3: Detection** | **Cloud Audit, Honeytoken & Auto-Quarantine** | No centralized cloud audit trail, deception tripwires, or automated containment | Multi-region CloudTrail + GuardDuty + Security Hub (CIS/FSBP) + Config + IAM Honeytoken + EventBridge Severity `>= 7` Quarantine Lambda active | Passed |
| **Phase 4: DAST** | **OWASP ZAP Live ALB Scan (`v2.17.0`)** | 0 High, 2 Medium (HTTP-only `10106`, missing CSP `10038`), 6 Low (`500` on `404` routes, `Werkzeug` banner, missing headers) | **0 High, 0 Medium, 0 Low**; ACM TLS 1.3/1.2 (`:443`), HTTP `301` redirect, Gunicorn + `Server: SentinelPay`, and full security headers verified | Passed |

### Visual Evidence Gallery

#### Phase 1 Proof: JWT `alg: none` Blocked (`V-APP-02`), IDOR Blocked (`V-APP-03`), Deserialization Blocked (`V-APP-10`) & Audit Logging (`V-APP-11`)
![Broken JWT Exploit Before](./assets/images/broken%20jwt%20exploit.png)
![JWT Fixed After](./assets/images/jwt%20fixed.png)
![IDOR Exploit Before](./assets/images/IDOR%20exploit.png)
![IDOR Remediated After](./assets/images/IDOR%20remediated.png)
![Insecure Deserialization Remediated After](./assets/images/insecure%20deserialization%20remediated.png)
![Audit Log Check After](./assets/images/audit%20log%20check.png)
*Figure 1: Empirical before-and-after verification confirming rejection of forged `alg: none` JWTs (`401 UNAUTHORIZED`), enforcement of cross-account IDOR ownership checks (`404 NOT FOUND`), blocking of untrusted `pickle` session blobs (`401 UNAUTHORIZED`), and structured `sentinelpay.audit` JSON logging.*

#### Phase 2, 3 & 4 Proof: Terraform State Bootstrap, ECR Container Promotion & Live DAST HTTPS Header Verification
![Bootstrap Apply Success](./assets/images/bootstrap%20apply.png)
![Container Push to AWS ECR](./assets/images/container%20push%20to%20aws.png)
![Content Header Check](./assets/images/content%20header%20check.png)
*Figure 2: Provisioning the encrypted S3/DynamoDB remote state backend, pushing hardened Alpine microservice images to Amazon ECR (`eu-west-1`), and verifying live HTTPS TLS termination, Gunicorn execution, defensive browser headers, and clean `404` JSON responses on the AWS ALB.*

---

## 7. Key Challenges & Trade-Offs

* **Phase 1 Challenge — Zero-Downtime Password Hashing Migration & Secret Baselines:** Upgrading `users.password_hash` from unsalted MD5 to `Argon2id` risked locking out existing merchants, while historical training secrets and Terraform honeytoken references triggered Gitleaks. We built a transparent login-time MD5-to-Argon2id re-hashing flow and baselined historical/honeytoken fingerprints in `gitleaks-baseline.json` so CI blocks only net-new leaks.
* **Phase 2 Challenge — GitHub OIDC Subject Mismatches, Conftest Working Directory & Immutable ECR Tags:** Initial OIDC role assumption failed after 12 retries due to a customized GitHub repository subject format, `policy-checks.yml` failed with `No configuration files` when run from `infra/`, and workflow re-runs collided with immutable ECR commit tags. We aligned the IAM trust policy in `modules/github-oidc` to allow both `main` and `pull_request` subjects, pointed Conftest at `infra/environments/dev` with `--all-namespaces` and OIDC backend auth, and resolved `@sha256` digests for Cosign signing while keeping ECR tag immutability intact.
* **Phase 3 Challenge — AWS Sandbox Quotas & Checkov/tfsec Hardening:** Setting `reserved_concurrent_executions = 5` on the rotation Lambda triggered AWS account minimum-unreserved-capacity errors, and KMS key policies initially restricted CloudWatch Logs encryption to `/ecs/*`. We tuned concurrency for sandbox limits, expanded regional log group KMS conditions, and remediated 11 Checkov/`tfsec` findings to achieve **207 passed `tfsec` checks with 0 failures**.
* **Phase 4 Challenge — ECS `503` Crash Loops, ALB `DuplicateListener` Conflicts & ZAP `500` Error Disclosures:** Initial requests to the public ALB returned `503` because ECS tasks lacked NAT Gateway `:443` egress and `env_vars` injection; switching port `80` from `http_forward` to `http` redirect caused a `DuplicateListener` conflict; and `@app.errorhandler(Exception)` caught Werkzeug `404` exceptions during ZAP scans. We opened `:443` egress, injected `env_vars`, sequenced listener replacement via `depends_on`, and registered `@app.errorhandler(HTTPException)` before `Exception`.

---

## 8. Future Enhancements

- [ ] **Complete Cycle 6 & 7 Ephemeral PR Environments and Timed Attack Simulations (MTTD/MTTR):** Spin up isolated per-PR staging environments for automated OWASP ZAP gating before teardown, and execute timed attack simulations (honeytoken credential leak, vulnerable dependency injection, and manual IaC drift) to benchmark Mean Time to Detect (MTTD) and Mean Time to Respond (MTTR).
- [ ] **Separate PR Validation & Main Deployment IAM Roles + Stricter Cosign Identity:** Split the GitHub OIDC role into a read/plan-only PR role and a main-branch deployment role, and pin Cosign verification to the exact GitHub workflow certificate identity in `verify_supply_chain.sh`.
- [ ] **Cross-Region S3 Replication & Centralized SARIF Reporting:** Enable S3 Cross-Region Replication (`CKV_AWS_144`) on CloudTrail and KYC buckets for production disaster recovery, and aggregate Gitleaks, SAST, SCA, IaC, and Conftest outputs into GitHub Security SARIF dashboards.

---

## Authors & Project Contributors

* **Chinaza Nnamani** — Lead Application Security Engineer (`AppSec`, Container Hardening & `OWASP ZAP DAST`)
* **Sunday Abiodun (Ben)** — Cloud Security & DevSecOps Engineer (`KMS`, `RDS`, `Redis`, `S3`, `Secrets Rotation`, `Detection` & `OIDC`)
* **Muhammad Asif Salaudeen (Mohammed)** — DevSecOps Engineer (`Reusable CI/CD Workflows`, `OPA/Conftest`, `Syft SBOM` & `Cosign Supply-Chain Security`)
* **Femi Agbi** — Cloud Engineer (`VPC Network`, `ECS Fargate`, `ALB`, `WAFv2` & `IAM`)
* **Tega** — Team Lead (`STRIDE Threat Modelling`, `PR Governance` & `Constraint Verification`)