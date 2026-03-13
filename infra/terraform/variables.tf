variable "aws_region" {
  description = "AWS region for provider and deployment."
  type        = string
  default     = "ap-northeast-1"
}

variable "github_owner" {
  description = "GitHub organization/user name."
  type        = string
  default     = "cns-taniyama"
}

variable "github_repository" {
  description = "GitHub repository name."
  type        = string
  default     = "taniawsdeploy"
}

variable "github_branch" {
  description = "Git branch that can assume the deploy role."
  type        = string
  default     = "main"
}

variable "github_subject_claims" {
  description = "Override GitHub OIDC sub claims. Empty list uses main branch default."
  type        = list(string)
  default     = []
}

variable "allowed_audiences" {
  description = "OIDC audiences allowed in token.actions.githubusercontent.com token."
  type        = list(string)
  default     = ["sts.amazonaws.com"]
}

variable "iam_role_name" {
  description = "IAM role name assumed from GitHub Actions."
  type        = string
  default     = "gha-taniawsdeploy-deploy"
}

variable "attach_administrator_access" {
  description = "Attach AWS managed AdministratorAccess policy."
  type        = bool
  default     = true
}

variable "additional_policy_arns" {
  description = "Additional IAM policy ARNs to attach."
  type        = list(string)
  default     = []
}

variable "create_github_oidc_provider" {
  description = "Create GitHub OIDC provider in IAM."
  type        = bool
  default     = true
}

variable "existing_github_oidc_provider_arn" {
  description = "Existing GitHub OIDC provider ARN (required when create_github_oidc_provider=false)."
  type        = string
  default     = null

  validation {
    condition     = var.create_github_oidc_provider || var.existing_github_oidc_provider_arn != null
    error_message = "existing_github_oidc_provider_arn must be set when create_github_oidc_provider is false."
  }
}

variable "ec2_instance_type" {
  description = "EC2 instance type for the web server."
  type        = string
  default     = "t3.micro"
}

variable "ec2_name" {
  description = "Name tag for EC2 instance."
  type        = string
  default     = "taniawsdeploy-web"
}

variable "ec2_key_name" {
  description = "Optional EC2 key pair name for SSH access."
  type        = string
  default     = null
}

variable "http_ingress_cidrs" {
  description = "CIDRs allowed to access HTTP(80) on EC2."
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "artifact_bucket_name" {
  description = "Optional pre-defined bucket name for deployment artifacts."
  type        = string
  default     = null
}

variable "artifact_bucket_force_destroy" {
  description = "Allow Terraform to delete a non-empty artifact bucket on destroy."
  type        = bool
  default     = false
}
