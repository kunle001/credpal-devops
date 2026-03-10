output "alb_dns_name" {
  value = module.alb.alb_dns_name
}

output "app_url" {
  value = "https://${var.domain_name}"
}

output "ecs_cluster" {
  value = module.ecs.cluster_name
}

output "ecs_service" {
  value = module.ecs.service_name
}

output "log_group" {
  value = module.ecs.log_group_name
}

output "pipeline_secret_name" {
  description = "Set this as GitHub Variable STAGING_PIPELINE_SECRET"
  value       = aws_secretsmanager_secret.pipeline.name
}

output "github_actions_role_arn" {
  description = "Set this as GitHub Variable AWS_STAGING_DEPLOY_ROLE_ARN"
  value       = aws_iam_role.github_actions.arn
}
