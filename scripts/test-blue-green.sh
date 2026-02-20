#!/bin/bash
# ============================================================
# Blue-Green Deployment Test & Evidence Collection
# ============================================================
set -e

EVIDENCE_DIR="docs/evidence/phase5"
mkdir -p "$EVIDENCE_DIR"

# --- Hardcoded ARNs (no terraform output dependency) --------
LISTENER_ARN="arn:aws:elasticloadbalancing:us-east-1:758620460011:listener/app/ecs-prod-alb/c529ae37b5ed6daf/c8d36be55bbaecb6"
BLUE_TG="arn:aws:elasticloadbalancing:us-east-1:758620460011:targetgroup/ecs-prod-blue/685ae4abdbf9d56a"
GREEN_TG="arn:aws:elasticloadbalancing:us-east-1:758620460011:targetgroup/ecs-prod-green/5076df5d9c3fb320"
BASE_URL="https://app.cipherpol.xyz"
# ------------------------------------------------------------

echo "=== Blue-Green Deployment Evidence Collection ==="
echo ""

# 1. Capture current (blue) state before switching
echo "--- 1. Current BLUE deployment state ---"
curl -s "$BASE_URL/health" | tee "$EVIDENCE_DIR/01-blue-health.json" | jq '{version, deployment}'
curl -s "$BASE_URL/items"  | tee "$EVIDENCE_DIR/01-blue-items.json"  | jq '{count}'
echo ""

# 2. Switch to GREEN
echo "--- 2. Switching ALB listener to GREEN (100%) ---"
aws elbv2 modify-listener \
  --listener-arn "$LISTENER_ARN" \
  --default-actions '[{"Type":"forward","ForwardConfig":{"TargetGroups":[{"TargetGroupArn":"'"$GREEN_TG"'","Weight":100},{"TargetGroupArn":"'"$BLUE_TG"'","Weight":0}]}}]' \
  --region us-east-1 \
  --output json | jq '.Listeners[0].DefaultActions[0].ForwardConfig.TargetGroups'
echo "✅ Traffic switched to GREEN"
sleep 3
echo ""

# 3. Verify green is serving
echo "--- 3. GREEN deployment health check ---"
curl -s "$BASE_URL/health" | tee "$EVIDENCE_DIR/02-green-health.json" | jq '{version, deployment}'
echo ""

# 4. Verify data still accessible (same DB)
echo "--- 4. Data persistence check ---"
curl -s "$BASE_URL/items" | tee "$EVIDENCE_DIR/03-items-green.json" | jq '{count}'
echo ""

# 5. Create new item on green to prove write path works
echo "--- 5. Write test on GREEN ---"
curl -s -X POST "$BASE_URL/items" \
  -H "Content-Type: application/json" \
  -d '{"name":"Created on Green v2.0"}' | tee "$EVIDENCE_DIR/04-green-write.json" | jq .
echo ""

# 6. Confirm item count increased
echo "--- 6. Final item count ---"
curl -s "$BASE_URL/items" | tee "$EVIDENCE_DIR/05-items-after-write.json" | jq '{count}'
echo ""

# 7. Rollback to BLUE
echo "--- 7. ROLLBACK: switching to BLUE ---"
aws elbv2 modify-listener \
  --listener-arn "$LISTENER_ARN" \
  --default-actions '[{"Type":"forward","ForwardConfig":{"TargetGroups":[{"TargetGroupArn":"'"$BLUE_TG"'","Weight":100},{"TargetGroupArn":"'"$GREEN_TG"'","Weight":0}]}}]' \
  --region us-east-1 \
  --output json | jq '.Listeners[0].DefaultActions[0].ForwardConfig.TargetGroups'
echo "✅ Rolled back to BLUE"
sleep 3
curl -s "$BASE_URL/health" | tee "$EVIDENCE_DIR/06-blue-after-rollback.json" | jq '{version, deployment}'
echo ""

# 8. Data still there after rollback
echo "--- 8. Data persistence after rollback ---"
curl -s "$BASE_URL/items" | tee "$EVIDENCE_DIR/07-items-after-rollback.json" | jq '{count}'
echo ""

# 9. Final switch back to GREEN (permanent)
echo "--- 9. Final switch: GREEN is primary ---"
aws elbv2 modify-listener \
  --listener-arn "$LISTENER_ARN" \
  --default-actions '[{"Type":"forward","ForwardConfig":{"TargetGroups":[{"TargetGroupArn":"'"$GREEN_TG"'","Weight":100},{"TargetGroupArn":"'"$BLUE_TG"'","Weight":0}]}}]' \
  --region us-east-1 \
  --output json > /dev/null
echo "✅ GREEN is now permanent deployment"
echo ""

# 10. Capture target group health states
echo "--- 10. Target group health snapshots ---"
aws elbv2 describe-target-health \
  --target-group-arn "$BLUE_TG" \
  --output json > "$EVIDENCE_DIR/08-blue-tg-health.json"

aws elbv2 describe-target-health \
  --target-group-arn "$GREEN_TG" \
  --output json > "$EVIDENCE_DIR/09-green-tg-health.json"

# 11. Full listener config snapshot
aws elbv2 describe-listeners \
  --listener-arns "$LISTENER_ARN" \
  --output json > "$EVIDENCE_DIR/10-listener-final.json"

# 12. Both service statuses
aws ecs describe-services \
  --cluster ecs-prod-cluster \
  --services ecs-prod-service ecs-prod-service-green \
  --output json > "$EVIDENCE_DIR/11-services-status.json"

# 13. Scale blue down
echo "--- 11. Scaling blue to 0 tasks ---"
aws ecs update-service \
  --cluster ecs-prod-cluster \
  --service ecs-prod-service \
  --desired-count 0 \
  --region us-east-1 \
  --output json | jq '{desiredCount: .service.desiredCount, runningCount: .service.runningCount}'
echo "✅ Blue scaled to 0, Green is primary"
echo ""

echo "============================================"
echo "✅ All evidence saved to: $EVIDENCE_DIR"
ls -la "$EVIDENCE_DIR/"
