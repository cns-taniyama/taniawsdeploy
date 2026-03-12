provider "aws" {
  region = var.aws_region
}

locals {
  default_subject = "repo:${var.github_owner}/${var.github_repository}:ref:refs/heads/${var.github_branch}"
  subject_claims  = length(var.github_subject_claims) > 0 ? var.github_subject_claims : [local.default_subject]
}

resource "aws_iam_openid_connect_provider" "github" {
  count = var.create_github_oidc_provider ? 1 : 0

  url             = "https://token.actions.githubusercontent.com"
  client_id_list  = var.allowed_audiences
  thumbprint_list = ["6938fd4d98bab03faadb97b34396831e3780aea1"]
}

locals {
  github_oidc_provider_arn = var.create_github_oidc_provider ? aws_iam_openid_connect_provider.github[0].arn : var.existing_github_oidc_provider_arn
}

data "aws_iam_policy_document" "assume_from_github" {
  statement {
    sid     = "AllowGitHubOidcAssumeRole"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [local.github_oidc_provider_arn]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = var.allowed_audiences
    }

    condition {
      test     = "StringLike"
      variable = "token.actions.githubusercontent.com:sub"
      values   = local.subject_claims
    }
  }
}

resource "aws_iam_role" "github_actions_deploy" {
  name               = var.iam_role_name
  assume_role_policy = data.aws_iam_policy_document.assume_from_github.json
}

resource "aws_iam_role_policy_attachment" "administrator_access" {
  count = var.attach_administrator_access ? 1 : 0

  role       = aws_iam_role.github_actions_deploy.name
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
}

resource "aws_iam_role_policy_attachment" "additional" {
  for_each = toset(var.additional_policy_arns)

  role       = aws_iam_role.github_actions_deploy.name
  policy_arn = each.value
}
