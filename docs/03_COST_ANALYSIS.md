# Cost Analysis — ECS Production Platform

**Sprint deploy strategy:** Deploy for 4 hours, capture evidence, destroy. Pay almost nothing while proving production-grade architecture.

---

## Total Actual Cost

| Session | Duration | Total |
|---|---|---|
| Build + validation (Feb 19, 2026) | ~6 hours | ~$0.50 |

Billed on the 3rd of the following month.

---

## Resource-by-Resource Breakdown

### Application Load Balancer (ALB)
- **Rate:** $0.0225/hour + $0.008 per LCU-hour
- **4 hours:** ~$0.09
- **Monthly if left running:** ~$16.20 — this is the primary cost driver
- **Note:** ALB has no free tier. It's billed from minute one.

### ECS Fargate Tasks
Each task: 0.25 vCPU, 0.5 GB RAM (minimum Fargate sizing)

| Resource | Rate | Per task/hour |
|---|---|---|
| vCPU | $0.04048/vCPU-hr | $0.01012 |
| Memory | $0.004445/GB-hr | $0.002223 |
| **Per task** | | **$0.01234** |

Running 2 tasks for 6 hours (blue + green each ran at different times):
~**$0.15** total

### RDS PostgreSQL (db.t3.micro)
- **Free Tier:** 750 hours/month of `db.t3.micro`
- **Cost: $0.00** — fully covered by free tier

### Route 53
- **Hosted Zone:** $0.50/month (prorated ~$0.07 for 5 days)
- **DNS Queries:** $0.40 per million (negligible — a few hundred queries)
- Sub-total: ~$0.07

### ACM Certificate
- **Cost: $0.00** — free with ALB

### Amazon ECR
- **Free Tier:** 500 MB/month free
- Flask image size: ~120 MB (multi-stage build)
- **Cost: $0.00**

### S3 (Terraform State)
- State files: < 1 MB total
- **Cost: $0.00** (well within free tier)

### DynamoDB (Terraform Lock Table)
- On-demand pricing, near-zero reads/writes
- **Cost: $0.00**

### CloudWatch Logs
- **Free Tier:** 5 GB ingestion/month
- **Cost: $0.00**

---

## Production Cost Projection

If this platform ran 24/7 in production with proper architecture:

| Component | Monthly Cost |
|---|---|
| ALB | $16.20 |
| ECS Fargate (2 tasks, always on) | $18.00 |
| RDS db.t3.small (Multi-AZ) | $48.00 |
| NAT Gateway (2 AZs) | $66.00 |
| Route 53 | $0.50 |
| CloudWatch | $3.00 |
| ECR | $1.00 |
| **Total** | **~$152/month** |

### Where the Money Goes
```
NAT Gateway ████████████████████████████ 43%  ($66)
RDS Multi-AZ ████████████████████        31%  ($48)
ALB          ███████████                 11%  ($16)
ECS Fargate  ████████████                12%  ($18)
Other        ██                           3%  ($4.50)
```

---

## Cost Optimization Decisions Made

### 1. Public Subnets Instead of NAT Gateway
- **Saved:** $66/month (NAT Gateway) or $3/month (NAT Instance on t3.nano)
- **Trade-off:** ECS tasks are internet-accessible (mitigated by security groups)
- **Production recommendation:** Use NAT Gateway. The isolation is worth the cost.

### 2. Single-AZ RDS
- **Saved:** ~$24/month (Multi-AZ doubles the instance cost)
- **Trade-off:** No automatic failover during AZ outage
- **Production recommendation:** Multi-AZ for any production workload

### 3. Minimum Fargate Sizing (0.25 vCPU / 0.5 GB)
- **Saved:** ~$18/month vs 1 vCPU / 2 GB
- **Trade-off:** Very limited headroom; not suitable for real traffic
- **Production recommendation:** Profile the app, start at 0.5 vCPU / 1 GB

### 4. Sprint Deploy Strategy
- **Saved:** ~$148/month (vs running 24/7)
- **Method:** Deploy → validate → document → destroy
- **All evidence captured before destroy** (see `docs/evidence/`)

---

## Free Tier Usage

Resources that cost $0 due to free tier:
- ✅ RDS db.t3.micro — 750 hrs/month free
- ✅ ECR storage — 500 MB/month free
- ✅ CloudWatch Logs — 5 GB/month free
- ✅ S3 — 5 GB storage free
- ✅ DynamoDB — 25 GB + 200M requests free
- ✅ ACM certificates — free with ALB

---

## Lessons for Cost Control

1. **ALB is always the hidden cost** — even idle, it charges $16/month. Consider API Gateway for low-traffic APIs, or share one ALB across projects using listener rules.
2. **NAT Gateway is expensive** — $0.045/GB data processing + $0.045/hour. For dev/learning environments, skip it; for production, it's non-negotiable.
3. **Set billing alerts** — `AWS Budgets` threshold at $5 sends an email before costs spiral. This project had a $5 alert configured.
4. **RDS is free tier-friendly** — `db.t3.micro` with single-AZ is the right choice for portfolio projects.
