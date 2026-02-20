# ECS Production Platform

> **A production-grade container platform built on AWS ECS Fargate with blue-green deployments, RDS PostgreSQL, and full infrastructure-as-code via Terraform.**

This is a sprint-deployed portfolio project demonstrating real-world cloud engineering patterns: zero-downtime deployments, network isolation, secrets management, and cost-controlled infrastructure. Total AWS cost: **~$0.50** for a 4-hour live validation window.

---

## Architecture

```
Internet
    │
    ▼
Route 53 (app.cipherpol.xyz)
    │
    ▼
ACM Certificate (TLS 1.2/1.3)
    │
    ▼
Application Load Balancer (ecs-prod-alb)
    │   Port 80 → 443 redirect
    │   Port 443 → weighted forward
    │
    ├──── Blue Target Group (ecs-prod-blue)
    │         │
    │         ▼
    │     ECS Fargate Service (ecs-prod-service)
    │     2 tasks × Flask/Gunicorn on port 8000
    │
    └──── Green Target Group (ecs-prod-green)
              │
              ▼
          ECS Fargate Service (ecs-prod-service-green)
          Weight: 100% during green deployment

Both services connect to:
    │
    ▼
RDS PostgreSQL 15.12 (private subnet, port 5432)
DB credentials stored in SSM Parameter Store
```

**VPC Design:**
- `10.0.0.0/16` CIDR with 4 subnets across 2 AZs
- Public subnets: ECS tasks (ALB-filtered ingress), ALB
- Private subnets: RDS only (no internet route)
- Security groups enforce least-privilege isolation

---

## Technology Stack

| Layer | Technology | Notes |
|---|---|---|
| Infrastructure as Code | Terraform 1.14+ | Modular design, remote state in S3 |
| Container Platform | AWS ECS Fargate | Serverless containers, no EC2 management |
| Load Balancing | AWS ALB | Blue-green switching via target group weights |
| Database | RDS PostgreSQL 15.12 | Private subnet, SSM-managed credentials |
| TLS/DNS | ACM + Route 53 | Auto-renewing cert, A record alias |
| Container Registry | Amazon ECR | Tagged versioned images |
| Secrets | AWS SSM Parameter Store | SecureString, no hardcoded credentials |
| Monitoring | CloudWatch Logs | Log group per service |
| Application | Flask 3.0 + Gunicorn | Python WSGI app in multi-stage Docker image |

---

## Repository Structure

```
ecs-production-platform/
├── README.md                          ← You are here
├── app/
│   ├── Dockerfile                     ← Multi-stage build
│   ├── requirements.txt
│   └── src/
│       ├── app.py                     ← Flask API (health, items, db-check)
│       ├── models.py                  ← PostgreSQL connection + queries
│       └── config.py                  ← Environment-based config
├── .github/
│   └── workflows/
│       ├── deploy.yml                 ← Build image, push to ECR, deploy green
│       └── rollback.yml               ← Switch ALB to blue, scale green down
├── terraform/
│   ├── modules/
│   │   ├── networking/                ← VPC, subnets, IGW, route tables, SGs
│   │   ├── iam/                       ← ECS task execution + task roles
│   │   ├── alb/                       ← ALB, listeners, blue/green target groups
│   │   ├── ecs/                       ← Cluster, task definitions, services
│   │   ├── rds/                       ← PostgreSQL instance, subnet group
│   │   └── cicd/                      ← OIDC provider + GitHub Actions IAM role (reference)
│   └── environments/
│       └── prod/
│           ├── main.tf                ← Module composition
│           ├── variable.tf            ← Input variables
│           ├── outputs.tf             ← Resource IDs, ARNs, endpoints
│           ├── backend.tf             ← S3 + DynamoDB remote state
│           └── versions.tf            ← Provider pins
├── docs/
│   ├── ARCHITECTURE.md               ← Design decisions and trade-offs
│   ├── 01_IMPLEMENTATION.md          ← Phase-by-phase build log
│   ├── 02_LESSONS_LEARNED.md         ← Issues encountered and fixes
│   ├── 03_COST_ANALYSIS.md           ← AWS cost breakdown
│   ├── 04_SECURITY.md                ← IAM, network, secrets design
│   ├── 05_CICD_DESIGN.md             ← Pipeline design, OIDC auth, setup steps
│   ├── evidence/                     ← JSON captures from live deployment
│   └── runbooks/
│       ├── deployment-failure.md     ← Incident response
│       ├── database-connection.md    ← DB connectivity troubleshooting
│       └── rollback-procedure.md     ← Blue-green rollback steps
└── scripts/
    ├── capture-evidence.sh           ← Infrastructure state snapshot
    ├── test-blue-green.sh            ← Full blue-green switch + evidence
    ├── test-deployment.sh            ← Endpoint smoke tests
    └── verify-cleanup.sh             ← Post-destroy resource check
```

---

## Blue-Green Deployment

This platform implements zero-downtime blue-green deployments using **ALB weighted target groups** — no DNS TTL delays, no ECS deployment controllers, just an instant listener update.

### How It Works

```
Normal state:    Blue TG weight=100, Green TG weight=0
Deploy green:    Green TG weight=100, Blue TG weight=0   ← instant switch
Rollback:        Blue TG weight=100, Green TG weight=0   ← instant rollback
```

### Switch Traffic to Green
```bash
aws elbv2 modify-listener \
  --listener-arn <HTTPS_LISTENER_ARN> \
  --default-actions '[{"Type":"forward","ForwardConfig":{"TargetGroups":[
    {"TargetGroupArn":"<GREEN_TG_ARN>","Weight":100},
    {"TargetGroupArn":"<BLUE_TG_ARN>","Weight":0}
  ]}}]' \
  --region us-east-1
```

