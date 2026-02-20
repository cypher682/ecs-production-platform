#!/bin/bash
# =============================================================
# Evidence Capture Script — ECS Production Platform
# Git Bash compatible — no jq required.
# Usage: bash scripts/capture-evidence.sh
# =============================================================
set -e

EVIDENCE_DIR="docs/evidence"
SCREENSHOTS_DIR="$EVIDENCE_DIR/screenshots"
mkdir -p "$EVIDENCE_DIR" "$SCREENSHOTS_DIR"

# --- Hardcoded resource identifiers -------------------------
CLUSTER="ecs-prod-cluster"
BLUE_SERVICE="ecs-prod-service"
GREEN_SERVICE="ecs-prod-service-green"
TASK_DEF_BLUE="ecs-prod-flask-app"
TASK_DEF_GREEN="ecs-prod-flask-app-green"
ALB_NAME="ecs-prod-alb"
LISTENER_ARN="arn:aws:elasticloadbalancing:us-east-1:758620460011:listener/app/ecs-prod-alb/c529ae37b5ed6daf/c8d36be55bbaecb6"
BLUE_TG="arn:aws:elasticloadbalancing:us-east-1:758620460011:targetgroup/ecs-prod-blue/685ae4abdbf9d56a"
GREEN_TG="arn:aws:elasticloadbalancing:us-east-1:758620460011:targetgroup/ecs-prod-green/5076df5d9c3fb320"
DB_IDENTIFIER="ecs-prod-db-cd31bf39"
LOG_GROUP="/ecs/ecs-prod/flask-app"
BASE_URL="https://app.cipherpol.xyz"
REGION="us-east-1"
# ------------------------------------------------------------

echo ""
echo "============================================================"
echo "  ECS Production Platform - Evidence Capture"
echo "  $(date '+%Y-%m-%d %H:%M:%S')"
echo "============================================================"
echo ""

# ---- 1. VPC & Networking -----------------------------------
echo "[1/12] Capturing VPC & networking..."
aws ec2 describe-vpcs \
  --filters "Name=tag:Project,Values=ecs-production-platform" \
  --region $REGION \
  --output json > "$EVIDENCE_DIR/01-vpc.json"

aws ec2 describe-subnets \
  --filters "Name=tag:Project,Values=ecs-production-platform" \
  --region $REGION \
  --output json > "$EVIDENCE_DIR/02-subnets.json"

aws ec2 describe-route-tables \
  --filters "Name=tag:Project,Values=ecs-production-platform" \
  --region $REGION \
  --output json > "$EVIDENCE_DIR/03-route-tables.json"

aws ec2 describe-security-groups \
  --filters "Name=tag:Project,Values=ecs-production-platform" \
  --region $REGION \
  --output json > "$EVIDENCE_DIR/04-security-groups.json"

VPC_ID=$(aws ec2 describe-vpcs \
  --filters "Name=tag:Project,Values=ecs-production-platform" \
  --region $REGION \
  --query 'Vpcs[0].VpcId' \
  --output text)
echo "    OK VPC: $VPC_ID"
echo "    OK Subnets/route-tables/security-groups saved"

# ---- 2. IAM Roles ------------------------------------------
echo "[2/12] Capturing IAM roles..."
EXEC_ROLE=$(aws iam list-roles \
  --query 'Roles[?contains(RoleName, `ecs-prod-ecs-exec`)].RoleName | [0]' \
  --output text 2>/dev/null)

TASK_ROLE=$(aws iam list-roles \
  --query 'Roles[?contains(RoleName, `ecs-prod-ecs-task`)].RoleName | [0]' \
  --output text 2>/dev/null)

if [ "$EXEC_ROLE" != "None" ] && [ -n "$EXEC_ROLE" ]; then
  aws iam get-role --role-name "$EXEC_ROLE" \
    --output json > "$EVIDENCE_DIR/05-iam-execution-role.json"
  echo "    OK Execution role: $EXEC_ROLE"
else
  echo "    WARN Execution role not found by tag — skipping"
fi

if [ "$TASK_ROLE" != "None" ] && [ -n "$TASK_ROLE" ]; then
  aws iam get-role --role-name "$TASK_ROLE" \
    --output json > "$EVIDENCE_DIR/06-iam-task-role.json"
  echo "    OK Task role: $TASK_ROLE"
else
  echo "    WARN Task role not found by tag — skipping"
fi

# ---- 3. ECS Cluster & Services ----------------------------
echo "[3/12] Capturing ECS cluster..."
aws ecs describe-clusters \
  --clusters $CLUSTER \
  --region $REGION \
  --output json > "$EVIDENCE_DIR/07-ecs-cluster.json"

aws ecs describe-services \
  --cluster $CLUSTER \
  --services $BLUE_SERVICE $GREEN_SERVICE \
  --region $REGION \
  --output json > "$EVIDENCE_DIR/08-ecs-services.json"

