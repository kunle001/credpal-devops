locals {
  name_prefix = "credpal-staging"
}

module "vpc" {
  source      = "../../modules/vpc"
  name_prefix = local.name_prefix
  vpc_cidr    = var.vpc_cidr
  az_count    = 2
}

module "security_groups" {
  source      = "../../modules/security-groups"
  name_prefix = local.name_prefix
  vpc_id      = module.vpc.vpc_id
  app_port    = var.app_port
}

module "alb" {
  source                     = "../../modules/alb"
  name_prefix                = local.name_prefix
  vpc_id                     = module.vpc.vpc_id
  public_subnet_ids          = module.vpc.public_subnet_ids
  alb_sg_id                  = module.security_groups.alb_sg_id
  app_port                   = var.app_port
  domain_name                = var.domain_name
  route53_zone_id            = var.route53_zone_id
  enable_deletion_protection = false
  enable_waf                 = false  # WAF skipped on staging to save cost
}

module "rds" {
  source             = "../../modules/rds"
  name_prefix        = local.name_prefix
  private_subnet_ids = module.vpc.private_subnet_ids
  rds_sg_id          = module.security_groups.rds_sg_id
  db_name            = var.db_name
  db_username        = var.db_username
  db_password        = var.db_password
  instance_class     = "db.t3.micro"
  backup_retention_days      = 1
  multi_az                   = false
  enable_deletion_protection = false
}

module "ecs" {
  source                  = "../../modules/ecs"
  name_prefix             = local.name_prefix
  environment             = "staging"
  aws_region              = var.aws_region
  vpc_id                  = module.vpc.vpc_id
  private_subnet_ids      = module.vpc.private_subnet_ids
  ecs_sg_id               = module.security_groups.ecs_sg_id
  target_group_arn        = module.alb.target_group_arn
  alb_arn_suffix          = module.alb.alb_arn
  target_group_arn_suffix = module.alb.target_group_arn
  app_image               = var.app_image
  app_port                = var.app_port
  fargate_cpu             = 256
  fargate_memory          = 512
  desired_count           = 1
  min_capacity            = 1
  max_capacity            = 3
  db_host                 = module.rds.db_endpoint
  db_port                 = module.rds.db_port
  db_name                 = module.rds.db_name
  db_username             = var.db_username
  db_password             = var.db_password
  log_retention_days      = 7
  alarm_email             = var.alarm_email
}

# ─── GitHub Actions OIDC (one per AWS account – import if it already exists) ─

resource "aws_iam_openid_connect_provider" "github" {
  url             = "https://token.actions.githubusercontent.com"
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = ["6938fd4d98bab03faadb97b34396831e3780aea1"]
}

resource "aws_iam_role" "github_actions" {
  name = "${local.name_prefix}-github-actions"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Federated = aws_iam_openid_connect_provider.github.arn
      }
      Action = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringLike = {
          "token.actions.githubusercontent.com:sub" = "repo:${var.github_repo}:*"
        }
        StringEquals = {
          "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
        }
      }
    }]
  })
}

# ─── Pipeline credentials secret ─────────────────────────────────────────────
# Stores DB credentials that CI/CD fetches at runtime via OIDC.
# No secrets live in GitHub – only this AWS SM secret and role ARNs (non-sensitive).

resource "aws_secretsmanager_secret" "pipeline" {
  name                    = "${local.name_prefix}/pipeline"
  description             = "CI/CD pipeline credentials for ${local.name_prefix}"
  recovery_window_in_days = 7
  tags                    = { Name = "${local.name_prefix}-pipeline-secret" }
}

resource "aws_secretsmanager_secret_version" "pipeline" {
  secret_id = aws_secretsmanager_secret.pipeline.id
  secret_string = jsonencode({
    DB_USERNAME = var.db_username
    DB_PASSWORD = var.db_password
  })
}

resource "aws_iam_role_policy" "github_actions_deploy" {
  name = "${local.name_prefix}-deploy-policy"
  role = aws_iam_role.github_actions.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      # ECS deployments
      {
        Effect = "Allow"
        Action = [
          "ecs:UpdateService",
          "ecs:RegisterTaskDefinition",
          "ecs:DescribeTaskDefinition",
          "ecs:DescribeServices"
        ]
        Resource = "*"
      },
      # Pass the ECS task role to the task definition
      {
        Effect   = "Allow"
        Action   = ["iam:PassRole"]
        Resource = module.ecs.task_role_arn
      },
      # Read pipeline credentials from Secrets Manager
      {
        Effect   = "Allow"
        Action   = ["secretsmanager:GetSecretValue"]
        Resource = aws_secretsmanager_secret.pipeline.arn
      },
      # Terraform remote state – S3
      {
        Effect = "Allow"
        Action = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject", "s3:ListBucket"]
        Resource = [
          "arn:aws:s3:::credpal-terraform-state",
          "arn:aws:s3:::credpal-terraform-state/staging/*"
        ]
      },
      # Terraform remote state – DynamoDB lock
      {
        Effect   = "Allow"
        Action   = ["dynamodb:GetItem", "dynamodb:PutItem", "dynamodb:DeleteItem"]
        Resource = "arn:aws:dynamodb:${var.aws_region}:*:table/credpal-terraform-locks"
      }
    ]
  })
}
