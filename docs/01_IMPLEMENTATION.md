# Implementation Log

A phase-by-phase record of what was built, decisions made, and issues encountered during the live deployment.

---

## Phase 1: Core Infrastructure ✅ COMPLETED
**Date**: 2026-02-16  
**Duration**: ~5 minutes (including ACM validation)  
**Cost**: $0 (free tier resources only)

### What Was Built

#### Networking
- **VPC**: `10.0.0.0/16` (`vpc-0d2a268b450bd99b0`)
- **Public Subnets**:
  - `10.0.0.0/24` — us-east-1a (`subnet-0cb9b9135533a98e8`)
  - `10.0.1.0/24` — us-east-1b (`subnet-0f03d9302f0d6471e`)
- **Private Subnets**:
  - `10.0.10.0/24` — us-east-1a (`subnet-00c0c46774db560b2`)
  - `10.0.11.0/24` — us-east-1b (`subnet-0762d5bcc2722cf27`)
- **Internet Gateway**: `igw-0418a46a2cd409aae`
- Public subnets route `0.0.0.0/0` via IGW; private subnets have no internet route

#### Security Groups
| Group | ID | Inbound | Purpose |
|---|---|---|---|
| ALB | `sg-0373513dd33d30ddb` | 443, 80 from internet | Public entry point |
| ECS Tasks | `sg-09a3082e31d282821` | 8000 from ALB SG only | Container isolation |
| RDS | `sg-07a5aae1f94e3e9e2` | 5432 from ECS SG only | Database isolation |

#### IAM Roles
- **Task Execution Role** (`ecs-prod-ecs-exec-*`): Pull images from ECR, write CloudWatch logs, read SSM
- **Task Role** (`ecs-prod-ecs-task-*`): Read `/ecs-prod/*` SSM parameters only

#### TLS Certificate
- **Domains**: `cipherpol.xyz`, `*.cipherpol.xyz`
- **Validation**: DNS via Route 53 (resolved in ~2 seconds with hosted zone in same account)
- **ARN**: `arn:aws:acm:us-east-1:758620460011:certificate/3a9c9807-389b-46ba-aca0-35733af32651`

### Issues Encountered

**Terraform deprecated `dynamodb_table` warning** (non-blocking):
```
Warning: The parameter "dynamodb_table" is deprecated. Use "use_lockfile" instead.
```
State locking works correctly. The warning is from Terraform 1.14 deprecating the parameter name. No action required during the build.

### Key Decisions
1. **`/24` subnets** — 256 IPs each, well within limits for this scale
2. **Public subnets start at `.0`, private at `.10`** — clear CIDR separation by design
3. **`create_before_destroy` on security groups** — avoids dependency deadlock during updates

### Evidence
- `docs/evidence/01-vpc.json` — VPC details
- `docs/evidence/02-subnets.json` — Subnet list
- `docs/evidence/04-security-groups.json` — Security group rules
- `docs/evidence/05-iam-execution-role.json` — Execution role policy
- Screenshots: see `docs/evidence/screenshots/`

---

## Phase 2: Application Deployment (ECS + ALB) ✅ COMPLETED
**Date**: 2026-02-16  
**Duration**: ~4 minutes (ALB provisioning dominates)  
**Cost**: $0.0225/hour (ALB billing started)

### What Was Built

#### Application Load Balancer
- **Name**: `ecs-prod-alb`
- **DNS**: `ecs-prod-alb-641417416.us-east-1.elb.amazonaws.com`
- **Scheme**: Internet-facing
- **Listeners**:
  - HTTPS (443) → weighted forward to blue/green target groups
  - HTTP (80) → redirect to HTTPS
- **Certificate**: ACM wildcard for `*.cipherpol.xyz`

#### Target Groups (Blue-Green Foundation)
- **Blue**: `ecs-prod-blue` — active (listeners forward here by default)
- **Green**: `ecs-prod-green` — standby (0 weight until switch)
- **Health Check**: `GET /health`, 30s interval, 2 successes = healthy

#### ECS Cluster & Service
- **Cluster**: `ecs-prod-cluster`
- **Service**: `ecs-prod-service` (desired: 2)
- **Task Definition**: `ecs-prod-flask-app:1`
  - CPU: 256 units (0.25 vCPU)
  - Memory: 512 MB
  - Port: 8000
  - Log group: `/ecs/ecs-prod/flask-app`
