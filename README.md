# SentinelPay — Securing an Inherited Fintech Platform (Team Capstone, In Progress)

> 🚧 **Status: Cycle 5 of 7.** Application security remediation is complete. Cloud infrastructure, detection, and CI/CD pipeline hardening are actively in progress. This README will be updated as the remaining cycles land.

**Scenario:** SentinelPay Technologies Ltd, a fictional Nigerian-founded pan-African fintech processing card and bank-transfer payments for roughly 1,400 merchants across Nigeria, Ghana, Kenya, and Rwanda. After two years of fast feature delivery with zero dedicated security investment, an external researcher disclosed an IDOR vulnerability in production. We're the security engineering team brought in to fix it, and everything that came with it.
**Team:** Five people, each owning a distinct track.
**Stack:** Flask (payments API, KYC API), Terraform, AWS (ECS Fargate, RDS, S3, GuardDuty, Security Hub), GitHub Actions, OPA, Gitleaks, Semgrep, Bandit, Trivy, Cosign

## Team structure

| Role | Owner | Track |
|---|---|---|
| Team Lead | Me | Threat modelling, PR review, constraint verification, attack-sim coordination |
| AppSec Engineer | Chinaza | Vulnerability scanning, manual code review, application fixes |
| Cloud Engineer — Network & Compute | Femi | VPC, ECS Fargate, ALB, WAF, IAM |
| Cloud Engineer — Data, Identity & Detection | Ben | KMS, RDS, Secrets Manager, GuardDuty, CloudTrail, Security Hub, honeytokens |
| DevSecOps Engineer | Mohammed | CI/CD pipeline, OIDC federation, policy-as-code, image signing |

## How the work is structured

The project runs across 7 cycles rather than a single build-then-ship pass. Each cycle produces specific artefacts (a threat register, remediation writeups, a constraint scorecard, a signed pipeline, an attack simulation report) rather than just code.

- **Cycle 1** — Full team threat model: a STRIDE pass against every trust boundary in the payments-api and kyc-api services, written up as a threat register (threat, category, boundary, likelihood, impact, status).
- **Cycle 2** — Critical application vulnerabilities fixed first: SQL injection, JWT verification (rejecting `alg: none`, moving to RS256), IDOR via explicit ownership checks, and a wallet-debit race condition fixed with row-level locking. Every fix is reviewed as a before/after exploit demo, not approved on "looks fine."
- **Cycle 3** — Remaining application hardening: password hashing moved to Argon2id, mass-assignment whitelisting, rate limiting on auth endpoints, verbose error handling turned off, insecure deserialisation replaced with signed JSON sessions, and structured audit logging added around every sensitive operation. **This closes out the AppSec track.**
- **Cycles 3–4 (cloud, ongoing)** — VPC and ECS Fargate standup, WAF attached to the ALB with managed and custom rate-limit rules, KMS-encrypted RDS and S3 with a security-group-reference-only ingress pattern, Secrets Manager with rotation, GuardDuty/CloudTrail/Security Hub/Config enabled, and a deliberately planted honeytoken wired to an EventBridge alarm.
- **Cycle 5 (current)** — Constraint verification against five defined planes (Edge, Application, Data, Identity & Secrets, Detection & Response), each checked against a live Terraform resource or AWS console screen, never taken on trust. Any unmet constraint gets either a fix ticket or a written, reviewed justification, never silence. In parallel: full CI/CD gate wiring, OPA policy-as-code enforcing the security baseline (no public S3, no open ingress outside the ALB, mandatory encryption at rest), Cosign image and SBOM signing, and a per-PR ephemeral staging environment scanned with OWASP ZAP before teardown.
- **Cycle 6 (upcoming)** — A full dry run of the entire path end to end: commit, every gate, deployment, and a live GuardDuty/CloudTrail event, with every failure logged as evidence.
- **Cycle 7 (upcoming)** — A timed attack simulation: leaked-credential detection, a dependency with a known CVE, and manual IaC drift, each measured for MTTD (mean time to detect) and MTTR (mean time to respond), written up with an executive summary.

## What's in this repository right now

- **`infra/`** — the Terraform build, in progress
- **`policy-tests/` and `policy/terraform/`** — OPA policy-as-code and their tests
- **`.gitleaks.toml`, `gitleaks-baseline.json`** — secret-scanning configuration and baseline
- **`.trivyignore`** — documented scanning exceptions
- **`.github/workflows/`** — the CI/CD pipeline, gates being wired incrementally cycle by cycle

## Tools

`Flask` `Terraform` `AWS` `GitHub Actions` `OPA` `Gitleaks` `Semgrep` `Bandit` `Trivy` `Cosign` `Syft`
