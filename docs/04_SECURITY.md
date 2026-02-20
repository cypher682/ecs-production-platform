# Security Design — ECS Production Platform

This document explains every security control implemented in the platform and the reasoning behind each decision.

---

## Network Isolation

### VPC Architecture
```
Internet
  │
  ├─ Public Subnets (10.0.0.0/24, 10.0.1.0/24)
  │    ALB (internet-facing)
  │    ECS tasks (Fargate, public IP assigned)
  │
  └─ Private Subnets (10.0.10.0/24, 10.0.11.0/24)
       RDS PostgreSQL (no internet route)
```

### Security Group Chain

Traffic must traverse three security groups. No resource is directly internet-accessible except through the ALB.

```
Internet → [ALB SG: 80,443 inbound] → ALB
                                        │
                          [ECS SG: 8000 from ALB SG only]
                                        │
                                   ECS Tasks (Flask)
                                        │
                          [RDS SG: 5432 from ECS SG only]
                                        │
                                   RDS PostgreSQL
```

**Key rules:**
- ALB accepts traffic on 80 and 443 from `0.0.0.0/0`
- ECS tasks accept traffic **only from the ALB security group** on port 8000. Direct internet access to containers is blocked even though they have public IPs.
- RDS accepts traffic **only from the ECS security group** on port 5432. No internet access at any point.

### Production Improvement
Move ECS tasks to private subnets. Add NAT Gateway for outbound internet (ECR pulls, SSM calls). This removes the public IP from containers entirely.

---

## IAM: Least Privilege

Two separate IAM roles — a common mistake is merging them into one.

### ECS Task Execution Role
**Purpose:** Allows the ECS control plane to set up the container.

**Permissions:**
- Pull images from ECR (`ecr:GetAuthorizationToken`, `ecr:BatchGetImage`)
- Write logs to CloudWatch Logs
- Read SSM parameters (for secrets injection at startup)
- Read Secrets Manager (if used)

**Does NOT have:** Any application-level AWS permissions.

### ECS Task Role
**Purpose:** Allows the running container to call AWS APIs.

**Permissions:**
- Read specific SSM parameters (`/ecs-prod/*`)
- No other AWS access

**Does NOT have:** ECR access (that's the execution role), CloudWatch write (done by the agent), IAM permissions.

**Why separate?** If the app is compromised, the attacker only gets the task role (limited SSM read). They don't inherit the execution role (which can pull any ECR image or write anywhere).

---

## Secrets Management

**No hardcoded credentials — anywhere.**

### Database Password Flow
```
1. Password generated → stored in SSM Parameter Store (/ecs-prod/db/password, SecureString)
2. Deployment: export TF_VAR_db_password=$(aws ssm get-parameter --with-decryption ...)
3. Terraform passes password to RDS as input variable (never written to state in plaintext)
4. ECS task reads password from SSM at container startup via execution role
5. Password injected as environment variable into container
6. Container connects to RDS using env var — never hardcoded
```

**What's in .gitignore:**
- `*.tfvars` — would contain `db_password = "..."`
- `.db-password-backup.txt` — locally saved backup
- `*password*`, `*secret*` — glob catch-all

**What's in Terraform state:**
The RDS password IS in the terraform state file (this is a known Terraform limitation). The state is stored in S3 with:
- Server-side encryption (AES-256)
- Public access block enabled
- Versioning enabled (for recovery)
- State access controlled by IAM

**Production recommendation:** Use AWS Secrets Manager with automatic rotation instead of SSM. Terraform has a `aws_secretsmanager_secret_rotation` resource.

---

## TLS / HTTPS

- ACM certificate for `*.cipherpol.xyz` (wildcard)
- ALB HTTPS listener on port 443
- HTTP listener on port 80 redirects to HTTPS (no plaintext traffic)
- TLS policy: `ELBSecurityPolicy-TLS13-1-2-2021-06` (TLS 1.2 minimum, TLS 1.3 preferred)
- Certificate auto-renews via ACM (managed by AWS, no manual action)

---

## Container Security

### Multi-Stage Dockerfile
```dockerfile
# Stage 1: builder (has pip, build tools)
FROM python:3.11-slim AS builder
# Install dependencies here

# Stage 2: runtime (minimal)
FROM python:3.11-slim
# Copy only installed packages — no pip, no build tools in final image
```

Benefits:
- Smaller attack surface (no build tools in production image)
- Smaller image size (~120 MB vs ~400 MB single-stage)

### No Root Execution
Container runs as the default Python image user. Gunicorn binds on port 8000 (non-privileged).

### ECR Image Scanning
Amazon ECR can be configured to scan images on push. All images tagged with semantic versions (`latest`, `green`, `v3`) for traceability.

---

## Audit Trail

| Action | Where Logged |
|---|---|
| AWS API calls | CloudTrail (enabled by default) |
| Application requests | CloudWatch Logs (`/ecs/ecs-prod/flask-app`) |
| ECS service events | ECS service event log (30 days) |
| Terraform changes | Git history + S3 state versioning |
| ALB access logs | Can be enabled to S3 (disabled in this project for cost) |

---

## Security Gaps (Honest Assessment)

| Gap | Risk | Production Fix |
|---|---|---|
| ECS tasks in public subnets | Container network interface has public IP | Move to private subnets + NAT |
| No WAF on ALB | No protection against OWASP Top 10 | Enable AWS WAF with managed rules |
| No ALB access logs | Can't audit who called what endpoint | Enable S3 access logging |
| Single-AZ RDS | DB unavailable during AZ failure | Multi-AZ RDS |
| No S3 bucket policy on state | Relies only on IAM | Add explicit bucket policy |
| RDS password in Terraform state | State file contains plaintext password | Migrate to Secrets Manager |
