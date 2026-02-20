# Data source for AWS account ID
data "aws_caller_identity" "current" {}

# Networking Module
module "networking" {
  source = "../../modules/networking"

  project_name       = var.project_name
  vpc_cidr           = var.vpc_cidr
  availability_zones = var.availability_zones
}

# IAM Module
module "iam" {
  source = "../../modules/iam"

  project_name   = var.project_name
  aws_region     = var.aws_region
  aws_account_id = data.aws_caller_identity.current.account_id
}

# ACM Certificate (for HTTPS)
resource "aws_acm_certificate" "main" {
  domain_name               = var.domain_name
  subject_alternative_names = ["*.${var.domain_name}"]
  validation_method         = "DNS"

  lifecycle {
    create_before_destroy = true
  }

  tags = {
    Name = "${var.project_name}-cert"
  }
}

# ACM Certificate Validation Records
resource "aws_route53_record" "cert_validation" {
  for_each = {
    for dvo in aws_acm_certificate.main.domain_validation_options : dvo.domain_name => {
      name   = dvo.resource_record_name
      record = dvo.resource_record_value
      type   = dvo.resource_record_type
    }
  }

  allow_overwrite = true
  name            = each.value.name
  records         = [each.value.record]
  ttl             = 60
  type            = each.value.type
  zone_id         = data.aws_route53_zone.main.zone_id
}

# Data source for Route 53 hosted zone
data "aws_route53_zone" "main" {
  name         = var.domain_name
  private_zone = false
}

# Wait for certificate validation
resource "aws_acm_certificate_validation" "main" {
  certificate_arn         = aws_acm_certificate.main.arn
  validation_record_fqdns = [for record in aws_route53_record.cert_validation : record.fqdn]
}

# ALB Module
module "alb" {
  source = "../../modules/alb"

  project_name          = var.project_name
  vpc_id                = module.networking.vpc_id
  public_subnet_ids     = module.networking.public_subnet_ids
  alb_security_group_id = module.networking.alb_security_group_id
  acm_certificate_arn   = aws_acm_certificate.main.arn

  depends_on = [aws_acm_certificate_validation.main]
}

# ECS Module
module "ecs" {
  source = "../../modules/ecs"

  project_name                = var.project_name
  aws_region                  = var.aws_region
  container_image             = var.container_image
  container_image_green       = var.container_image_green
  ecs_task_execution_role_arn = module.iam.ecs_task_execution_role_arn
  ecs_task_role_arn           = module.iam.ecs_task_role_arn
  public_subnet_ids           = module.networking.public_subnet_ids
  ecs_security_group_id       = module.networking.ecs_tasks_security_group_id
  target_group_arn            = module.alb.blue_target_group_arn
  green_target_group_arn      = module.alb.green_target_group_arn
  alb_listener_arn            = module.alb.https_listener_arn
  
 
  # Real database configuration
  db_host               = module.rds.db_address
  db_name               = var.db_name
  db_user               = var.db_username
  db_password_ssm_param = "/ecs-prod/db/password"

  depends_on = [module.rds]
}

# Route 53 Record for ALB
resource "aws_route53_record" "app" {
  zone_id = data.aws_route53_zone.main.zone_id
  name    = "app.${var.domain_name}"
  type    = "A"

  alias {
    name                   = module.alb.alb_dns_name
    zone_id                = module.alb.alb_zone_id
    evaluate_target_health = true
  }
}

# RDS Module
module "rds" {
  source = "../../modules/rds"

  project_name          = var.project_name
  db_name               = var.db_name
  db_username           = var.db_username
  db_password           = var.db_password
  db_subnet_group_name  = module.networking.db_subnet_group_name
  rds_security_group_id = module.networking.rds_security_group_id
}