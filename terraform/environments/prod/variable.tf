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