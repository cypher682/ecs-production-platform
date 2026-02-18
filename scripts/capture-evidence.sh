# Create: scripts/capture-evidence.sh

#!/bin/bash
EVIDENCE_DIR="docs/evidence"
mkdir -p $EVIDENCE_DIR

echo "Capturing infrastructure state..."

# 1. VPC details
aws ec2 describe-vpcs --filters "Name=tag:Name,Values=production-vpc" > $EVIDENCE_DIR/vpc-details.json

# 2. Security group rules (formatted)
aws ec2 describe-security-groups --filters "Name=tag:Project,Values=ecs-production" \
  --query 'SecurityGroups[*].[GroupName,GroupId,IpPermissions]' \
  --output table > $EVIDENCE_DIR/security-group-rules.txt

# 3. ECS task definition
aws ecs describe-task-definition --task-definition flask-app:1 > $EVIDENCE_DIR/task-definition.json

# 4. ALB target health
aws elbv2 describe-target-health --target-group-arn $(aws elbv2 describe-target-groups --names flask-blue --query 'TargetGroups[0].TargetGroupArn' --output text) > $EVIDENCE_DIR/target-health.json

# 5. CloudWatch logs sample (last 50 lines)
aws logs tail /ecs/flask-app --since 1h --format short > $EVIDENCE_DIR/app-logs.txt

# 6. RDS connection test
aws rds describe-db-instances --db-instance-identifier production-db --query 'DBInstances[0].[Endpoint.Address,Endpoint.Port,DBInstanceStatus]' --output table > $EVIDENCE_DIR/rds-endpoint.txt

echo "✅ Evidence captured in $EVIDENCE_DIR/"
