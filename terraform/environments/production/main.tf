locals {
  name_prefix = "credpal-production"
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
  enable_deletion_protection = true
  enable_waf                 = true
}

module "rds" {
  source                     = "../../modules/rds"
  name_prefix                = local.name_prefix
  private_subnet_ids         = module.vpc.private_subnet_ids
  rds_sg_id                  = module.security_groups.rds_sg_id
  db_name                    = var.db_name
  db_username                = var.db_username
  db_password                = var.db_password
  instance_class             = "db.t3.small"
  backup_retention_days      = 7
  multi_az                   = true
  enable_deletion_protection = true
}

module "ecs" {
  source                  = "../../modules/ecs"
  name_prefix             = local.name_prefix
  environment             = "production"
  aws_region              = var.aws_region
  vpc_id                  = module.vpc.vpc_id
  private_subnet_ids      = module.vpc.private_subnet_ids
  ecs_sg_id               = module.security_groups.ecs_sg_id
  target_group_arn        = module.alb.target_group_arn
  alb_arn_suffix          = module.alb.alb_arn
  target_group_arn_suffix = module.alb.target_group_arn
  app_image               = var.app_image
  app_port                = var.app_port
  fargate_cpu             = 512
  fargate_memory          = 1024
  desired_count           = 2
  min_capacity            = 2
  max_capacity            = 10
  db_host                 = module.rds.db_endpoint
  db_port                 = module.rds.db_port
  db_name                 = module.rds.db_name
  db_username             = var.db_username
  db_password             = var.db_password
  log_retention_days      = 30
  alarm_email             = var.alarm_email
  ghcr_secret_arn         = "arn:aws:secretsmanager:us-east-1:517818188528:secret:credpal/ghcr-pull-credentials"
}

# ─── GitHub Actions OIDC ──────────────────────────────────────────────────────
# The OIDC provider is account-scoped (one per URL) so staging creates it.
# Production references it via a data source to avoid a duplicate error.

data "aws_iam_openid_connect_provider" "github" {
  url = "https://token.actions.githubusercontent.com"
}

resource "aws_iam_role" "github_actions" {
  name = "${local.name_prefix}-github-actions"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Federated = data.aws_iam_openid_connect_provider.github.arn
      }
      Action = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        # Allow production environment jobs (approval-gated) and main-branch jobs
        StringLike = {
          "token.actions.githubusercontent.com:sub" = [
            "repo:${var.github_repo}:environment:production",
            "repo:${var.github_repo}:ref:refs/heads/main"
          ]
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
      # Read-only access across all services – required for Terraform state refresh
      # (Describe*, List*, Get* operations needed to read existing resources)
      {
        Effect = "Allow"
        Action = [
          "ec2:Describe*", "ec2:Get*",
          "elasticloadbalancing:Describe*",
          "acm:Describe*", "acm:List*", "acm:Get*",
          "wafv2:Describe*", "wafv2:List*", "wafv2:Get*", "wafv2:Check*",
          "route53:List*", "route53:Get*",
          "rds:Describe*", "rds:List*",
          "ecs:Describe*", "ecs:List*",
          "iam:Get*", "iam:List*",
          "secretsmanager:Describe*", "secretsmanager:List*", "secretsmanager:GetSecretValue",
          "logs:Describe*", "logs:List*",
          "cloudwatch:Describe*", "cloudwatch:List*", "cloudwatch:Get*",
          "sns:Get*", "sns:List*",
          "application-autoscaling:Describe*",
          "elasticloadbalancing:Describe*"
        ]
        Resource = "*"
      },
      # ECS – full management for deployments and Terraform
      {
        Effect   = "Allow"
        Action   = ["ecs:*"]
        Resource = "*"
      },
      # IAM – manage roles/policies scoped to this project, plus PassRole
      {
        Effect = "Allow"
        Action = [
          "iam:CreateRole", "iam:DeleteRole", "iam:GetRole", "iam:TagRole", "iam:UntagRole",
          "iam:UpdateRole", "iam:UpdateAssumeRolePolicy",
          "iam:PutRolePolicy", "iam:GetRolePolicy", "iam:DeleteRolePolicy",
          "iam:ListRolePolicies", "iam:ListAttachedRolePolicies",
          "iam:AttachRolePolicy", "iam:DetachRolePolicy",
          "iam:PassRole"
        ]
        Resource = "arn:aws:iam::*:role/credpal-*"
      },
      # IAM – OIDC provider read (data source lookup by URL)
      {
        Effect   = "Allow"
        Action   = ["iam:ListOpenIDConnectProviders", "iam:GetOpenIDConnectProvider"]
        Resource = "*"
      },
      # EC2 – VPC, subnets, SGs, routing, NAT, EIPs
      {
        Effect   = "Allow"
        Action   = ["ec2:*"]
        Resource = "*"
      },
      # ELB – ALB, target groups, listeners
      {
        Effect   = "Allow"
        Action   = ["elasticloadbalancing:*"]
        Resource = "*"
      },
      # ACM – certificates
      {
        Effect   = "Allow"
        Action   = ["acm:*"]
        Resource = "*"
      },
      # WAFv2
      {
        Effect   = "Allow"
        Action   = ["wafv2:*"]
        Resource = "*"
      },
      # Route53 – DNS records for ACM validation and ALB alias
      {
        Effect   = "Allow"
        Action   = ["route53:*"]
        Resource = "*"
      },
      # RDS
      {
        Effect   = "Allow"
        Action   = ["rds:*"]
        Resource = "*"
      },
      # Secrets Manager – full access for pipeline secret + db secret management
      {
        Effect   = "Allow"
        Action   = ["secretsmanager:*"]
        Resource = "arn:aws:secretsmanager:*:*:secret:credpal-*"
      },
      # CloudWatch Logs
      {
        Effect   = "Allow"
        Action   = ["logs:*"]
        Resource = "*"
      },
      # CloudWatch Alarms
      {
        Effect   = "Allow"
        Action   = ["cloudwatch:*"]
        Resource = "*"
      },
      # SNS – alarm topics
      {
        Effect   = "Allow"
        Action   = ["sns:*"]
        Resource = "*"
      },
      # Application Auto Scaling
      {
        Effect   = "Allow"
        Action   = ["application-autoscaling:*"]
        Resource = "*"
      },
      # Terraform remote state – S3
      {
        Effect = "Allow"
        Action = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject", "s3:ListBucket"]
        Resource = [
          "arn:aws:s3:::credpal-terraform-state-517818188528",
          "arn:aws:s3:::credpal-terraform-state-517818188528/production/*"
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