- **Image**: `758620460011.dkr.ecr.us-east-1.amazonaws.com/ecs-prod/flask-app:latest`

#### DNS
- **Record**: `app.cipherpol.xyz` → A alias to ALB
- **TTL**: Propagation instant (Route 53 hosted zone)

### Deployment Timing
| Step | Duration |
|---|---|
| ALB provisioning | 2m 55s |
| ECS service creation | 5s |
| Tasks reaching healthy | ~60s |
| Route53 A record | 39s |
| **Total** | **~4m** |

### Issues Encountered

**DB endpoints return 503** — expected and correct. No RDS exists yet. `/db-check` and `/items` return 503 until Phase 3.

### Key Decisions
1. **ALB always takes ~3 minutes** — no way to speed this up; Terraform handles `depends_on` correctly
2. **Health check grace period = 60s** — prevents premature task failure before app starts

### Evidence
- `docs/evidence/11-alb.json` — ALB details
- `docs/evidence/12-alb-listeners.json` — Listener configuration
- `docs/evidence/13-blue-tg-health.json`, `14-green-tg-health.json` — Target group health

---

## Phase 3: Database Integration (RDS + Secrets) ✅ COMPLETED
**Date**: 2026-02-19  
**Duration**: ~11 minutes (RDS provisioning dominates)  
**Cost**: $0 (RDS free tier: 750 hrs/month)

### What Was Built

#### RDS PostgreSQL Instance
- **Identifier**: `ecs-prod-db-cd31bf39`
- **Engine**: PostgreSQL **15.12** (see issue below)
- **Instance Class**: `db.t3.micro`
- **Storage**: 20 GB gp3
- **Deployment**: Single-AZ (free tier)
- **Network**: Private subnets only, no public access

#### Secrets Management
- **Parameter name**: `/ecs-prod/db/password` (SecureString, KMS-encrypted)
- **Access**: Task execution role reads at container startup
- **Never hardcoded** — sourced via `aws ssm get-parameter --with-decryption` during Terraform run

#### ECS Task Update
- **Revision**: `ecs-prod-flask-app:2`
- Environment variables injected: `DB_HOST`, `DB_NAME`, `DB_USER`
- Schema auto-created on first connection by `models.py`

### Issues Encountered

**1. PostgreSQL 15.4 no longer exists in AWS**
```
Error: Cannot find version 15.4 for postgres
```
`engine_version = "15.4"` was retired by AWS. Changed to `"15.12"` and re-applied. See `docs/02_LESSONS_LEARNED.md` for full details.

**2. `Module not installed` — forgot `terraform init` after adding RDS module**
```
Error: Module not installed
  on main.tf line 118: module "rds" {}
```
Added `rds` module block to `main.tf` without re-running `terraform init`. Ran `init`, then `plan` and `apply` succeeded.

**3. Git Bash path conversion broke SSM parameter fetch**
```bash
aws ssm get-parameter --name /ecs-prod/db/password
# ParameterNotFound — Git Bash converted the path to a Windows file path
```
Fixed with `export MSYS_NO_PATHCONV=1`. See `docs/02_LESSONS_LEARNED.md`.

### Test Results

| Endpoint | Result |
|---|---|
| `GET /db-check` | `{"status":"connected","database":"postgresql"}` ✅ |
| `GET /items` | `{"count":0,"items":[]}` ✅ |
| `POST /items` | Item created with ID and timestamp ✅ |

### Key Decisions
1. **Single-AZ RDS** — free tier-eligible; acknowledged production deviation
2. **SSM Parameter Store** over Secrets Manager — sufficient for this scope, free tier
3. **App-managed schema** — `models.py` creates the `items` table on startup

### Evidence
- `docs/evidence/15-rds-instance.json` — RDS instance details
- `docs/evidence/18-app-dbcheck-response.json` — Live DB connectivity proof

---

## Phase 4: CI/CD Pipeline ⏳ PENDING
**Status**: Code not yet written  
**Planned**: GitHub Actions workflow with OIDC (no long-lived IAM keys)

Planned pipeline:
1. Push to `main` → trigger workflow
2. Build Docker image
3. Push to ECR with commit SHA tag
4. Update ECS task definition
5. `--force-new-deployment` to rolling update blue service

