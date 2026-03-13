# -----------------------------------------------------------------------------
# AWS プロバイダ設定と共通参照情報
# -----------------------------------------------------------------------------
provider "aws" {
  region = var.aws_region
}
# Provider 認証情報は実行環境（AWS CLI プロファイル、環境変数、引受ロール）から取得します。
# コード内に固定アクセスキーは持ちません。

# アカウント情報を含む一意な命名に使います。
data "aws_caller_identity" "current" {}

# 初期構築を簡単にするため、default VPC / default subnet を利用します。
# 専用 VPC 構成へ移行する場合は、この data 参照を管理リソースへ置き換えます。
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
# SSM から AMI を取得し、リージョンごとの AMI 固定値ハードコードを避けます。

# 複数リソースで再利用する導出値です。
locals {
  # 既定の OIDC subject で「1 リポジトリ + 1 ブランチ」に引受元を限定します。
  # 形式: repo:<owner>/<repo>:ref:refs/heads/<branch>
  default_subject = "repo:${var.github_owner}/${var.github_repository}:ref:refs/heads/${var.github_branch}"
  # カスタム claim が指定されていればそれを優先し、未指定時は既定値を使います。
  subject_claims = length(var.github_subject_claims) > 0 ? var.github_subject_claims : [local.default_subject]
  # 単一 EC2 構成のため、default subnet の先頭を配置先として使います。
  default_subnet_id = sort(data.aws_subnets.default.ids)[0]
  db_identifier     = lower("${var.github_repository}-mysql")
  # S3 バケット名はグローバル一意のため、アカウントIDとリージョンを付与して衝突を減らします。
  artifact_bucket_name = var.artifact_bucket_name != null && var.artifact_bucket_name != "" ? var.artifact_bucket_name : lower(
    "${var.github_repository}-deploy-${data.aws_caller_identity.current.account_id}-${var.aws_region}"
  )
}

# -----------------------------------------------------------------------------
# GitHub OIDC 信頼設定と GitHub Actions 用デプロイロール
# -----------------------------------------------------------------------------
resource "aws_iam_openid_connect_provider" "github" {
  count = var.create_github_oidc_provider ? 1 : 0

  url             = "https://token.actions.githubusercontent.com"
  client_id_list  = var.allowed_audiences
  thumbprint_list = ["6938fd4d98bab03faadb97b34396831e3780aea1"]
}
# 既に同一アカウントに Provider がある場合は create=false にし、
# existing_github_oidc_provider_arn へ既存 ARN を渡して EntityAlreadyExists を回避します。

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
    # aud 条件でトークンの利用先が AWS STS であることを確認します。

    condition {
      test     = "StringLike"
      variable = "token.actions.githubusercontent.com:sub"
      values   = local.subject_claims
    }
    # sub 条件で、引受可能なリポジトリ/ブランチ/実行コンテキストを制限します。
  }
}

# GitHub Actions が OIDC で引き受ける IAM ロール本体です。
resource "aws_iam_role" "github_actions_deploy" {
  name               = var.iam_role_name
  assume_role_policy = data.aws_iam_policy_document.assume_from_github.json
}

resource "aws_iam_role_policy_attachment" "administrator_access" {
  count = var.attach_administrator_access ? 1 : 0

  role       = aws_iam_role.github_actions_deploy.name
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
}
# 初期構築優先の既定値です。本番では無効化し、
# S3 アップロード + SSM 実行など必要最小限の権限だけを付与してください。

resource "aws_iam_role_policy_attachment" "additional" {
  for_each = toset(var.additional_policy_arns)

  role       = aws_iam_role.github_actions_deploy.name
  policy_arn = each.value
}

