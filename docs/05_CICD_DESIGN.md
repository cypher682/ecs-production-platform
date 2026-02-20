# CI/CD Pipeline Design

**Status:** Code written and committed. Not tested live.  
**Reason:** Sprint window optimised for infrastructure and blue-green validation. Pipeline can be enabled by completing the OIDC setup below.

---

## Pipeline Architecture

```
Push to main (app/** changes)
        |
        v
GitHub Actions triggered
        |
        +-- Build Docker image (tagged with git SHA)
        |
        +-- Push to ECR (:latest + :<sha>)
        |
        +-- Download current green task definition
        |
        +-- Render new task definition with updated image
        |
        +-- Deploy to ecs-prod-service-green
        |
        +-- Wait for service stability (2 min health check)
        |
        v
Manual step: switch ALB listener to green (100%)
Manual step: monitor for 15 minutes
Manual step: scale blue to 0
```

---

## Authentication: OIDC (No Long-Lived Keys)

GitHub Actions requests short-lived AWS credentials on each run. No secrets are stored in GitHub.

### Why OIDC Over Access Keys

| Method | Token Lifetime | Rotation | Audit Trail |
|---|---|---|---|
| IAM Access Keys | Permanent | Manual | Limited |
| OIDC Tokens | ~1 hour (per workflow run) | Automatic | Full CloudTrail |

### Setup Steps (Not Applied — Reference Only)

**1. Create IAM Identity Provider**
```bash
aws iam create-open-id-connect-provider \
  --url https://token.actions.githubusercontent.com \
  --client-id-list sts.amazonaws.com \
  --thumbprint-list 6938fd4d98bab03faadb97b34396831e3780aea1
```

**2. Create Deployment IAM Role**

Trust policy (allows only pushes to `main` branch of this repo):
```json
{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Principal": {
      "Federated": "arn:aws:iam::758620460011:oidc-provider/token.actions.githubusercontent.com"
    },
    "Action": "sts:AssumeRoleWithWebIdentity",
    "Condition": {
      "StringEquals": {
        "token.actions.githubusercontent.com:aud": "sts.amazonaws.com",
        "token.actions.githubusercontent.com:sub": "repo:cypher682/ecs-production-platform:ref:refs/heads/main"
      }
    }
  }]
}
```

**3. Permissions Required**

```
ECR:
  ecr:GetAuthorizationToken          (global)
  ecr:BatchCheckLayerAvailability    (repository)
  ecr:PutImage                       (repository)
  ecr:InitiateLayerUpload            (repository)
  ecr:UploadLayerPart                (repository)
  ecr:CompleteLayerUpload            (repository)

ECS:
  ecs:DescribeTaskDefinition
  ecs:RegisterTaskDefinition
  ecs:UpdateService
  ecs:DescribeServices
  ecs:ListTasks
  ecs:DescribeTasks

IAM:
  iam:PassRole    (scoped to task execution + task roles only)
```

**4. Enable in deploy.yml**

Uncomment the `permissions` block and the `configure-aws-credentials` step. Replace the `run: exit 1` placeholder with the real action.

---

## Deployment Strategy

### Normal Deploy (Push to main)
1. Code pushed to `main` branch (app code changes)
2. GitHub Actions builds Docker image tagged `:${GITHUB_SHA}`
3. Image pushed to ECR with `:latest` and `:${SHA}` tags
4. New green task definition registered with updated image URI
5. Green ECS service updated — rolling deploy
6. Workflow waits for service stability (tasks pass health checks)
7. Deployment summary printed with manual next steps

### Manual Traffic Switch (After Verification)
```bash
aws elbv2 modify-listener \
  --listener-arn <HTTPS_LISTENER_ARN> \
  --default-actions '[{"Type":"forward","ForwardConfig":{"TargetGroups":[
    {"TargetGroupArn":"<GREEN_TG_ARN>","Weight":100},
    {"TargetGroupArn":"<BLUE_TG_ARN>","Weight":0}
  ]}}]'
```

### Rollback (workflow_dispatch trigger)
- Operator triggers rollback workflow from GitHub Actions UI
- Provides reason (logged to workflow summary)
- ALB listener switched back to blue in <1 second
- Blue scaled to 2, green scaled to 0

---

## Canary Deployment Option (Future)

Instead of instant 100% switch, this flow sends 10% to green first:

```
Step 1: green=10%, blue=90%   — monitor 5 minutes
Step 2: green=50%, blue=50%   — monitor 5 minutes
Step 3: green=100%, blue=0%   — complete
```

Implemented by calling `modify-listener` three times with different weight values and sleeping between steps. CloudWatch alarms can trigger rollback if error rate exceeds threshold at any stage.

---

## Terraform Module (Reference Only)

`terraform/modules/cicd/` contains the IaC for the OIDC provider and deployment IAM role. This module is **not wired into `terraform/environments/prod/main.tf`** — it is reference code to show how you would provision this infrastructure reproducibly.

To apply it:
1. Add `module "cicd" { source = "../../modules/cicd" ... }` to `prod/main.tf`
2. Pass `ecr_repository_arn`, `ecs_task_execution_role_arn`, `ecs_task_role_arn`
3. Run `terraform apply`
4. Note the output `github_actions_role_arn` and set it in `deploy.yml`
