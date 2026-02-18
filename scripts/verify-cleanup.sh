# Create this as: scripts/verify-cleanup.sh

#!/bin/bash
echo "Checking for remaining resources..."

echo "1. ECS Clusters:"
aws ecs list-clusters --query 'clusterArns' --output table

echo "2. Load Balancers:"
aws elbv2 describe-load-balancers --query 'LoadBalancers[*].LoadBalancerName' --output table

echo "3. RDS Instances:"
aws rds describe-db-instances --query 'DBInstances[*].DBInstanceIdentifier' --output table

echo "4. NAT Gateways:"
aws ec2 describe-nat-gateways --filter "Name=state,Values=available" --query 'NatGateways[*].NatGatewayId' --output table

echo "5. Elastic IPs:"
aws ec2 describe-addresses --query 'Addresses[?AssociationId==null].PublicIp' --output table

echo "6. Route 53 Hosted Zones:"
aws route53 list-hosted-zones --query 'HostedZones[*].Name' --output table

echo "✅ If all sections are empty (except Route 53), cleanup successful"
