variable "project_name" {
  description = "Project name for resource naming"
  type        = string
}

variable "db_name" {
  description = "Database name"
  type        = string
  default     = "app_db"
}

variable "db_username" {
  description = "Database master username"
  type        = string
  default     = "app_user"
}

variable "db_password" {
  description = "Database master password"
  type        = string
  sensitive   = true
}

variable "db_subnet_group_name" {
  description = "DB subnet group name"
  type        = string
}

variable "rds_security_group_id" {
  description = "RDS security group ID"
  type        = string
}