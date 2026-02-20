variable "project_name" {
  description = "Project name used for resource naming"
  type        = string
}

variable "github_repo" {
  description = "GitHub repository in owner/repo format (e.g. cypher682/ecs-production-platform)"
  type        = string
  default     = "cypher682/ecs-production-platform"
}

variable "ecr_repository_arn" {
  description = "ARN of the ECR repository the deployment role is allowed to push to"
  type        = string
}

variable "ecs_task_execution_role_arn" {
  description = "ARN of the ECS task execution role (needed for iam:PassRole)"
  type        = string
}

variable "ecs_task_role_arn" {
  description = "ARN of the ECS task role (needed for iam:PassRole)"
  type        = string
}
