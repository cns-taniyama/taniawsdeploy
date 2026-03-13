provider "aws" {
  region = var.aws_region
}

data "aws_caller_identity" "current" {}

data "aws_vpc" "default" {
  default = true
}

data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }

  filter {
    name   = "default-for-az"
    values = ["true"]
  }
}

data "aws_ssm_parameter" "al2023_ami" {
  name = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64"
}

locals {
  default_subject   = "repo:${var.github_owner}/${var.github_repository}:ref:refs/heads/${var.github_branch}"
  subject_claims    = length(var.github_subject_claims) > 0 ? var.github_subject_claims : [local.default_subject]
  default_subnet_id = sort(data.aws_subnets.default.ids)[0]
  artifact_bucket_name = var.artifact_bucket_name != null && var.artifact_bucket_name != "" ? var.artifact_bucket_name : lower(
    "${var.github_repository}-deploy-${data.aws_caller_identity.current.account_id}-${var.aws_region}"
  )
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

resource "aws_s3_bucket" "artifacts" {
  bucket        = local.artifact_bucket_name
  force_destroy = var.artifact_bucket_force_destroy
}

resource "aws_s3_bucket_versioning" "artifacts" {
  bucket = aws_s3_bucket.artifacts.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "artifacts" {
  bucket = aws_s3_bucket.artifacts.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "artifacts" {
  bucket = aws_s3_bucket.artifacts.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

data "aws_iam_policy_document" "assume_from_ec2" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "ec2" {
  name               = "${var.github_repository}-ec2-role"
  assume_role_policy = data.aws_iam_policy_document.assume_from_ec2.json
}

resource "aws_iam_role_policy_attachment" "ec2_ssm_core" {
  role       = aws_iam_role.ec2.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

data "aws_iam_policy_document" "ec2_artifact_read" {
  statement {
    actions   = ["s3:ListBucket"]
    resources = [aws_s3_bucket.artifacts.arn]
  }

  statement {
    actions   = ["s3:GetObject"]
    resources = ["${aws_s3_bucket.artifacts.arn}/*"]
  }
}

resource "aws_iam_role_policy" "ec2_artifact_read" {
  name   = "${var.github_repository}-ec2-artifact-read"
  role   = aws_iam_role.ec2.id
  policy = data.aws_iam_policy_document.ec2_artifact_read.json
}

resource "aws_iam_instance_profile" "ec2" {
  name = "${var.github_repository}-ec2-profile"
  role = aws_iam_role.ec2.name
}

resource "aws_security_group" "web" {
  name        = "${var.github_repository}-web-sg"
  description = "Allow HTTP access to taniawsdeploy web server"
  vpc_id      = data.aws_vpc.default.id

  ingress {
    description = "HTTP"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = var.http_ingress_cidrs
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_instance" "web" {
  ami                         = data.aws_ssm_parameter.al2023_ami.value
  instance_type               = var.ec2_instance_type
  subnet_id                   = local.default_subnet_id
  vpc_security_group_ids      = [aws_security_group.web.id]
  iam_instance_profile        = aws_iam_instance_profile.ec2.name
  associate_public_ip_address = true
  key_name                    = var.ec2_key_name

  user_data = <<-EOF
    #!/bin/bash
    set -e
    dnf -y update
    dnf -y install httpd php unzip
    systemctl enable --now amazon-ssm-agent || true
    systemctl enable --now httpd
    mkdir -p /var/www/html
    echo "<?php phpinfo(); ?>" > /var/www/html/index.php
    chown -R apache:apache /var/www/html
  EOF

  tags = {
    Name = var.ec2_name
  }
}