# -----------------------------------------------------------------------------
# デプロイ成果物バケット（GitHub Actions が zip をアップロード）
# -----------------------------------------------------------------------------
resource "aws_s3_bucket" "artifacts" {
  bucket        = local.artifact_bucket_name
  force_destroy = var.artifact_bucket_force_destroy
}
# GitHub Actions が生成した配布 zip を保存します。
# force_destroy=false では terraform destroy 時に中身が残っていれば削除されません。

resource "aws_s3_bucket_versioning" "artifacts" {
  bucket = aws_s3_bucket.artifacts.id

  versioning_configuration {
    status = "Enabled"
  }
}
# バージョニングにより、配布物の差し戻し追跡性を確保します。

resource "aws_s3_bucket_server_side_encryption_configuration" "artifacts" {
  bucket = aws_s3_bucket.artifacts.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}
# SSE-S3（AES256）で保存時暗号化を有効化します（KMS 管理不要）。

resource "aws_s3_bucket_public_access_block" "artifacts" {
  bucket = aws_s3_bucket.artifacts.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}
# バケット公開を防ぐため、パブリックアクセス経路を明示的に遮断します。

# -----------------------------------------------------------------------------
# EC2 IAM ロールとインスタンスプロファイル
# -----------------------------------------------------------------------------
data "aws_iam_policy_document" "assume_from_ec2" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}
# EC2 インスタンスプロファイル用ロールの信頼ポリシーです。

resource "aws_iam_role" "ec2" {
  name               = "${var.github_repository}-ec2-role"
  assume_role_policy = data.aws_iam_policy_document.assume_from_ec2.json
}

resource "aws_iam_role_policy_attachment" "ec2_ssm_core" {
  role       = aws_iam_role.ec2.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}
# SSM Managed ポリシーにより、Session Manager 接続やコマンド実行を許可します。

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
# EC2 には成果物バケットの読み取りのみを許可します。
# 一覧取得とダウンロードは可能ですが、アップロード/更新/削除は不可です。

resource "aws_iam_role_policy" "ec2_artifact_read" {
  name   = "${var.github_repository}-ec2-artifact-read"
  role   = aws_iam_role.ec2.id
  policy = data.aws_iam_policy_document.ec2_artifact_read.json
}

resource "aws_iam_instance_profile" "ec2" {
  name = "${var.github_repository}-ec2-profile"
  role = aws_iam_role.ec2.name
}

