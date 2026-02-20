variable "project_name" {
  description = "Project name"
  type        = string
}

variable "aws_region" {
  description = "AWS region"
  type        = string
}

variable "container_image" {
  description = "Docker image URL"
  type        = string
}

variable "ecs_task_execution_role_arn" {
  description = "ECS task execution role ARN"
  type        = string
}

variable "ecs_task_role_arn" {
  description = "ECS task role ARN"
  type        = string
}

variable "public_subnet_ids" {
  description = "Public subnet IDs"
  type        = list(string)
}

variable "ecs_security_group_id" {
  description = "ECS security group ID"
  type        = string
}

variable "target_group_arn" {
  description = "Target group ARN"
  type        = string
}

variable "alb_listener_arn" {
  description = "ALB listener ARN"
  type        = string
}

variable "db_host" {
  description = "Database host (will be set in Phase 3)"
  type        = string
  default     = "placeholder.rds.amazonaws.com"
}

variable "db_name" {
  description = "Database name"
  type        = string
  default     = "app_db"
}

variable "db_user" {
  description = "Database username"
  type        = string
  default     = "app_user"
}

variable "db_password_ssm_param" {
  description = "SSM parameter name for DB password"
  type        = string
  default     = "/ecs-prod/db/password"
}

variable "container_image_green" {
  description = "Docker image URL for green deployment"
  type        = string
  default     = ""
}

variable "green_target_group_arn" {
  description = "Green target group ARN"
  type        = string
  default     = ""
}