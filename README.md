# CredPal DevOps Assessment

A production-ready DevOps pipeline for a Node.js web application, covering containerisation, CI/CD, infrastructure-as-code, zero-downtime deployment, and security.

---

## Table of Contents

1. [Architecture Overview](#architecture-overview)
2. [Running Locally](#running-locally)
3. [Running Tests](#running-tests)
4. [Docker](#docker)
5. [CI/CD Pipeline](#cicd-pipeline)
6. [Infrastructure (Terraform)](#infrastructure-terraform)
7. [Deployment](#deployment)
8. [Accessing the App](#accessing-the-app)
9. [Key Decisions](#key-decisions)

---

## Architecture Overview

```
Internet
   │
   ▼
Application Load Balancer  (HTTPS :443, HTTP :80 → redirect)
   │
   ▼
ECS Fargate Service  (private subnets, 2 tasks minimum)
   │
   ├── Node.js App  (port 3000, non-root user)
   │
   └── RDS PostgreSQL  (private subnet, encrypted at rest)
```

| Component | Technology |
|-----------|-----------|
| App runtime | Node.js 20 (Alpine) |
| Container orchestration | AWS ECS Fargate |
| Load balancer | AWS ALB |
| TLS/SSL | AWS ACM (auto-renewed) |
| Database | AWS RDS PostgreSQL 15 |
| Secrets | AWS Secrets Manager |
| IaC | Terraform ≥ 1.6 |
| CI/CD | GitHub Actions |
| Container registry | GitHub Container Registry (GHCR) |
| Logging | CloudWatch Logs |

---

## Running Locally

### Prerequisites

- Node.js 20+
- Docker & Docker Compose

### Option A – Node directly

```bash
cd app
cp .env.example .env        # edit values as needed
npm install
npm start
```

The app starts on **http://localhost:3000**.

### Option B – Docker Compose (recommended)

```bash
# Create a .env file in the project root
cp app/.env.example .env
# Set DB_PASSWORD in .env (any value for local dev)

docker compose up --build
```

Both the app and PostgreSQL will start. The app is available at **http://localhost:3000**.

---

## Running Tests

```bash
cd app
npm install
npm test
```

Jest runs all tests under `app/tests/` and outputs a coverage report to `app/coverage/`.

---

## Docker

### Build the production image manually

```bash
docker build --target production -t credpal-app:local .
```

### Run the image standalone

```bash
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

The pipeline lives in [.github/workflows/ci-cd.yml](.github/workflows/ci-cd.yml) and runs on every push or pull request to `main`.

### Jobs

| Job | Trigger | What it does |
|-----|---------|-------------|
| `test` | All events | Installs deps, runs Jest, uploads coverage |
| `build-and-push` | Push to `main` only | Builds multi-stage image, pushes to GHCR |
| `deploy-staging` | After successful build | Deploys to ECS staging (automatic) |
| `deploy-production` | After staging deploy | Deploys to ECS production (**requires manual approval**) |

### Required GitHub Secrets

| Secret | Description |
|--------|-------------|
| `AWS_ACCESS_KEY_ID` | IAM key with ECS/ECR permissions |
| `AWS_SECRET_ACCESS_KEY` | Corresponding secret |
| `AWS_REGION` | Target AWS region (e.g. `us-east-1`) |

### Manual Approval Gate

The `production` GitHub environment must be configured with **required reviewers**:

> **Settings → Environments → production → Required reviewers**

No push to production happens without an explicit approval.

---

## Infrastructure (Terraform)

All infrastructure is defined in the [`terraform/`](terraform/) directory.

### First-time setup

```bash
cd terraform
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars with your values

terraform init
terraform plan
terraform apply
```

> **Note:** The S3 backend bucket and DynamoDB lock table must exist before `terraform init`.
> Create them once with the AWS CLI:
> ```bash
> aws s3api create-bucket --bucket credpal-terraform-state --region us-east-1
> aws dynamodb create-table \
>   --table-name credpal-terraform-locks \
>   --attribute-definitions AttributeName=LockID,AttributeType=S \
>   --key-schema AttributeName=LockID,KeyType=HASH \
>   --billing-mode PAY_PER_REQUEST
> ```

### Resources provisioned

| Resource | Purpose |
|----------|---------|
| VPC + subnets | Isolated network (2 public, 2 private AZs) |
| Internet Gateway + NAT | Public ingress; private outbound |
| Security Groups | ALB, ECS tasks, and RDS with least-privilege rules |
| Application Load Balancer | HTTPS termination, HTTP→HTTPS redirect |
| ACM Certificate | Free TLS cert with DNS validation |
| ECS Cluster + Fargate Service | Containerised app, 2 tasks minimum |
| RDS PostgreSQL | Managed database in private subnet |
| Secrets Manager | Stores DB password; injected at container runtime |
| CloudWatch Logs | Centralised log storage (30-day retention) |

---

## Deployment

### Rolling deployment (zero downtime)

ECS is configured with:

- `deployment_minimum_healthy_percent = 100` – existing tasks stay alive until new ones pass health checks
- `deployment_maximum_percent = 200` – allows twice the desired count during a rollout
- **Deployment circuit breaker + automatic rollback** – failed deployments automatically revert

### Blue/Green alternative

For stricter zero-downtime guarantees, the ECS service can be migrated to use **AWS CodeDeploy** (blue/green). The current rolling strategy is simpler and sufficient for most workloads.

### Manual production approval

The GitHub Actions `deploy-production` job is gated by the `production` environment's required reviewer configuration. A reviewer must approve the workflow run before the deployment proceeds.

---

## Accessing the App

| Endpoint | Method | Description |
|----------|--------|-------------|
| `/health` | GET | Liveness probe – always responds if the process is running |
| `/status` | GET | Readiness probe – reports version, env, and DB connectivity |
| `/process` | POST | Accepts JSON body, echoes it back with metadata |

**Locally:** `http://localhost:3000`
**Production:** `https://<your-domain-name>` (set via `var.domain_name`)

Example requests:

```bash
# Health
curl http://localhost:3000/health

# Status
curl http://localhost:3000/status

# Process
curl -X POST http://localhost:3000/process \
  -H "Content-Type: application/json" \
  -d '{"user": "alice", "amount": 5000}'
```

---

## Key Decisions

### Security

| Decision | Rationale |
|----------|-----------|
| Non-root container user (UID 1001) | Limits blast radius of container compromise |
| Multi-stage Dockerfile | Production image contains no dev tools or test code |
| `dumb-init` as PID 1 | Correct signal forwarding; prevents zombie processes |
| Secrets Manager for DB password | Never stored in code, env files, or GitHub secrets |
| ALB terminates TLS | ACM certificates auto-renew; no manual cert management |
| ECS tasks in private subnets | Not directly reachable from the internet |
| Security groups with least privilege | RDS only accepts connections from ECS; ECS only from ALB |
| `helmet` middleware | Sets secure HTTP headers (X-Frame-Options, CSP, etc.) |

### CI/CD

| Decision | Rationale |
|----------|-----------|
| Tests must pass before image is built | Prevents broken images from ever reaching a registry |
| Image tagged with Git SHA | Every image is traceable to an exact commit |
| GitHub Actions cache for Docker layers | Faster builds without re-downloading unchanged layers |
| Staging → Production promotion | No code reaches production without passing a staging environment first |
| Manual approval gate | Explicit human sign-off required before production changes |
| ECS circuit breaker + rollback | Automated safety net for bad deployments |

### Infrastructure

| Decision | Rationale |
|----------|-----------|
| AWS ECS Fargate | No EC2 instance management; automatic scaling |
| RDS managed PostgreSQL | Automated backups, minor version updates, and Multi-AZ option |
| S3 + DynamoDB remote state | Shared, locked state prevents concurrent Terraform apply conflicts |
| `ignore_changes = [task_definition]` | Lets CI/CD own the running image tag without Terraform interference |
| `deregistration_delay = 30s` on target group | Gives in-flight requests time to complete during rolling updates |
