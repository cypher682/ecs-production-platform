output "vpc_id" {
  description = "VPC ID"
  value       = module.networking.vpc_id
}

output "public_subnet_ids" {
  description = "Public subnet IDs"
  value       = module.networking.public_subnet_ids
}

output "private_subnet_ids" {
  description = "Private subnet IDs"
  value       = module.networking.private_subnet_ids
}

output "alb_security_group_id" {
  description = "ALB security group ID"
  value       = module.networking.alb_security_group_id
}

output "ecs_tasks_security_group_id" {
  description = "ECS tasks security group ID"
  value       = module.networking.ecs_tasks_security_group_id
}

output "rds_security_group_id" {
  description = "RDS security group ID"
  value       = module.networking.rds_security_group_id
}

output "ecs_task_execution_role_arn" {
  description = "ECS task execution role ARN"
  value       = module.iam.ecs_task_execution_role_arn
}

output "ecs_task_role_arn" {
  description = "ECS task role ARN"
  value       = module.iam.ecs_task_role_arn
}

output "acm_certificate_arn" {
  description = "ACM certificate ARN"
  value       = aws_acm_certificate.main.arn
}

output "route53_zone_id" {
  description = "Route 53 hosted zone ID"
  value       = data.aws_route53_zone.main.zone_id
}
output "alb_dns_name" {
  description = "ALB DNS name"
  value       = module.alb.alb_dns_name
}

output "app_url" {
  description = "Application URL"
  value       = "https://app.${var.domain_name}"
}

output "ecs_cluster_name" {
  description = "ECS cluster name"
  value       = module.ecs.cluster_name
}

output "ecs_service_name" {
  description = "ECS service name"
  value       = module.ecs.service_name
}
output "db_endpoint" {
  description = "RDS endpoint"
  value       = module.rds.db_endpoint
  sensitive   = true
}

output "db_address" {
  description = "RDS hostname"
  value       = module.rds.db_address
}

output "db_name" {
  description = "Database name"
  value       = module.rds.db_name
}