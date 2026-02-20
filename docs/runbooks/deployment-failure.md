# Runbook: Deployment Failure Response

**When to use:** ECS service deployment is stuck — tasks keep failing health checks, `failedTasks` is climbing, or the deployment never reaches `COMPLETED` rollout state.

---

## Diagnostic Flow

```
Deployment stuck?
      │
      ├─ Check: Are tasks starting?
      │    aws ecs describe-services --cluster ecs-prod-cluster --services ecs-prod-service
      │    Look at: runningCount vs desiredCount, failedTasks
      │
      ├─ Check: Are tasks crashing on startup?
      │    aws ecs list-tasks --cluster ecs-prod-cluster --service-name ecs-prod-service
      │    aws ecs describe-tasks --cluster ecs-prod-cluster --tasks <TASK_ARN>
      │    Look at: stoppedReason, containers[].reason
      │
      ├─ Check: Are tasks healthy from ALB perspective?
      │    aws elbv2 describe-target-health --target-group-arn <BLUE_TG_ARN>
      │    Look at: TargetHealth.State (initial/healthy/unhealthy/draining)
      │
      └─ Check: What is the app logging?
           aws logs tail /ecs/ecs-prod/flask-app --since 15m --format short
```

---

## Common Failures & Fixes

### 1. `failedTasks` climbing, "failed container health checks"

**Cause:** The Dockerfile `HEALTHCHECK` command is failing inside the container.

**Diagnose:**
```bash
# Check the healthcheck command in the task definition
aws ecs describe-task-definition \
  --task-definition ecs-prod-flask-app \
  --query 'taskDefinition.containerDefinitions[0].healthCheck'
```

**Common root causes:**
- Python package missing (`import requests` fails if `requests` not in requirements.txt)
- App fails to start (syntax error, missing env var)
- Health check timeout too short (increase `--timeout`)

**Fix:**
1. Fix the issue in `app.py` or `requirements.txt`
2. Rebuild and push: `docker build ... && docker push ...`
3. Force new deployment: `aws ecs update-service --force-new-deployment`

---

### 2. Tasks never start — stuck at 0 running

**Cause:** Image pull failure, or IAM permission issue.

**Diagnose:**
```bash
aws ecs describe-tasks \
  --cluster ecs-prod-cluster \
  --tasks $(aws ecs list-tasks --cluster ecs-prod-cluster --service-name ecs-prod-service --query 'taskArns[0]' --output text) \
  --query 'tasks[0].{status:lastStatus,stopped:stoppedReason,containers:containers[*].{name:name,reason:reason}}'
```

**Common root causes:**
- ECR image tag doesn't exist (`CannotPullContainerError`)
- Task execution role lacks `ecr:BatchGetImage` permission
- Image was built for wrong architecture (e.g., ARM on M1 Mac → fails on Fargate x86)

**Fix for wrong architecture:**
```bash
# Force x86 build on Mac
docker buildx build --platform linux/amd64 -t <ECR_URI>:latest . --push
```

---

### 3. ALB target shows `unhealthy` (app running but health check failing)

**Cause:** ALB health check gets non-200 response, or port/path mismatch.

**Diagnose:**
```bash
aws elbv2 describe-target-health \
  --target-group-arn "arn:aws:elasticloadbalancing:us-east-1:758620460011:targetgroup/ecs-prod-blue/685ae4abdbf9d56a" \
  --query 'TargetHealthDescriptions[*].{IP:Target.Id,State:TargetHealth.State,Reason:TargetHealth.Description}'
```

Check the target group health check settings:
```bash
aws elbv2 describe-target-groups \
  --target-group-arns "arn:aws:elasticloadbalancing:us-east-1:758620460011:targetgroup/ecs-prod-blue/685ae4abdbf9d56a" \
  --query 'TargetGroups[0].{path:HealthCheckPath,port:HealthCheckPort,threshold:HealthyThresholdCount}'
```

**Common root causes:**
- `/health` endpoint returns non-200 (app crash, DB failure on startup)
- Security group doesn't allow ALB → ECS on port 8000
- Health check port is wrong in target group config

---

### 4. Deployment stuck in `IN_PROGRESS` indefinitely

**Cause:** ECS can't replace old tasks because new ones never become healthy — and `minimumHealthyPercent=100` won't drain old tasks until new ones are up.

**Fix:** Force-stop the stuck deployment by temporarily reducing `minimumHealthyPercent`:
```bash
aws ecs update-service \
  --cluster ecs-prod-cluster \
  --service ecs-prod-service \
  --deployment-configuration "maximumPercent=200,minimumHealthyPercent=0" \
  --force-new-deployment \
  --region us-east-1

# Restore after fix
aws ecs update-service \
  --cluster ecs-prod-cluster \
  --service ecs-prod-service \
  --deployment-configuration "maximumPercent=200,minimumHealthyPercent=100" \
  --region us-east-1
```

---

## Emergency: Roll Back to Last Known Good Image

```bash
# Find previous task definition revision
aws ecs list-task-definitions \
  --family-prefix ecs-prod-flask-app \
  --sort DESC \
  --query 'taskDefinitionArns[:5]' \
  --output table

# Update service to use previous revision
aws ecs update-service \
  --cluster ecs-prod-cluster \
  --service ecs-prod-service \
  --task-definition ecs-prod-flask-app:<PREVIOUS_REVISION_NUMBER> \
  --region us-east-1
```