# -----------------------------------------------------------------------------
# セキュリティグループ
# alb: インターネット -> ALB(80)
# app: ALB -> EC2(80)
# db : EC2 -> RDS(3306)
# web: SG 付け替え時の破壊的変更を避けるため残している旧 SG
# -----------------------------------------------------------------------------
resource "aws_security_group" "alb" {
  name        = "${var.github_repository}-alb-sg"
  description = "Allow HTTP access to ALB"
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

resource "aws_security_group" "app" {
  name        = "${var.github_repository}-app-sg"
  description = "Allow HTTP only from ALB"
  vpc_id      = data.aws_vpc.default.id

  ingress {
    description     = "HTTP from ALB"
    from_port       = 80
    to_port         = 80
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_security_group" "db" {
  name        = "${var.github_repository}-db-sg"
  description = "Allow MySQL only from EC2 app instances"
  vpc_id      = data.aws_vpc.default.id

  ingress {
    description     = "MySQL from app"
    from_port       = 3306
    to_port         = 3306
    protocol        = "tcp"
    security_groups = [aws_security_group.app.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
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
# 注記: aws_security_group.web は旧構成用で、現在 EC2 には未アタッチです。
# 既存環境での名前変更/削除による破壊的変更を避けるため残しています。

# EC2 ウェブノード。GitHub Actions から SSM 経由でアプリを配備します。
resource "aws_instance" "web" {
  ami                         = data.aws_ssm_parameter.al2023_ami.value
  instance_type               = var.ec2_instance_type
  subnet_id                   = local.default_subnet_id
  vpc_security_group_ids      = [aws_security_group.app.id]
  iam_instance_profile        = aws_iam_instance_profile.ec2.name
  associate_public_ip_address = true
  key_name                    = var.ec2_key_name

  user_data = <<-EOF
    #!/bin/bash
    set -e
    # 最小限の初期化のみ実施（Web 実行環境 + 配布 zip 展開に必要な unzip）。
    dnf -y update
    dnf -y install httpd php php-mysqlnd unzip
    # デプロイ経路は SSH ではなく SSM Agent を利用します。
    systemctl enable --now amazon-ssm-agent || true
    systemctl enable --now httpd
    mkdir -p /var/www/html
    # 初回デプロイ前でも ALB ヘルスチェックが通るよう、仮ページを配置します。
    echo "<?php phpinfo(); ?>" > /var/www/html/index.php
    chown -R apache:apache /var/www/html
  EOF

  tags = {
    Name = var.ec2_name
  }
}

# -----------------------------------------------------------------------------
# EC2 前段の ALB（Application Load Balancer）
# -----------------------------------------------------------------------------
resource "aws_lb" "web" {
  name               = var.alb_name
  load_balancer_type = "application"
  subnets            = sort(data.aws_subnets.default.ids)
  security_groups    = [aws_security_group.alb.id]
}

resource "aws_lb_target_group" "web" {
  name     = "${var.github_repository}-tg"
  port     = 80
  protocol = "HTTP"
  vpc_id   = data.aws_vpc.default.id

  health_check {
    path                = var.alb_health_check_path
    matcher             = "200-399"
    healthy_threshold   = 2
    unhealthy_threshold = 3
    timeout             = 5
    interval            = 30
  }
}
# ヘルスチェックパスは軽量で 200-399 を返すエンドポイントを指定します。
# アプリの URL 構成を変更した場合は alb_health_check_path も更新してください。

resource "aws_lb_target_group_attachment" "web" {
  target_group_arn = aws_lb_target_group.web.arn
  target_id        = aws_instance.web.id
  port             = 80
}

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.web.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.web.arn
  }
}

# -----------------------------------------------------------------------------
# MySQL RDS（非公開）と自動生成マスターパスワード
# -----------------------------------------------------------------------------
resource "aws_db_subnet_group" "mysql" {
  name       = "${var.github_repository}-db-subnet-group"
  subnet_ids = sort(data.aws_subnets.default.ids)
}

resource "random_password" "db_master" {
  # 初回作成時に生成され、Terraform state に保存されます。
  # 取得コマンド: terraform output -raw rds_master_password
  length  = 24
  special = false
}
# より厳しいパスワード要件が必要な場合は special=true を検討し、
# アプリ側が特殊文字を扱えることを事前確認してください。

resource "aws_db_instance" "mysql" {
  # DB は public 非公開。EC2 app SG からのみ到達可能です。
  identifier                  = local.db_identifier
  engine                      = "mysql"
  instance_class              = var.db_instance_class
  allocated_storage           = var.db_allocated_storage
  db_name                     = var.db_name
  username                    = var.db_username
  password                    = random_password.db_master.result
  port                        = 3306
  db_subnet_group_name        = aws_db_subnet_group.mysql.name
  vpc_security_group_ids      = [aws_security_group.db.id]
  backup_retention_period     = var.db_backup_retention_period
  multi_az                    = false
  storage_encrypted           = true
  publicly_accessible         = false
  skip_final_snapshot         = var.db_skip_final_snapshot
  final_snapshot_identifier   = var.db_skip_final_snapshot ? null : "${local.db_identifier}-final"
  deletion_protection         = var.db_deletion_protection
  apply_immediately           = true
  auto_minor_version_upgrade  = true
  allow_major_version_upgrade = false
}
# ここでのコスト/安全設定の既定値は開発寄りです:
# - multi_az=false
# - db_skip_final_snapshot=true（変数の既定値）
# - db_deletion_protection=false（変数の既定値）
# 本番運用前に必ず見直してください。
