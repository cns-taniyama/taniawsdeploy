output "github_actions_role_arn" {
  description = "IAM role ARN to set in GitHub Actions variable AWS_ROLE_ARN."
  value       = aws_iam_role.github_actions_deploy.arn
}

output "github_oidc_provider_arn" {
  description = "GitHub OIDC provider ARN used in trust relationship."
  value       = local.github_oidc_provider_arn
}
