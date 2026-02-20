# ============================================================
# CI/CD IAM Module — Reference Only, Not Applied
# ============================================================
# This module provisions the IAM OIDC provider and deployment
# role for GitHub Actions. It is NOT wired into prod/main.tf.
#
# To apply:
#   1. Add module block to terraform/environments/prod/main.tf
#   2. Pass ecr_repository_arn, ecs_task_execution_role_arn,
#      ecs_task_role_arn from existing module outputs
#   3. Run terraform apply
#   4. Use output github_actions_role_arn in deploy.yml
# ============================================================

resource "aws_iam_openid_connect_provider" "github" {
  url = "https://token.actions.githubusercontent.com"

  client_id_list = [
    "sts.amazonaws.com",
  ]

  # Thumbprint for token.actions.githubusercontent.com
  # See: https://docs.aws.amazon.com/IAM/latest/UserGuide/id_roles_providers_create_oidc_verify-thumbprint.html
  thumbprint_list = [
    "6938fd4d98bab03faadb97b34396831e3780aea1"
  ]

  tags = {
    Name    = "${var.project_name}-github-oidc-provider"
    Project = var.project_name
  }
}

resource "aws_iam_role" "github_actions" {
  name        = "${var.project_name}-github-actions-deploy"
  description = "IAM role assumed by GitHub Actions via OIDC for ECS deployments"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Federated = aws_iam_openid_connect_provider.github.arn
      }
      Action = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
          # Restrict to main branch of specific repo only
          "token.actions.githubusercontent.com:sub" = "repo:${var.github_repo}:ref:refs/heads/main"
        }
      }
    }]
  })

  tags = {
    Name    = "${var.project_name}-github-deploy-role"
    Project = var.project_name
  }
}

# ECR — allow pushing images
resource "aws_iam_role_policy" "ecr_push" {
  name = "${var.project_name}-ecr-push"
  role = aws_iam_role.github_actions.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        # GetAuthorizationToken requires * — AWS limitation
        Effect   = "Allow"
        Action   = ["ecr:GetAuthorizationToken"]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "ecr:BatchCheckLayerAvailability",
          "ecr:GetDownloadUrlForLayer",
          "ecr:BatchGetImage",
          "ecr:PutImage",
          "ecr:InitiateLayerUpload",
          "ecr:UploadLayerPart",
          "ecr:CompleteLayerUpload",
        ]
        Resource = var.ecr_repository_arn
      }
    ]
  })
}

# ECS — allow updating services and task definitions
resource "aws_iam_role_policy" "ecs_deploy" {
  name = "${var.project_name}-ecs-deploy"
  role = aws_iam_role.github_actions.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ecs:DescribeServices",
          "ecs:DescribeTaskDefinition",
          "ecs:RegisterTaskDefinition",
          "ecs:UpdateService",
          "ecs:ListTasks",
          "ecs:DescribeTasks",
        ]
        Resource = "*"
      },
      {
        # PassRole required so GitHub Actions can attach the
        # task execution and task roles to new task definitions
        Effect = "Allow"
        Action = ["iam:PassRole"]
        Resource = [
          var.ecs_task_execution_role_arn,
          var.ecs_task_role_arn,
        ]
      }
    ]
  })
}