CLUSTER_STATUS=$(aws ecs describe-clusters \
  --clusters $CLUSTER \
  --region $REGION \
  --query 'clusters[0].status' \
  --output text)

BLUE_DESIRED=$(aws ecs describe-services \
  --cluster $CLUSTER \
  --services $BLUE_SERVICE \
  --region $REGION \
  --query 'services[0].desiredCount' \
  --output text)

GREEN_DESIRED=$(aws ecs describe-services \
  --cluster $CLUSTER \
  --services $GREEN_SERVICE \
  --region $REGION \
  --query 'services[0].desiredCount' \
  --output text)

echo "    OK Cluster: $CLUSTER ($CLUSTER_STATUS)"
echo "    OK Blue desired: $BLUE_DESIRED  Green desired: $GREEN_DESIRED"

# ---- 4. Task Definitions -----------------------------------
echo "[4/12] Capturing task definitions..."
aws ecs describe-task-definition \
  --task-definition $TASK_DEF_BLUE \
  --region $REGION \
  --output json > "$EVIDENCE_DIR/09-task-def-blue.json"

aws ecs describe-task-definition \
  --task-definition $TASK_DEF_GREEN \
  --region $REGION \
  --output json > "$EVIDENCE_DIR/10-task-def-green.json"

BLUE_REV=$(aws ecs describe-task-definition \
  --task-definition $TASK_DEF_BLUE \
  --region $REGION \
  --query 'taskDefinition.revision' \
  --output text)

GREEN_REV=$(aws ecs describe-task-definition \
  --task-definition $TASK_DEF_GREEN \
  --region $REGION \
  --query 'taskDefinition.revision' \
  --output text)

echo "    OK Blue task def revision: $BLUE_REV"
echo "    OK Green task def revision: $GREEN_REV"

# ---- 5. ALB & Target Groups --------------------------------
echo "[5/12] Capturing ALB configuration..."
aws elbv2 describe-load-balancers \
  --names $ALB_NAME \
  --region $REGION \
  --output json > "$EVIDENCE_DIR/11-alb.json"

aws elbv2 describe-listeners \
  --listener-arns $LISTENER_ARN \
  --region $REGION \
  --output json > "$EVIDENCE_DIR/12-alb-listeners.json"

aws elbv2 describe-target-health \
  --target-group-arn $BLUE_TG \
  --region $REGION \
  --output json > "$EVIDENCE_DIR/13-blue-tg-health.json"

aws elbv2 describe-target-health \
  --target-group-arn $GREEN_TG \
  --region $REGION \
  --output json > "$EVIDENCE_DIR/14-green-tg-health.json"

ALB_DNS=$(aws elbv2 describe-load-balancers \
  --names $ALB_NAME \
  --region $REGION \
  --query 'LoadBalancers[0].DNSName' \
  --output text)

BLUE_HEALTH=$(aws elbv2 describe-target-health \
  --target-group-arn $BLUE_TG \
  --region $REGION \
  --query 'TargetHealthDescriptions[0].TargetHealth.State' \
  --output text 2>/dev/null || echo "no targets")

GREEN_HEALTH=$(aws elbv2 describe-target-health \
  --target-group-arn $GREEN_TG \
  --region $REGION \
  --query 'TargetHealthDescriptions[0].TargetHealth.State' \
  --output text 2>/dev/null || echo "no targets")

echo "    OK ALB: $ALB_DNS"
echo "    OK Blue TG health: $BLUE_HEALTH"
echo "    OK Green TG health: $GREEN_HEALTH"

# ---- 6. RDS ------------------------------------------------
echo "[6/12] Capturing RDS..."
aws rds describe-db-instances \
  --db-instance-identifier $DB_IDENTIFIER \
  --region $REGION \
  --output json > "$EVIDENCE_DIR/15-rds-instance.json"

DB_STATUS=$(aws rds describe-db-instances \
  --db-instance-identifier $DB_IDENTIFIER \
  --region $REGION \
  --query 'DBInstances[0].DBInstanceStatus' \
  --output text)

DB_ENDPOINT=$(aws rds describe-db-instances \
  --db-instance-identifier $DB_IDENTIFIER \
  --region $REGION \
  --query 'DBInstances[0].Endpoint.Address' \
  --output text)

echo "    OK RDS status: $DB_STATUS"
echo "    OK Endpoint: $DB_ENDPOINT"

# ---- 7. Live Application Tests -----------------------------
echo "[7/12] Testing live application endpoints..."
echo "    Testing $BASE_URL..."

curl -sf "$BASE_URL/" \
  -o "$EVIDENCE_DIR/16-app-root-response.json" \
  --max-time 10 && echo "    OK Root endpoint: responded" || echo "    FAIL Root endpoint: failed"

curl -sf "$BASE_URL/health" \
  -o "$EVIDENCE_DIR/17-app-health-response.json" \
  --max-time 10 && echo "    OK Health endpoint: responded" || echo "    FAIL Health endpoint: failed"

