# Runbook: Database Connection Issues

**When to use:** The `/db-check` endpoint returns an error, the app can't read/write items, or ECS tasks are crashing because they can't connect to RDS.

---

## Quick Check

```bash
curl -s https://app.cipherpol.xyz/db-check | jq .
```

**Healthy response:**
```json
{"database": "postgresql", "status": "connected", "version": "PostgreSQL 15.12..."}
```

**Unhealthy response:**
```json
{"message": "Database connection failed", "status": "error"}
```

---

## Diagnostic Steps

### Step 1 — Is RDS Running?

```bash
aws rds describe-db-instances \
  --db-instance-identifier ecs-prod-db-cd31bf39 \
  --query 'DBInstances[0].{status:DBInstanceStatus,endpoint:Endpoint.Address,az:AvailabilityZone}' \
  --output table
```

**Expected:** `status = available`

If status is `stopped` or `rebooting`, wait or start it:
```bash
aws rds start-db-instance --db-instance-identifier ecs-prod-db-cd31bf39
```

---

### Step 2 — Does the App Have the Right Endpoint?

The DB endpoint is injected into the task via environment variable at deploy time. If RDS was recreated (new `random_id` suffix), the endpoint changed but the task definition still has the old one.

Check what the running task sees:
```bash
TASK_ARN=$(aws ecs list-tasks \
  --cluster ecs-prod-cluster \
  --service-name ecs-prod-service \
  --query 'taskArns[0]' --output text)

aws ecs describe-tasks \
  --cluster ecs-prod-cluster \
  --tasks $TASK_ARN \
  --query 'tasks[0].overrides.containerOverrides[0].environment'
```

Compare with actual RDS endpoint:
```bash
aws rds describe-db-instances \
  --db-instance-identifier ecs-prod-db-cd31bf39 \
  --query 'DBInstances[0].Endpoint.Address' --output text
```

**Fix:** Update the task definition with the new endpoint and redeploy:
```bash
cd terraform/environments/prod
terraform plan -out=fix.tfplan   # Will update task definition
terraform apply "fix.tfplan"
```

---

### Step 3 — Security Group: Is Port 5432 Open?

```bash
# Get the RDS security group ID
RDS_SG=$(aws rds describe-db-instances \
  --db-instance-identifier ecs-prod-db-cd31bf39 \
  --query 'DBInstances[0].VpcSecurityGroups[0].VpcSecurityGroupId' \
  --output text)

# Check its inbound rules
aws ec2 describe-security-groups \
  --group-ids $RDS_SG \
  --query 'SecurityGroups[0].IpPermissions'
```

**Expected:** Port 5432 allowed from the ECS tasks security group (`sg-09a3082e31d282821`).

If the rule is missing, add it:
```bash
ECS_SG="sg-09a3082e31d282821"
aws ec2 authorize-security-group-ingress \
  --group-id $RDS_SG \
  --protocol tcp \
  --port 5432 \
  --source-group $ECS_SG
```

---

### Step 4 — Is the Password Correct?

The app reads `DB_PASSWORD` from environment, which was set from SSM.

Verify the SSM parameter still exists:
```bash
export MSYS_NO_PATHCONV=1
aws ssm get-parameter \
  --name /ecs-prod/db/password \
  --with-decryption \
  --query 'Parameter.Value' \
  --output text | wc -c   # Print length only, not the password
```

If it returns 0 or errors, the parameter was deleted. Re-create it:
```bash
aws ssm put-parameter \
  --name /ecs-prod/db/password \
  --value "<YOUR_DB_PASSWORD>" \
  --type SecureString \
  --overwrite
```

Then redeploy the ECS service so the new value is injected.

---

### Step 5 — Network Connectivity (Subnet Routing)

ECS tasks are in public subnets. RDS is in private subnets. Both are in the same VPC — they communicate over private IPs and don't need internet access.

Verify they're in the same VPC:
```bash
# VPC of ECS tasks (check security group's VPC)
aws ec2 describe-security-groups \
  --group-ids sg-09a3082e31d282821 \
  --query 'SecurityGroups[0].VpcId' --output text

# VPC of RDS
aws rds describe-db-instances \
  --db-instance-identifier ecs-prod-db-cd31bf39 \
  --query 'DBInstances[0].DBSubnetGroup.VpcId' --output text
```

Both should return: `vpc-0d2a268b450bd99b0`

---

## Reference: Database Connection Details

| Parameter | Value |
|---|---|
| DB Identifier | `ecs-prod-db-cd31bf39` |
| Engine | PostgreSQL 15.12 |
| Port | 5432 |
| Database name | Set via `var.db_name` |
| Username | Set via `var.db_username` |
| Password | SSM: `/ecs-prod/db/password` |
| Subnet | Private (no internet route) |
| Security Group | `sg-07a5aae1f94e3e9e2` (RDS) |
| ECS SG (allowed) | `sg-09a3082e31d282821` |
