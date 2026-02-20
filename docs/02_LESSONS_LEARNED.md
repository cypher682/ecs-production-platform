# Lessons Learned — ECS Production Platform

Real issues encountered during the build, with root causes and fixes. This is the document that differentiates a project that was actually run from one that was only written.

---

## 1. Git Bash Path Conversion Broke AWS CLI

**Phase:** 3 (SSM Parameters)

**What happened:**
```bash
aws ssm get-parameter --name /ecs-prod/db/password
# Error: ParameterNotFound
```

The parameter existed. The error was Git Bash on Windows automatically converting Unix-style paths starting with `/` into Windows file paths. `/ecs-prod/db/password` became `C:/ecs-prod/db/password`.

**Fix:**
```bash
export MSYS_NO_PATHCONV=1
# Then re-run the command — it works immediately
```

**Lesson:** Always set `MSYS_NO_PATHCONV=1` when running AWS CLI commands with path-like values (SSM names, ARNs with slashes) in Git Bash on Windows. Add it to your shell profile.

---

## 2. PostgreSQL 15.4 No Longer Exists in AWS

**Phase:** 3 (RDS)

**What happened:**
```
Error: api error InvalidParameterCombination:
Cannot find version 15.4 for postgres
```

Terraform module was hardcoded to `engine_version = "15.4"`. AWS periodically retires old minor versions; 15.4 was removed.

**Fix:**
```hcl
# modules/rds/main.tf
engine_version = "15.12"   # was "15.4"
```

**Lesson:** Never pin to a specific minor version in Terraform. Use the latest minor version and check [AWS RDS release notes](https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/PostgreSQL.Concepts.General.DBVersions.html) before deploying.

---

## 3. `terraform init` Required After Adding New Module

**Phase:** 3 (RDS module added)

**What happened:**
```
Error: Module not installed
  on main.tf line 118: module "rds" {}
```

New module was added to `main.tf` but `terraform init` hadn't been re-run, so Terraform didn't know where to find the module code.

**Fix:** `terraform init` — always required when adding a new module, provider, or backend configuration.

**Lesson:** `terraform plan` will fail cleanly with this error and tell you to run `init`. This is expected behaviour, not a bug.

---

## 4. Container Health Check Crashed 106+ Tasks

**Phase:** 5 (Post-deployment)

**What happened:**
ECS service events showed 106 `failedTasks` with `failed container health checks`. The app was serving traffic (ALB health checks passed), but ECS kept killing and replacing tasks.

**Root cause:**
```dockerfile
# Dockerfile HEALTHCHECK
HEALTHCHECK CMD python -c "import requests; requests.get('http://localhost:8000/health', timeout=2)"
```

`requests` was not in `requirements.txt`. The container health check (run inside the container) failed on every check. ALB health checks (hitting the TCP port externally) still passed, so traffic worked — but ECS saw unhealthy containers and replaced them on a loop.

**Two separate health check systems:**
| Health Check | Who runs it | What it checks | Effect of failure |
|---|---|---|---|
| Container HEALTHCHECK | Docker daemon inside container | Command exit code | Task replaced by ECS |
| ALB Target Group health check | ALB, externally | HTTP 200 from `/health` | Target deregistered |

**Fix:**
```txt
# requirements.txt — add:
requests==2.31.0
```

Then rebuild and push the image. `failedTasks` stopped climbing after the fix.

**Lesson:** Always test both health check methods locally. Run `docker inspect <container>` to see the container health status separate from whether the app is reachable.

---

## 5. `terraform output` Variables Not Wired Up

**Phase:** 5 (Blue-green switching scripts)

**What happened:**
```bash
LISTENER_ARN=$(terraform output -raw alb_listener_arn)
# Error: No outputs found
```

The ALB module outputs the listener ARN internally, but it was never exposed at the `terraform/environments/prod/outputs.tf` level.

**Fix:** Use hardcoded ARNs for operational scripts (they don't change once deployed). Add missing outputs to `outputs.tf` for future use.

**Lesson:** Module outputs need to be explicitly re-exported at each level of the module hierarchy. If `module.alb` outputs `listener_arn`, the root module must also declare `output "alb_listener_arn" { value = module.alb.listener_arn }` for it to be accessible via `terraform output`.

---

## 6. `modify-listener` Simple Syntax Rejected After Weighted Config

**Phase:** 5 (Traffic switching)

**What happened:**
After the ALB listener was configured with a weighted `ForwardConfig` block (required to support both blue and green target groups), the simple CLI syntax failed:

```bash
aws elbv2 modify-listener \
  --default-actions Type=forward,TargetGroupArn=$GREEN_TG
# Error: Invalid request
```

Once a listener uses `ForwardConfig` (weighted), the API requires `ForwardConfig` on all subsequent updates — you can't mix syntaxes.

**Fix:**
```bash
aws elbv2 modify-listener \
  --default-actions '[{"Type":"forward","ForwardConfig":{"TargetGroups":[
    {"TargetGroupArn":"<GREEN_ARN>","Weight":100},
    {"TargetGroupArn":"<BLUE_ARN>","Weight":0}
  ]}}]'
```

**Lesson:** Once you use advanced listener features, all future CLI modifications must use the full JSON syntax. Document your ARNs — you'll need them.

---

## 7. ECS Service Running 4 Tasks Instead of 2

**Phase:** 5 (After force-new-deployment)

**What happened:**
`runningCount: 4` reported during `--force-new-deployment` when `desiredCount` was 2.

**Why this is normal:**
ECS rolling deployment uses `maximumPercent: 200`. With `desiredCount=2`, it can run up to 4 tasks simultaneously (2 old + 2 new) while swapping them out. Once new tasks pass health checks, old tasks are drained. The count returns to 2 automatically.

**Lesson:** runningCount temporarily exceeding desiredCount during a rolling deploy is expected and correct. Only worry if it stays elevated or if you see `failedTasks` climbing.

---

## 8. Same Image = Both Slots Show "green" Deployment String

**What happened:**
After fixing the container health check, both the blue and green service returned `"deployment": "green"` from the health endpoint — even the "blue" service.

**Why:** When we rebuilt the image to fix `requests`, we pushed the same `app.py` (which hardcodes `"deployment": "green"`) to both `:latest` (blue) and `:green` tags.

**The trade-off:** A real blue-green scenario would have distinct code between the two. This project used the same image to simplify the proof-of-concept; what was demonstrated was the **routing mechanism**, not a code difference.

**Lesson:** For portfolio purposes, the blue-green mechanism (ALB listener switching, health checks, rollback timing) is the valuable part — not which string is hardcoded in the app. Document the distinction clearly.

---

## What I'd Do Differently in Production

| This Project | Production Change | Reason |
|---|---|---|
| Public subnets for ECS | Private subnets + NAT Gateway | Defence in depth |
| Single-AZ RDS | Multi-AZ RDS | HA, automatic failover |
| Manual blue-green switch | CodeDeploy or weighted canary with CloudWatch alarm rollback | Automated rollback on error rate spike |
| Hardcoded ARNs in scripts | `terraform output` with all outputs wired | Maintainability |
| `db.t3.micro` | `db.t3.small` minimum for production workload | IOPS headroom |
| No autoscaling | ECS Service Auto Scaling on CPU/memory | Cost + availability |
