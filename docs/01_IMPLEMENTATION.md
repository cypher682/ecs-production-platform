# Implementation Log

## Phase 1: Core Infrastructure ✅ COMPLETED
**Date**: 2026-02-16  
**Duration**: 90 seconds deployment time  
**Cost**: $0 (free tier resources only)

### What Was Built

#### Networking
- **VPC**: 10.0.0.0/16 (`vpc-0d2a268b450bd99b0`)
- **Public Subnets**:
  - 10.0.0.0/24 in us-east-1a (`subnet-0cb9b9135533a98e8`)
  - 10.0.1.0/24 in us-east-1b (`subnet-0f03d9302f0d6471e`)
- **Private Subnets**:
  - 10.0.10.0/24 in us-east-1a (`subnet-00c0c46774db560b2`)
  - 10.0.11.0/24 in us-east-1b (`subnet-0762d5bcc2722cf27`)
- **Internet Gateway**: `igw-0418a46a2cd409aae`
- **Route Table**: Public subnets route 0.0.0.0/0 to IGW

#### Security Groups (Least Privilege)
- **ALB SG** (`sg-0373513dd33d30ddb`):
  - Inbound: 443, 80 from internet
  - Outbound: All traffic
- **ECS Tasks SG** (`sg-09a3082e31d282821`):
  - Inbound: 8000 from ALB SG only
  - Outbound: All traffic (for RDS, AWS APIs)
- **RDS SG** (`sg-07a5aae1f94e3e9e2`):
  - Inbound: 5432 from ECS SG only
  - Outbound: None

#### IAM Roles (Separation of Concerns)
- **Task Execution Role**: Can pull images, write logs, read SSM secrets
- **Task Role**: Application permissions (read SSM parameters)

#### TLS Certificate
- **Domain**: `cipherpol.xyz`, `*.cipherpol.xyz`
- **Validation**: DNS (automatic via Route 53)
- **Status**: Issued in 2 seconds
- **ARN**: `arn:aws:acm:us-east-1:758620460011:certificate/3a9c9807-389b-46ba-aca0-35733af32651`

### Issues Encountered

**Issue 1: Terraform Backend Warning**
```
Warning: Deprecated Parameter
The parameter "dynamodb_table" is deprecated. Use parameter "use_lockfile" instead.
```
**Impact**: None (warning only, state locking works correctly)  
**Fix**: This is a Terraform 1.14.0 deprecation notice. For now, it's functional. In future, will update `backend.tf` to use `use_lockfile = true`.

**Issue 2: None** — Deployment was clean! 🎉

### Key Learnings

1. **ACM + Route 53 Integration**: Certificate validation was instant because DNS is in Route 53. In other scenarios (external DNS), validation can take 30+ minutes.

2. **Security Group Dependencies**: Terraform handled the circular dependency (ALB SG → ECS SG → RDS SG) automatically using `create_before_destroy`.

3. **CIDR Planning**: Used `/24` subnets (256 IPs each). Public subnets start at `.0`, private at `.10` for clear separation.

4. **Free Tier Usage**: Zero cost so far. VPC, subnets, security groups, IAM roles, and Route 53 validation records are all free.

### Evidence
- [VPC Overview](evidence/01-vpc-overview.png)
- [Subnets](evidence/02-subnets.png)
- [Security Groups](evidence/04-security-groups.png)
- [IAM Roles](evidence/08-iam-roles.png)
- [ACM Certificate](evidence/10-acm-certificate.png)
- [Terraform Outputs](evidence/terraform-outputs-phase1.txt)

### Production Deviations
None yet — this is exactly how I'd deploy in production.

---

## Next: Phase 2 (ECS + ALB)
Will add:
- Application Load Balancer with 2 target groups (blue/green)
- ECS Fargate cluster
- Sample Flask application deployment
- CloudWatch log groups

**Expected cost**: ~$0.20 for 4-hour testing window