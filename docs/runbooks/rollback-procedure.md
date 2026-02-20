# Runbook: Blue-Green Rollback Procedure

**When to use:** Green deployment is live (100% traffic) and you need to immediately switch back to blue — due to errors, failed health checks, or bad response data.

**Time to complete:** < 2 minutes

---

## Quick Reference

```bash
# INSTANT ROLLBACK — copy-paste this
aws elbv2 modify-listener \
  --listener-arn "arn:aws:elasticloadbalancing:us-east-1:758620460011:listener/app/ecs-prod-alb/c529ae37b5ed6daf/c8d36be55bbaecb6" \
  --default-actions '[{"Type":"forward","ForwardConfig":{"TargetGroups":[{"TargetGroupArn":"arn:aws:elasticloadbalancing:us-east-1:758620460011:targetgroup/ecs-prod-blue/685ae4abdbf9d56a","Weight":100},{"TargetGroupArn":"arn:aws:elasticloadbalancing:us-east-1:758620460011:targetgroup/ecs-prod-green/5076df5d9c3fb320","Weight":0}]}}]' \
  --region us-east-1
```

---

## Step-by-Step

### Step 1 — Detect the Problem

Signs you need to roll back:
- `curl https://app.cipherpol.xyz/health` returns non-200
- Application errors visible in browser
- CloudWatch logs showing exceptions
- Target group health check showing `unhealthy`

Check target group health first:
```bash
aws elbv2 describe-target-health \
  --target-group-arn "arn:aws:elasticloadbalancing:us-east-1:758620460011:targetgroup/ecs-prod-green/5076df5d9c3fb320" \
  --query 'TargetHealthDescriptions[*].{IP:Target.Id,State:TargetHealth.State,Reason:TargetHealth.Reason}' \
  --output table
```

### Step 2 — Switch Traffic to Blue (Instant)

```bash
aws elbv2 modify-listener \
  --listener-arn "arn:aws:elasticloadbalancing:us-east-1:758620460011:listener/app/ecs-prod-alb/c529ae37b5ed6daf/c8d36be55bbaecb6" \
  --default-actions '[{"Type":"forward","ForwardConfig":{"TargetGroups":[
    {"TargetGroupArn":"arn:aws:elasticloadbalancing:us-east-1:758620460011:targetgroup/ecs-prod-blue/685ae4abdbf9d56a","Weight":100},
    {"TargetGroupArn":"arn:aws:elasticloadbalancing:us-east-1:758620460011:targetgroup/ecs-prod-green/5076df5d9c3fb320","Weight":0}
  ]}}]' \
  --region us-east-1
```

The switch is **instantaneous** — no DNS propagation delay, no connection draining wait.

### Step 3 — Verify Blue is Serving

```bash
curl -s https://app.cipherpol.xyz/health | jq '{status, version, deployment}'
curl -s https://app.cipherpol.xyz/ | jq '{version, deployment}'
```

### Step 4 — Scale Down Green (Optional Cleanup)

If green is in a crash loop, stop it to prevent unnecessary task churn:
```bash
aws ecs update-service \
  --cluster ecs-prod-cluster \
  --service ecs-prod-service-green \
  --desired-count 0 \
  --region us-east-1
```

### Step 5 — Investigate Green Failure

```bash
# Check recent service events
aws ecs describe-services \
  --cluster ecs-prod-cluster \
  --services ecs-prod-service-green \
  --query 'services[0].events[:10]' \
  --output table

# Check CloudWatch logs for exceptions
aws logs tail /ecs/ecs-prod/flask-app --since 30m --format short
```

---

## ARN Reference

| Resource | ARN |
|---|---|
| HTTPS Listener | `arn:aws:elasticloadbalancing:us-east-1:758620460011:listener/app/ecs-prod-alb/c529ae37b5ed6daf/c8d36be55bbaecb6` |
| Blue Target Group | `arn:aws:elasticloadbalancing:us-east-1:758620460011:targetgroup/ecs-prod-blue/685ae4abdbf9d56a` |
| Green Target Group | `arn:aws:elasticloadbalancing:us-east-1:758620460011:targetgroup/ecs-prod-green/5076df5d9c3fb320` |
