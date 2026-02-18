# ECS Production Platform — Architecture

## Design Overview

Production-grade deployment platform using AWS ECS Fargate, demonstrating zero-downtime deployments, automated rollback, and cost-optimized design.

## Architecture Diagram
```
Internet
   ↓
Route 53 (cipherpol.xyz)
   ↓
ALB (us-east-1a, us-east-1b) ← ACM Certificate (*.cipherpol.xyz)
   ├─ Target Group: Blue  → ECS Fargate Tasks (public subnets)
   └─ Target Group: Green → ECS Fargate Tasks (standby)
        ↓
   RDS PostgreSQL db.t3.micro (private subnet, single-AZ)
```

## Technology Decisions

| Component | Choice | Rationale |
|-----------|--------|-----------|
| **Compute** | ECS Fargate | No OS management, free tier coverage, industry standard for containers |
| **Load Balancer** | ALB | Required for blue-green (2 target groups), health checks, TLS termination |
| **Database** | RDS PostgreSQL | Managed backups, free tier 750 hours/month (single-AZ) |
| **IaC** | Terraform | Industry standard, module reusability, state management |
| **CI/CD** | GitHub Actions | Free for public repos, OIDC integration with AWS (no long-lived credentials) |
| **Secrets** | SSM Parameter Store | Free tier, sufficient for this use case (vs Secrets Manager $0.40/secret) |
| **Networking** | Public subnets for ECS | Cost optimization (no NAT charges), security via security groups |

## Network Design

### VPC Layout
- **CIDR**: 10.0.0.0/16
- **Public Subnets**: 
  - 10.0.1.0/24 (us-east-1a) — ALB, ECS tasks
  - 10.0.2.0/24 (us-east-1b) — ALB, ECS tasks
- **Private Subnets**: 
  - 10.0.11.0/24 (us-east-1a) — RDS
  - 10.0.12.0/24 (us-east-1b) — Reserved for multi-AZ RDS

### Security Group Rules

**ALB Security Group**:
- Inbound: 443 from 0.0.0.0/0 (HTTPS)
- Outbound: 8000 to ECS task security group

**ECS Task Security Group**:
- Inbound: 8000 from ALB security group only
- Outbound: 5432 to RDS security group, 443 to 0.0.0.0/0 (AWS APIs)

**RDS Security Group**:
- Inbound: 5432 from ECS task security group only
- Outbound: None

## Deployment Strategy

### Blue-Green Process
1. New tasks deployed to "Green" target group
2. Health checks run for 2 minutes (deregistration_delay)
3. If healthy: ALB switches traffic to Green
4. If unhealthy: Deployment fails, traffic stays on Blue
5. Old Blue tasks drained and terminated

### Rollback Triggers
- Task health check failures (3 consecutive)
- 5xx error rate > 5% (CloudWatch alarm)
- Manual rollback via GitHub Actions workflow

## Cost Analysis

| Resource | Monthly Cost | Optimization Applied |
|----------|--------------|----------------------|
| ALB | $16.00 | None (required for blue-green) |
| Route 53 | $0.50 | Minimal zone cost |
| ECS Fargate | $0.00 | Free tier: 400 vCPU-hours |
| RDS db.t3.micro | $0.00 | Free tier: 750 hours (single-AZ) |
| CloudWatch Logs | $0.00 | Free tier: 5GB ingestion |
| **Total** | **$16.50/month** | |

**1-week project cost**: ~$3.90

## Production Deviations (Documented Trade-offs)

| Aspect | This Project | Production Standard |
|--------|--------------|---------------------|
| **ECS Subnets** | Public | Private with NAT Gateway |
| **RDS** | Single-AZ | Multi-AZ for HA |
| **Secrets** | SSM Parameter Store | AWS Secrets Manager with rotation |
| **Monitoring** | CloudWatch only | + Datadog/New Relic |
| **Backups** | AWS automated | + cross-region replication |

### Rationale for Public Subnet ECS Tasks

**Decision**: Deploy Fargate tasks to public subnets instead of private subnets with NAT.

**Why**:
- NAT Gateway costs $33/month, exceeding project budget
- NAT Instance requires additional management overhead
- Security groups still enforce network isolation (tasks only accept ALB traffic)
- RDS remains in private subnet with no public access

**Security measures maintained**:
- ALB is only entry point (port 443 only)
- Tasks cannot be accessed directly from internet
- RDS security group only allows connections from task security group
- All secrets stored in SSM, never in code

**Production recommendation**: Use private subnets with NAT Gateway for defense-in-depth.

## Compliance Checklist

- [x] No hardcoded credentials (IAM roles only)
- [x] TLS encryption in transit (ACM certificate)
- [x] Encryption at rest (RDS default encryption)
- [x] Least privilege IAM policies
- [x] CloudWatch logging for all services
- [x] Automated deployment with rollback capability
- [x] Infrastructure as code (100% Terraform)

---
**Version**: 1.0  
**Last Updated**: 2025-02-16  
**Author**: Suleiman
