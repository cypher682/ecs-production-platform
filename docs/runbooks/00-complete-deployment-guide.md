# Runbook: Complete Deployment Guide

**Purpose:** End-to-end instructions for deploying, testing, and tearing down the ECS production platform. Follow this in order. Anyone with access to this repo and an AWS account can replicate the full setup.

**Estimated time:** 45–60 minutes (most of that is `terraform apply` and RDS provisioning waiting)  
**Estimated cost:** ~$0.50 for a 4-hour validation session, ~$1.64 per 24 hours.

> **Related runbooks:**
> - [`rollback-procedure.md`](./rollback-procedure.md) — how to roll back a failed deployment
> - [`deployment-failure.md`](./deployment-failure.md) — diagnosing ECS deployment failures
> - [`database-connection.md`](./database-connection.md) — diagnosing RDS connectivity issues

---

## Prerequisites

### Tools Required

| Tool | Min Version | Install |
|---|---|---|
| AWS CLI | v2 | [docs.aws.amazon.com/cli](https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html) |
| Terraform | v1.6+ | [developer.hashicorp.com/terraform](https://developer.hashicorp.com/terraform/install) |
| Docker | any recent | [docs.docker.com/get-docker](https://docs.docker.com/get-docker/) |
| Git | any | system package manager |

Verify:
```bash
aws --version
terraform -version
docker --version
```

### AWS Account Requirements

- An AWS account with billing enabled
- An IAM user with `AdministratorAccess` (or a scoped policy covering EC2, ECS, RDS, ALB, IAM, S3, DynamoDB, SSM, Route 53, ACM, CloudWatch, ECR)
- AWS CLI configured: `aws configure` — enter your Access Key ID, Secret Access Key, region (`us-east-1`), output (`json`)
- A Route 53 hosted zone for a domain you control (e.g., `cipherpol.xyz`)

> **Windows Git Bash users:** Run this at the start of every session to prevent path mangling:
> ```bash
> export MSYS_NO_PATHCONV=1
> ```

---

## Phase 1: Bootstrap AWS Resources (One-Time Setup)

These resources must exist before Terraform can store state. Create them once. Do not destroy them.

### 1.1 Create the S3 State Bucket

```bash
# Replace ACCOUNT_ID with your 12-digit AWS account ID
aws s3api create-bucket \
  --bucket cipherpol-terraform-state-ACCOUNT_ID \
  --region us-east-1

# Enable versioning (allows state recovery)
aws s3api put-bucket-versioning \
  --bucket cipherpol-terraform-state-ACCOUNT_ID \
  --versioning-configuration Status=Enabled

# Block all public access
aws s3api put-public-access-block \
  --bucket cipherpol-terraform-state-ACCOUNT_ID \
  --public-access-block-configuration \
    BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true
```

### 1.2 Create the DynamoDB Lock Table

```bash
aws dynamodb create-table \
  --table-name cipherpol-terraform-locks \
  --attribute-definitions AttributeName=LockID,AttributeType=S \
  --key-schema AttributeName=LockID,KeyType=HASH \
  --billing-mode PAY_PER_REQUEST \
  --region us-east-1
```

### 1.3 Create the ECR Repository

```bash
aws ecr create-repository \
  --repository-name ecs-prod/flask-app \
  --region us-east-1
```

Note the repository URI from the output — format: `ACCOUNT_ID.dkr.ecr.us-east-1.amazonaws.com/ecs-prod/flask-app`

### 1.4 Store the Database Password in SSM

Pick a strong password. Store it now — Terraform will read it from SSM during apply.

```bash
export MSYS_NO_PATHCONV=1

aws ssm put-parameter \
  --name /ecs-prod/db/password \
  --value "YOUR_STRONG_PASSWORD_HERE" \
  --type SecureString \
  --region us-east-1
```

### 1.5 Update `backend.tf`

Open `terraform/environments/prod/backend.tf` and replace the bucket name with your actual bucket:

```hcl
terraform {
  backend "s3" {
    bucket         = "cipherpol-terraform-state-ACCOUNT_ID"   # <- your bucket
    key            = "prod/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "cipherpol-terraform-locks"
    encrypt        = true
  }
}
```

### 1.6 Update `terraform.tfvars` (or set variables)

Check `terraform/environments/prod/variables.tf` for required variables. The key ones:

```hcl
# terraform/environments/prod/terraform.tfvars  (DO NOT COMMIT THIS FILE)
project_name       = "ecs-prod"
aws_region         = "us-east-1"
domain_name        = "cipherpol.xyz"          # your domain
aws_account_id     = "758620460011"           # your account ID
```

> `terraform.tfvars` is gitignored. Create it locally or pass variables via `TF_VAR_*` environment variables.

---

## Phase 2: Build and Push the Docker Image

Before applying Terraform, the container image must already exist in ECR — ECS will try to pull it during `apply`.

```bash
cd app

# Authenticate Docker to ECR
export ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
aws ecr get-login-password --region us-east-1 | \
  docker login --username AWS --password-stdin \
  $ACCOUNT_ID.dkr.ecr.us-east-1.amazonaws.com

# Build the image
docker build -t ecs-prod/flask-app:v1.0.0 .

# Tag for ECR
ECR_REPO="$ACCOUNT_ID.dkr.ecr.us-east-1.amazonaws.com/ecs-prod/flask-app"
docker tag ecs-prod/flask-app:v1.0.0 $ECR_REPO:v1.0.0
docker tag ecs-prod/flask-app:v1.0.0 $ECR_REPO:latest

# Push both tags
docker push $ECR_REPO:v1.0.0
docker push $ECR_REPO:latest

cd ..
```

---

## Phase 3: Deploy Infrastructure

```bash
cd terraform/environments/prod

# Set the DB password variable (reads from SSM so you do not hardcode it)
export MSYS_NO_PATHCONV=1
export TF_VAR_db_password=$(aws ssm get-parameter \
  --name /ecs-prod/db/password \
  --with-decryption \
  --query Parameter.Value \
  --output text)

# Initialise — downloads providers, connects to S3 backend
terraform init

# Preview — read this carefully before applying
terraform plan -out=deploy.tfplan

# Apply
terraform apply "deploy.tfplan"
```

**Expected duration:** 10–15 minutes. RDS provisioning takes the longest (~8 minutes on its own).

**What gets created:** 36 resources — VPC, subnets, security groups, IGW, route tables, ALB, two target groups, HTTPS listener, ECS cluster, two task definitions, two services, RDS instance, IAM roles, CloudWatch log group, ACM certificate, Route 53 records.

### 3.1 Verify the Deployment

Once `apply` completes, get the app URL from outputs:

```bash
terraform output
# Look for: alb_dns_name, app_url
```

Test the endpoints:

```bash
BASE_URL="https://app.cipherpol.xyz"   # or use the ALB DNS directly for HTTP

curl $BASE_URL/health
# Expected: {"status": "healthy", "version": "1.0.0", "deployment": "blue"}

curl $BASE_URL/db-check
# Expected: {"status": "connected", "database": "app_db"}

curl $BASE_URL/items
# Expected: {"count": 0, "items": []}
```

If `/health` returns a 503 or no response, wait 2–3 minutes — ECS tasks need time to start and pass initial health checks.

---

## Phase 4: Blue-Green Deployment

This phase deploys a new version to the green service and switches traffic.

### 4.1 Build and Push the New Image

```bash
cd app

# Make a visible change so you can confirm the switch
# Edit app.py: change "version": "1.0.0" to "version": "2.0.0"
# and "deployment": "blue" to a variable if not already

docker build -t ecs-prod/flask-app:v2.0.0 .
docker tag ecs-prod/flask-app:v2.0.0 $ECR_REPO:v2.0.0
docker tag ecs-prod/flask-app:v2.0.0 $ECR_REPO:green
docker push $ECR_REPO:v2.0.0
docker push $ECR_REPO:green

cd ..
```

### 4.2 Get the Resource ARNs

```bash
cd terraform/environments/prod
terraform output
cd ../../..

# Or look them up directly
LISTENER_ARN=$(aws elbv2 describe-listeners \
  --load-balancer-arn $(aws elbv2 describe-load-balancers \
    --names ecs-prod-alb --query 'LoadBalancers[0].LoadBalancerArn' --output text) \
  --query 'Listeners[?Port==`443`].ListenerArn | [0]' \
  --output text)

BLUE_TG=$(aws elbv2 describe-target-groups \
  --names ecs-prod-blue \
  --query 'TargetGroups[0].TargetGroupArn' --output text)

GREEN_TG=$(aws elbv2 describe-target-groups \
  --names ecs-prod-green \
  --query 'TargetGroups[0].TargetGroupArn' --output text)
```

### 4.3 Scale Up the Green Service

```bash
aws ecs update-service \
  --cluster ecs-prod-cluster \
  --service ecs-prod-service-green \
  --desired-count 2 \
  --region us-east-1

echo "Waiting for green tasks to become healthy (~90 seconds)..."
```

Check green target group health:

```bash
aws elbv2 describe-target-health \
  --target-group-arn $GREEN_TG \
  --query 'TargetHealthDescriptions[*].{IP:Target.Id,State:TargetHealth.State}' \
  --output table
```

Wait until both targets show `healthy` before proceeding.

### 4.4 Switch Traffic to Green

```bash
export MSYS_NO_PATHCONV=1

aws elbv2 modify-listener \
  --listener-arn $LISTENER_ARN \
  --default-actions '[{"Type":"forward","ForwardConfig":{"TargetGroups":[
    {"TargetGroupArn":"'"$GREEN_TG"'","Weight":100},
    {"TargetGroupArn":"'"$BLUE_TG"'","Weight":0}
  ]}}]' \
  --region us-east-1
```

### 4.5 Verify Green is Serving

```bash
curl https://app.cipherpol.xyz/health
# Expected: {"status": "healthy", "version": "2.0.0", "deployment": "green"}

# Write a test item on green
curl -X POST https://app.cipherpol.xyz/items \
  -H "Content-Type: application/json" \
  -d '{"name": "written on green v2.0.0"}'

curl https://app.cipherpol.xyz/items
# Should include all items written on blue AND green (same RDS)
```

### 4.6 Scale Blue to Zero (After Soak Period)

Once you are satisfied green is healthy, remove blue's capacity:

```bash
aws ecs update-service \
  --cluster ecs-prod-cluster \
  --service ecs-prod-service \
  --desired-count 0 \
  --region us-east-1
```

> **To roll back at any point before scaling blue to 0:** see [`rollback-procedure.md`](./rollback-procedure.md).

---

## Phase 5: Capture Evidence (Before Destroying)

```bash
# From the project root
bash scripts/capture-evidence.sh
```

This saves 24+ files to `docs/evidence/` — VPC state, IAM roles, ECS services, target group health, live API responses, CloudWatch logs, and Terraform outputs.

Commit the evidence before destroying:

```bash
git add docs/evidence/
git commit -m "Add pre-destroy infrastructure evidence"
git push origin main
```

---

## Phase 6: Teardown

```bash
export MSYS_NO_PATHCONV=1

# Scale both services to 0 first (avoids 5-minute ALB connection draining wait)
aws ecs update-service \
  --cluster ecs-prod-cluster \
  --service ecs-prod-service \
  --desired-count 0 \
  --region us-east-1

aws ecs update-service \
  --cluster ecs-prod-cluster \
  --service ecs-prod-service-green \
  --desired-count 0 \
  --region us-east-1

echo "Waiting 60 seconds for tasks to drain..."
sleep 60

# Destroy all 36 resources
cd terraform/environments/prod

export TF_VAR_db_password="deleteme"
# Note: any value works here — Terraform just needs a non-empty string for variable validation during destroy

terraform destroy
# Type "yes" when prompted
# Duration: ~8 minutes
```

### What terraform destroy Does NOT Remove

These must be deleted manually if you want a clean account:

| Resource | How to Delete |
|---|---|
| S3 state bucket | Console → S3 → empty bucket → delete |
| DynamoDB lock table | Console → DynamoDB → delete table |
| ECR repository + images | `aws ecr delete-repository --repository-name ecs-prod/flask-app --force` |
| CloudWatch log group | Console → CloudWatch → Log Groups → delete (or wait for 7-day retention) |
| SSM parameter | `aws ssm delete-parameter --name /ecs-prod/db/password` |

---

## Troubleshooting Quick Reference

| Symptom | Likely Cause | See |
|---|---|---|
| ECS tasks cycling (106+ failed) | Docker HEALTHCHECK failure | [`deployment-failure.md`](./deployment-failure.md) |
| ALB returns 503 immediately | Tasks not yet healthy | Wait 2–3 min, check target group health |
| `ParameterNotFound` in Git Bash | MSYS path mangling | `export MSYS_NO_PATHCONV=1` |
| `terraform destroy` hangs | ALB connection draining | Scale services to 0 first, wait 60s |
| `Cannot find version X.Y` for RDS | AWS retired that minor version | Use `15.12` or latest available |
| Green targets showing `initial` state | Health checks not started yet | Wait 60–90 seconds |
| `modify-listener` syntax rejected | Listener uses ForwardConfig | Use full JSON syntax, not shorthand |

---

*Last updated: 2026-02-21. Validated on AWS us-east-1.*
