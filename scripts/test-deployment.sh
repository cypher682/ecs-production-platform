
#!/bin/bash
ALB_DNS="your-alb-dns.us-east-1.elb.amazonaws.com"  # Replace after deployment

echo "Testing application endpoints..."

# 1. Health check
echo "1. Health Check:"
curl -s https://$ALB_DNS/health | jq .

# 2. Database connectivity
echo "2. Database Check:"
curl -s https://$ALB_DNS/db-check | jq .

# 3. Create item
echo "3. Create Item:"
curl -s -X POST https://$ALB_DNS/items -H "Content-Type: application/json" -d '{"name":"test-item"}' | jq .

# 4. List items
echo "4. List Items:"
curl -s https://$ALB_DNS/items | jq .

# 5. Load test (10 requests)
echo "5. Load Test:"
ab -n 10 -c 2 https://$ALB_DNS/health

# Save results
curl -s https://$ALB_DNS/health > docs/evidence/health-response.json
curl -s https://$ALB_DNS/items > docs/evidence/items-response.json
