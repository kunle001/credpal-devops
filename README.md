# CredPal DevOps Assessment

DevOps pipeline for a Node.js web application — containerisation, CI/CD, infrastructure-as-code, zero-downtime deployment, security, and observability.

---

## Table of Contents

1. [Architecture Overview](#architecture-overview)
2. [Project Structure](#project-structure)
3. [Running Locally](#running-locally)
4. [Running Tests](#running-tests)
5. [Docker](#docker)
6. [CI/CD Pipeline](#cicd-pipeline)
7. [Infrastructure (Terraform)](#infrastructure-terraform)
8. [Deployment](#deployment)
9. [Accessing the App](#accessing-the-app)
10. [Key Decisions](#key-decisions)

---

## Architecture Overview

```
Internet
   │
   ▼
AWS WAF  (OWASP rules + rate limiting)
   │
   ▼
Application Load Balancer  (HTTPS :443 · HTTP :80 → redirect)
   │
   ▼
ECS Fargate Service  ×2 tasks min  (private subnets)
   │  Auto-scales on CPU 70% / Memory 80%
   ├── Node.js App  (port 3000 · non-root UID 1001)
   │
   └── RDS PostgreSQL 15  (private subnet · encrypted · Multi-AZ in prod)
```

| Component | Technology |
|-----------|-----------|
| Runtime | Node.js 20 Alpine |
| Container orchestration | AWS ECS Fargate |
| Load balancer | AWS ALB |
| TLS/SSL | AWS ACM (auto-renewed) |
| WAF | AWS WAFv2 – managed rule groups |
| Database | AWS RDS PostgreSQL 15 |
| Secrets | AWS Secrets Manager |
| IaC | Terraform ≥ 1.6 – modular |
| CI/CD | GitHub Actions (9 jobs) |
| Registry | GitHub Container Registry (GHCR) |
| Logging | CloudWatch Logs |
| Alerting | CloudWatch Alarms → SNS → Email |

---

## Project Structure

```
credpal-devops/
├── app/
│   ├── src/
│   │   ├── index.js          # Express app entry point
│   │   ├── db.js             # Singleton pg connection pool
│   │   └── routes/
│   │       ├── health.js     # GET /health
│   │       ├── status.js     # GET /status
│   │       └── process.js    # POST /process
│   └── tests/
│       └── app.test.js
├── .github/workflows/
│   └── ci-cd.yml             # 9-job pipeline
├── terraform/
│   ├── modules/
│   │   ├── vpc/              # VPC, subnets, IGW, NAT
│   │   ├── security-groups/  # ALB, ECS, RDS security groups
│   │   ├── alb/              # ALB, ACM, WAF, Route 53 records
│   │   ├── rds/              # RDS PostgreSQL
│   │   └── ecs/              # ECS cluster+service, IAM, Secrets Manager,
│   │                         # autoscaling, CloudWatch alarms, SNS
│   ├── environments/
│   │   ├── staging/          # Calls all modules – staging sizes
│   │   └── production/       # Calls all modules – production sizes + HA
│   └── scripts/
│       └── bootstrap.sh      # One-time S3+DynamoDB state backend setup
├── Dockerfile                # Multi-stage (deps → test → production)
├── .pre-commit-config.yaml   # terraform fmt auto-format on commit
├── docker-compose.yml        # App + PostgreSQL for local dev
└── .env.example
```

---

## Running Locally

### Prerequisites

- Node.js 20+
- Docker & Docker Compose

### Option A – Node directly

```bash
cd app
cp .env.example .env   # edit if needed
npm install
npm start
```

App starts on **http://localhost:3000**.

### Option B – Docker Compose (recommended, mirrors production)

```bash
# Copy root .env.example to .env (docker-compose reads from project root)
cp .env.example .env

docker compose up --build
```

App + PostgreSQL start. Visit **http://localhost:3000**.

---

## Running Tests

```bash
cd app && npm install && npm test
```

Jest runs all tests under `app/tests/` with coverage written to `app/coverage/`.

---

## Docker

### Multi-stage build stages

| Stage | Purpose | Shipped? |
|-------|---------|---------|
| `deps` | Installs production deps only (`npm ci --omit=dev`) | No |
| `test` | Runs Jest (CI validation) | No |
| `production` | Lean runtime image — non-root user, npm/corepack removed, all OS packages upgraded | **Yes** |

> **Security hardening in the production stage:**
> - `apk upgrade --no-cache` — patches all Alpine OS packages to their latest versions, clearing fixable CVEs
> - `npm` and `corepack` are deleted — the container only runs `node src/index.js` and does not need a package manager at runtime; this also eliminates npm's bundled dependencies from vulnerability scans

```bash
# Build production image
docker build --target production -t credpal-app:local .

# Run it
docker run -p 3000:3000 \
  -e NODE_ENV=production \
  -e DB_HOST=<host> \
  -e DB_NAME=credpal_db \
  -e DB_USER=credpal_user \
  -e DB_PASSWORD=<password> \
  credpal-app:local
```

---

## CI/CD Pipeline

Pipeline: [.github/workflows/ci-cd.yml](.github/workflows/ci-cd.yml)

### Flow

```
PR  ──►  lint-and-test
     ──►  dockerfile-lint
     ──►  terraform-validate ──► terraform-plan (posts plan as PR comment)

main ──►  lint-and-test
      ──►  dockerfile-lint
      ──►  terraform-validate
      ──►  build-and-push  (Trivy scan table → SARIF → fail on CRITICAL/HIGH fixable CVEs before push)
      ──►  deploy-staging  (rolling ECS update + smoke test)
      ──►  terraform-apply-staging
      ──►  deploy-production  ◄── MANUAL APPROVAL GATE
      ──►  terraform-apply-production
```

### GitHub Variables required

All values are non-sensitive — set under **Settings → Secrets and variables → Actions → Variables tab**.

| Name | Description | Where to get it |
|------|-------------|-----------------|
| `AWS_REGION` | AWS region | `us-east-1` |
| `AWS_STAGING_DEPLOY_ROLE_ARN` | IAM role ARN for staging OIDC | `terraform output github_actions_role_arn` (staging) |
| `AWS_PROD_DEPLOY_ROLE_ARN` | IAM role ARN for production OIDC | `terraform output github_actions_role_arn` (production) |
| `STAGING_PIPELINE_SECRET` | AWS Secrets Manager secret name | `terraform output pipeline_secret_name` (staging) |
| `PROD_PIPELINE_SECRET` | AWS Secrets Manager secret name | `terraform output pipeline_secret_name` (production) |
| `STAGING_DOMAIN` | Staging hostname | e.g. `staging-api.yourdomain.com` |
| `PROD_DOMAIN` | Production hostname | e.g. `api.yourdomain.com` |
| `ALARM_EMAIL` | Alert notification email | your email |

> **Zero GitHub Secrets** — no long-lived AWS keys or DB passwords stored in GitHub. Authentication uses OIDC short-lived tokens; DB credentials are fetched at runtime from AWS Secrets Manager. The IAM roles and pipeline secrets are created by Terraform.

> **ECS task definition** — the pipeline fetches the current task definition directly from ECS (`aws ecs describe-task-definition`) and updates only the image tag. Terraform is the source of truth for all other task definition fields (roles, env vars, health checks, log config).

### Manual Approval Gate

Configure in **GitHub → Settings → Environments → production → Required reviewers**.

---

## Infrastructure (Terraform)

### First-time setup

```bash
# 1. Create S3 state bucket, DynamoDB lock table, and GitHub OIDC provider
#    (all three are account-scoped and created once — safe to re-run)
chmod +x terraform/scripts/bootstrap.sh
BUCKET_NAME=credpal-terraform-state-$(aws sts get-caller-identity --query Account --output text) \
  AWS_REGION=us-east-1 \
  ./terraform/scripts/bootstrap.sh

# Update backend.tf files with your actual bucket name before continuing
# sed -i '' "s/credpal-terraform-state/credpal-terraform-state-ACCOUNT_ID/g" \
#   terraform/environments/staging/backend.tf \
#   terraform/environments/production/backend.tf

# 2. Create GHCR pull credentials in Secrets Manager
#    Generate a GitHub PAT at: Settings → Developer settings → Personal access tokens
#    Scope required: read:packages only
aws secretsmanager create-secret \
  --name "credpal/ghcr-pull-credentials" \
  --secret-string '{"username":"<GITHUB_USERNAME>","password":"<GITHUB_PAT>"}' \
  --region us-east-1

# 3. Deploy staging
cd terraform/environments/staging
cp terraform.tfvars.example terraform.tfvars  # fill in your values
terraform init
terraform apply

# 4. Deploy production (OIDC provider already exists from bootstrap — no conflict)
cd ../production
cp terraform.tfvars.example terraform.tfvars
terraform init
terraform apply
```

### Modules

| Module | Resources |
|--------|-----------|
| `vpc` | VPC, 2 public + 2 private subnets, IGW, NAT, route tables |
| `security-groups` | ALB SG, ECS SG, RDS SG (least-privilege) |
| `alb` | ALB, target group, HTTPS listener, HTTP→HTTPS redirect, ACM cert, WAF |
| `rds` | RDS PostgreSQL 15, subnet group |
| `ecs` | ECS cluster, task definition, rolling service, IAM roles, Secrets Manager, auto-scaling, CloudWatch alarms, SNS topic |

### Staging vs Production differences

| Setting | Staging | Production |
|---------|---------|-----------|
| ECS tasks | 1 (min 1, max 3) | 2 (min 2, max 10) |
| Fargate CPU/memory | 256 / 512 | 512 / 1024 |
| RDS class | db.t3.micro | db.t3.small |
| RDS Multi-AZ | No | **Yes** |
| RDS backup retention | 1 day | 7 days |
| Deletion protection | No | **Yes** |
| WAF | Disabled | **Enabled** |

---

## Deployment

### Zero-downtime rolling strategy

ECS service configuration:

```
deployment_minimum_healthy_percent = 100   # never drop below desired capacity
deployment_maximum_percent         = 200   # spin up double during rollout
deregistration_delay               = 30s   # drain in-flight requests
deployment_circuit_breaker                 # auto-rollback on failure
```

### Auto-scaling

| Policy | Trigger | Action |
|--------|---------|--------|
| CPU | > 70% average | Scale out (60s cooldown out, 300s in) |
| Memory | > 80% average | Scale out |

### Manual approval for production

The `deploy-production` job references the `production` GitHub environment. Until a configured reviewer approves the workflow run, the job is blocked.

---

## Accessing the App

| Endpoint | Method | Description |
|----------|--------|-------------|
| `/health` | GET | Liveness probe |
| `/status` | GET | Readiness probe + DB connectivity |
| `/process` | POST | Accepts JSON, echoes with metadata |

```bash
# Health
curl https://api.yourdomain.com/health

# Status
curl https://api.yourdomain.com/status

# Process
curl -X POST https://api.yourdomain.com/process \
  -H "Content-Type: application/json" \
  -d '{"user": "alice", "amount": 5000}'
```

---

## Key Decisions

### Security

| Decision | Rationale |
|----------|-----------|
| OIDC instead of static AWS keys | No long-lived credentials stored in GitHub; each workflow run gets a short-lived token |
| Production OIDC condition: `ref:refs/heads/main` | Only merges to main can deploy to production |
| Non-root container user (UID 1001) | Limits blast radius of a container compromise |
| Multi-stage Dockerfile | Production image has no dev tooling or test code |
| npm/corepack removed from production image | Package manager not needed at runtime; eliminates its bundled deps (minimatch, tar) from Trivy scan surface |
| `apk upgrade --no-cache` in production stage | Patches all Alpine OS packages to latest, clearing fixable CVEs reported by Trivy |
| `dumb-init` as PID 1 | Correct signal forwarding, no zombie processes |
| DB password in Secrets Manager | Injected at container runtime — never in code, Git, or env files |
| GHCR pull credentials in Secrets Manager | GitHub PAT (read:packages only) stored in AWS Secrets Manager; ECS execution role reads it via `repositoryCredentials` — no credentials in task definition or source code |
| ACM + ALB for TLS | Certs auto-renew; no manual cert management |
| ECS tasks in private subnets | Not directly reachable from the internet |
| WAF (production) | OWASP common rules + known-bad-inputs + IP rate limiting (1 000 req/5 min) |
| `helmet` middleware | Secure HTTP headers on every response |

### CI/CD

| Decision | Rationale |
|----------|-----------|
| Trivy scan before push | Two-step scan: table format prints CVE names to the Actions log for visibility; SARIF format enforces the gate and uploads results to the GitHub Security tab. Image is only pushed after a clean scan |
| `npm audit --audit-level=high` | Catches known vulnerable dependencies before any build |
| Hadolint | Catches Dockerfile anti-patterns early |
| `terraform fmt -check` + `validate` on every PR | IaC changes are linted before merge |
| `.pre-commit-config.yaml` + local git hook | Automatically runs `terraform fmt -recursive` before every commit, preventing fmt check failures in CI |
| `terraform plan` posted as PR comment | Reviewers see exact infrastructure changes before approving |
| SHA-tagged images | Every image is traceable to an exact commit |
| Smoke test after staging deploy | Catches broken deployments before they reach production |
| Circuit breaker + auto-rollback | Failed deployments revert automatically without manual intervention |

### Infrastructure

| Decision | Rationale |
|----------|-----------|
| Terraform modules | Reusable, independently testable; staging and production share the same code with different inputs |
| Separate state files per environment | A broken production state cannot affect staging |
| `ignore_changes = [task_definition]` | CI/CD owns the running image tag; Terraform owns everything else |
| RDS Multi-AZ (production only) | Automatic failover; staging doesn't need the cost |
| Auto-scaling target tracking | Simpler and more reliable than step scaling; scales both out and in automatically |
| CloudWatch Alarms → SNS → Email | Operational visibility: CPU high, memory high, 5xx errors, unhealthy host count |
| S3 state with versioning + encryption | Recover from accidental state corruption; state at rest is encrypted |
| DynamoDB state locking | Prevents concurrent `terraform apply` races |

