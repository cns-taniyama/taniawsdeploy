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
