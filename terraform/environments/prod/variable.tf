variable "aws_region" {
    description = "AWS region for resources"
    type = string
    default = "us-east-1"
  
}

variable "project_name" {
    description = "Project name for resource"
    type = string
    default = "ecs-prod"
  
}

variable "vpc_cidr" {
    description = "CIDR block for vpc"
    type = string
    default = "10.0.0.0/16"
  
}

variable "domain_name" {
    description = "Domain name for ACM Certificate"
    type = string
    default = "cipherpol.xyz"
}

variable "availability_zones" {
    description = "Availability zones"
    type = list(string)
    default = [ "us-east-1a", "us-east-1b" ]
  
}
variable "container_image" {
  description = "Docker image for ECS task"
  type        = string
  default     = "758620460011.dkr.ecr.us-east-1.amazonaws.com/ecs-prod/flask-app:latest"
}
variable "db_name" {
  description = "Database name"
  type        = string
  default     = "app_db"
}

variable "db_username" {
  description = "Database username"
  type        = string
  default     = "app_user"
}

variable "db_password" {
  description = "Database password (from SSM)"
  type        = string
  sensitive   = true
}
variable "container_image_green" {
  description = "Docker image for green deployment"
  type        = string
  default     = "758620460011.dkr.ecr.us-east-1.amazonaws.com/ecs-prod/flask-app:green"
}