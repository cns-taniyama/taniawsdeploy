output "github_actions_role_arn" {
  description = "IAM role ARN to set in GitHub Actions variable AWS_ROLE_ARN."
  value       = aws_iam_role.github_actions_deploy.arn
}

output "github_oidc_provider_arn" {
  description = "GitHub OIDC provider ARN used in trust relationship."
  value       = local.github_oidc_provider_arn
}

output "ec2_instance_id" {
  description = "EC2 instance ID used by GitHub Actions deployment."
  value       = aws_instance.web.id
}

output "ec2_public_ip" {
  description = "Public IP of EC2 web server."
  value       = aws_instance.web.public_ip
}

output "deploy_artifact_bucket" {
  description = "S3 bucket used to store deployment artifacts."
  value       = aws_s3_bucket.artifacts.bucket
}