See `.github/workflows/deploy.yml` (to be created).

---

## Phase 5: Blue-Green Deployment Testing ✅ COMPLETED
**Date**: 2026-02-19  
**Duration**: ~1.5 hours (including debugging)  
**Cost**: $0 (no new billable resources)

### What Was Tested

- Second ECS service (`ecs-prod-service-green`) using green target group
- ALB listener weighted forward: blue=100 / green=0 (default) → blue=0 / green=100 (switch) → rollback → final green
- Data persistence across deployment slots (same RDS)
- Evidence collection script (`scripts/test-blue-green.sh`)

### Final Verified Behaviour

| Test | Result |
|---|---|
| Traffic switch (blue → green) | Instant (<1s) ✅ |
| Health check: green healthy | ✅ |
| Write item on green | ID 5 created ✅ |
| Item count after write | 5 ✅ |
| Rollback to blue | Instant, count still 5 ✅ |
| Final switch to green | ✅ |
| Scale blue to 0 | `desiredCount:0` ✅ |

### Issues Encountered

**1. 106 failed tasks — container healthcheck crash loop**

After deploying the green service, `failedTasks` climbed to 106. Root cause: the Dockerfile `HEALTHCHECK` runs `python -c "import requests; ..."` but `requests` was not in `requirements.txt`. The container health check failed on every task while the ALB health check (external HTTP) still passed. ECS kept replacing tasks it considered unhealthy.

Fix: Added `requests==2.31.0` to `requirements.txt`, rebuilt both `latest` and `green` image tags, pushed, force-new-deployed both services.

**2. `modify-listener` simple syntax rejected**

After previously configuring the listener with weighted `ForwardConfig`, the simple CLI syntax fails:
```bash
--default-actions Type=forward,TargetGroupArn=$GREEN_TG   # rejected
```
Must use full JSON with `ForwardConfig` on all subsequent updates.

**3. `terraform output -raw alb_listener_arn` — output not wired up**

ALB module exposes `listener_arn` internally but it was not re-exported in `terraform/environments/prod/outputs.tf`. Scripts use hardcoded ARNs as a result.

**4. alternating v1/v2 responses before force-new-deploy settled**

During rolling redeployment, curl alternated between old (v1.0.0, no `deployment` field) and new (v2.0.0, `deployment=green`) responses. This is the ALB load-balancing between old and new tasks during the rolling update — expected, not a bug.

### Notes on "Blue vs Green" Distinction
Both the blue and green services ultimately ran the same image (`v2.0.0`) because the fix rebuild was pushed to both `:latest` and `:green` tags. The demonstrated value is the **ALB routing mechanism** — instant listener-level switching, not the code difference between slots.

### Evidence (all in `docs/evidence/phase5/`)
| File | Content |
|---|---|
| `01-blue-health.json` | Blue service state before switch |
| `02-green-health.json` | Green health after switch |
| `03-items-green.json` | Item count on green (4 at switch time) |
| `04-green-write.json` | Item created on green (ID 5) |
| `05-items-after-write.json` | Count=5 confirmed |
| `06-blue-after-rollback.json` | Health response after rollback |
| `07-items-after-rollback.json` | Count still 5 after rollback |
| `08/09-*-tg-health.json` | Target group health states |
| `10-listener-final.json` | Final listener config (green=100%) |
| `11-services-status.json` | Full service describe output |

---

## Project Summary

| Phase | Status | Key Resources | Billable? |
|---|---|---|---|
| Phase 1: VPC + IAM + TLS | ✅ Complete | VPC, 4 subnets, 3 SGs, 2 IAM roles, ACM cert | No |
| Phase 2: ALB + ECS | ✅ Complete | ALB, 2 target groups, ECS cluster + service, ECR | Yes — ALB |
| Phase 3: RDS + Secrets | ✅ Complete | RDS PostgreSQL, SSM parameter, task def v2 | No (free tier) |
| Phase 4: CI/CD | ⏳ Pending | GitHub Actions workflow | No |
| Phase 5: Blue-Green | ✅ Complete | Green service, green task def, listener switch | No |

**Total infrastructure resources deployed**: ~37  
**Total estimated AWS cost**: ~$0.50 (ALB ~6 hrs × $0.0225 + misc)  
**Live endpoint**: `https://app.cipherpol.xyz` (while infrastructure is running)