### Rollback (instant)
```bash
# Same command, weights reversed
```

See [`docs/runbooks/rollback-procedure.md`](docs/runbooks/rollback-procedure.md) for the full runbook.

---

## Deploying

> ⚠️ This is a **sprint-deploy** project. Deploy, validate, destroy. The infrastructure is not meant to run continuously due to ALB costs ($0.0225/hr).

### Prerequisites

- AWS CLI configured (`aws sts get-caller-identity`)
- Terraform >= 1.5
- Docker
- S3 backend: `cipherpol-terraform-state-758620460011`
- SSM parameter: `/ecs-prod/db/password` (SecureString)

### Deploy

```bash
cd terraform/environments/prod

# Set DB password from SSM
export MSYS_NO_PATHCONV=1   # Git Bash on Windows only
export TF_VAR_db_password=$(aws ssm get-parameter \
  --name /ecs-prod/db/password --with-decryption \
  --query Parameter.Value --output text)

terraform init
terraform plan -out=deploy.tfplan
terraform apply "deploy.tfplan"
```

### Build & Push App Image

```bash
cd app

aws ecr get-login-password --region us-east-1 | \
  docker login --username AWS --password-stdin \
  758620460011.dkr.ecr.us-east-1.amazonaws.com

docker build -t 758620460011.dkr.ecr.us-east-1.amazonaws.com/ecs-prod/flask-app:latest .
docker push 758620460011.dkr.ecr.us-east-1.amazonaws.com/ecs-prod/flask-app:latest

aws ecs update-service \
  --cluster ecs-prod-cluster \
  --service ecs-prod-service \
  --force-new-deployment \
  --region us-east-1
```

### Destroy (Clean Shutdown)

```bash
# Scale services to 0 first (avoids target group drain timeout)
aws ecs update-service --cluster ecs-prod-cluster --service ecs-prod-service --desired-count 0 --region us-east-1
aws ecs update-service --cluster ecs-prod-cluster --service ecs-prod-service-green --desired-count 0 --region us-east-1

sleep 60

cd terraform/environments/prod
terraform destroy

# Verify nothing remains
bash scripts/verify-cleanup.sh
```

---

## Application API

The Flask app exposes four endpoints:

| Endpoint | Method | Description |
|---|---|---|
| `GET /` | GET | Service info (version, deployment slot) |
| `GET /health` | GET | ALB health check target |
| `GET /db-check` | GET | PostgreSQL connectivity check |
| `GET /items` | GET | List all items |
| `POST /items` | POST | Create item `{"name": "..."}` |

---

## Key Design Decisions

### Public Subnets for ECS Tasks (vs. NAT Gateway)
ECS tasks run in public subnets with internet access. In production I'd use private subnets + NAT Gateway — but NAT costs $33/month, which exceeds the budget of a sprint deploy. Security groups enforce that only the ALB can reach container port 8000. RDS stays in private subnets in all cases.

### Single-AZ RDS
Free tier `db.t3.micro` with `Multi-AZ=false`. For production: `Multi-AZ=true` for automatic failover.

### Weighted Listener vs. CodeDeploy Blue-Green
ALB weighted target groups give instant, scriptable traffic control without CodeDeploy complexity. Trade-off: no automatic health-check-triggered rollback. That's mitigated by the ALB health check + ECS service replacement loop.

---

## CI/CD Pipeline (Designed, Not Live Tested)

Two GitHub Actions workflows are included in `.github/workflows/`:

| Workflow | Trigger | What It Does |
|---|---|---|
| `deploy.yml` | Push to `main` (app code changes) | Build image, push to ECR, deploy to green ECS service |
| `rollback.yml` | Manual (`workflow_dispatch`) | Switch ALB listener to blue, scale green to 0 |

Authentication uses **OIDC** (OpenID Connect) — GitHub requests short-lived AWS tokens per workflow run. No long-lived access keys stored in GitHub.

The OIDC provider and IAM deployment role are defined in `terraform/modules/cicd/` (reference only, not applied). To enable the workflows, create the IAM role and uncomment the `configure-aws-credentials` step in each workflow file.

See [`docs/05_CICD_DESIGN.md`](docs/05_CICD_DESIGN.md) for full setup instructions.

---

## Evidence

Live deployment evidence is captured in `docs/evidence/`:
- VPC, subnet, security group JSON
- ECS cluster, service, task definition snapshots
- ALB listener configuration (weighted forward)
- Target group health states
- Live API responses (`/health`, `/items`, `/db-check`)
- CloudWatch log sample
- Blue-green switch test results (11 files in `docs/evidence/phase5/`)

---

## Cost Analysis

See [`docs/03_COST_ANALYSIS.md`](docs/03_COST_ANALYSIS.md) for full breakdown.

**Summary for 4-hour validation window:**

| Service | Rate | 4h Cost |
|---|---|---|
| ALB | $0.0225/hr | $0.09 |
| ECS Fargate | ~$0.01/hr (0.25 vCPU, 0.5GB) | $0.04 |
| RDS db.t3.micro | Free tier | $0.00 |
| Route 53 | Prorated | ~$0.02 |
| Data transfer | Minimal | ~$0.01 |
| **Total** | | **~$0.16** |

---

## Author

**Suleiman** — Cloud Infrastructure Engineer  
[cipherpol.xyz](https://cipherpol.xyz)