curl -sf "$BASE_URL/db-check" \
  -o "$EVIDENCE_DIR/18-app-dbcheck-response.json" \
  --max-time 10 && echo "    OK DB-check endpoint: responded" || echo "    FAIL DB-check: failed"

curl -sf "$BASE_URL/items" \
  -o "$EVIDENCE_DIR/19-app-items-response.json" \
  --max-time 10 && echo "    OK Items endpoint: responded" || echo "    FAIL Items: failed"

# Print raw responses (no jq needed — already valid JSON files)
echo ""
echo "    Health response:"
cat "$EVIDENCE_DIR/17-app-health-response.json" 2>/dev/null || true
echo ""
echo "    Items response:"
cat "$EVIDENCE_DIR/19-app-items-response.json" 2>/dev/null || true
echo ""

# ---- 8. CloudWatch Logs ------------------------------------
echo "[8/12] Capturing CloudWatch logs (last 2 hours)..."
aws logs tail $LOG_GROUP \
  --since 2h \
  --format short \
  --region $REGION \
  > "$EVIDENCE_DIR/20-cloudwatch-logs.txt" 2>&1 \
  && echo "    OK Logs captured" \
  || echo "    WARN Log capture failed (app may not have written recently)"

# ---- 9. ECR Images -----------------------------------------
echo "[9/12] Capturing ECR image list..."
aws ecr describe-images \
  --repository-name ecs-prod/flask-app \
  --region $REGION \
  --output json \
  --query 'imageDetails[*].{tag:imageTags[0],pushed:imagePushedAt,size:imageSizeInBytes}' \
  > "$EVIDENCE_DIR/21-ecr-images.json" \
  && echo "    OK ECR images captured" \
  || echo "    WARN ECR capture failed"

# ---- 10. SSM Parameters ------------------------------------
echo "[10/12] Capturing SSM parameter names (not values)..."
aws ssm describe-parameters \
  --filters "Key=Name,Values=/ecs-prod/" \
  --region $REGION \
  --output json \
  --query 'Parameters[*].{Name:Name,Type:Type,LastModified:LastModifiedDate}' \
  > "$EVIDENCE_DIR/22-ssm-parameters.json" \
  && echo "    OK SSM parameters captured" \
  || echo "    WARN SSM capture failed"

# ---- 11. Terraform Outputs ---------------------------------
echo "[11/12] Capturing Terraform outputs..."
cd terraform/environments/prod
terraform output -json > "../../../$EVIDENCE_DIR/23-terraform-outputs.json" 2>/dev/null \
  && echo "    OK Terraform outputs captured" \
  || echo "    WARN Run from terraform/environments/prod for full outputs"
cd ../../..

# ---- 12. Cost Estimate -------------------------------------
echo "[12/12] Capturing current cost data..."

# Git Bash compatible date arithmetic
if date -d "7 days ago" +%Y-%m-%d >/dev/null 2>&1; then
  START_DATE=$(date -d "7 days ago" +%Y-%m-%d)
else
  START_DATE=$(date -v-7d +%Y-%m-%d 2>/dev/null || date +%Y-%m-%d)
fi
END_DATE=$(date +%Y-%m-%d)

aws ce get-cost-and-usage \
  --time-period "Start=$START_DATE,End=$END_DATE" \
  --granularity DAILY \
  --metrics BlendedCost \
  --group-by Type=SERVICE \
  --region us-east-1 \
  --output json \
  > "$EVIDENCE_DIR/24-cost-breakdown.json" 2>/dev/null \
  && echo "    OK Cost data captured" \
  || echo "    WARN Cost Explorer may not be enabled (check AWS Console > Billing)"

# ---- Summary -----------------------------------------------
echo ""
echo "============================================================"
echo "  Evidence Capture Complete"
echo "  Location: $EVIDENCE_DIR/"
echo "============================================================"
echo ""
echo "Files saved:"
ls "$EVIDENCE_DIR/"*.json "$EVIDENCE_DIR/"*.txt 2>/dev/null | while read f; do
  echo "  $f"
done
echo ""
echo "Screenshots still needed (manual - AWS Console):"
echo "   01-vpc-overview.png       -- VPC dashboard"
echo "   02-subnets.png            -- Subnet list (public/private)"
echo "   03-security-groups.png    -- Security group rules"
echo "   04-ecs-cluster.png        -- ECS cluster overview"
echo "   05-ecs-services.png       -- Both services (blue + green)"
echo "   06-running-tasks.png      -- Running tasks with IPs"
echo "   07-alb-overview.png       -- ALB details"
echo "   08-target-groups.png      -- Both target groups"
echo "   09-listener-weights.png   -- Listener rule (green=100%)"
echo "   10-rds-instance.png       -- RDS instance details"
echo "   11-cloudwatch-logs.png    -- Log stream with app logs"
echo "   12-billing-dashboard.png  -- Cost breakdown"
echo ""
echo "All JSON evidence saved. Ready for git push then teardown."
