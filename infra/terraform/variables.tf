# -----------------------------------------------------------------------------
# 全体共通
# -----------------------------------------------------------------------------
# 入力変数の設計方針:
# - 初回セットアップで動く既定値を用意する
# - 環境差分として必要な値だけを外出しする
# - セキュリティ関連の既定値は本番前に見直す
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

# -----------------------------------------------------------------------------
# GitHub OIDC / Actions ロール制御
# -----------------------------------------------------------------------------
# OIDC で「どの GitHub 実行元がロールを引き受けられるか」を制御します。
# 既定では 1 つのリポジトリの main ブランチのみ許可します。
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
# セキュリティ注意:
# - true: 初期構築は簡単だが権限が広い
# - false: 本番推奨。additional_policy_arns や main.tf のカスタムポリシーで
#   最小権限を付与する

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
# 既に同一アカウントに OIDC Provider がある場合:
# - create_github_oidc_provider = false
# - existing_github_oidc_provider_arn に既存 ARN を設定
# これで apply 時の EntityAlreadyExists を回避できます。

variable "existing_github_oidc_provider_arn" {
  description = "Existing GitHub OIDC provider ARN (required when create_github_oidc_provider=false)."
  type        = string
  default     = null

  validation {
    condition     = var.create_github_oidc_provider || var.existing_github_oidc_provider_arn != null
    error_message = "existing_github_oidc_provider_arn must be set when create_github_oidc_provider is false."
  }
}

# -----------------------------------------------------------------------------
# EC2 アプリケーションホスト
# -----------------------------------------------------------------------------
# この EC2 は GitHub Actions（SSM 経由）のデプロイ先です。
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
# null は「SSH キーペア未設定」を意味します。
# 本構成では運用アクセスを AWS Systems Manager 前提としています。

variable "http_ingress_cidrs" {
  description = "CIDRs allowed to access HTTP(80) on EC2."
  type        = list(string)
  default     = ["0.0.0.0/0"]
}
# 現在は ALB 側の公開 CIDR 制御にも使われます。
# 公開範囲を制限したい場合はこのリストを絞ってください。

# -----------------------------------------------------------------------------
# CI/CD 配布物アップロード用バケット
# -----------------------------------------------------------------------------
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
# 明示的に削除したい場合を除き false 推奨です。
# true は検証環境の後片付けには便利ですが、保管データ消失リスクがあります。

# -----------------------------------------------------------------------------
# ALB
# -----------------------------------------------------------------------------
variable "alb_name" {
  description = "ALB name for web traffic."
  type        = string
  default     = "taniawsdeploy-alb"
}

variable "alb_health_check_path" {
  description = "Health check path for ALB target group."
  type        = string
  default     = "/phpinfo.php"
}

# -----------------------------------------------------------------------------
# RDS MySQL
# -----------------------------------------------------------------------------
# ここで定義するのは初期 DB 特性です。
# アプリのスキーマ変更やデータ移行は Terraform の対象外です。
variable "db_name" {
  description = "Initial MySQL database name."
  type        = string
  default     = "appdb"
}

variable "db_username" {
  description = "Master username for MySQL RDS."
  type        = string
  default     = "admin"
}

variable "db_instance_class" {
  description = "RDS instance class."
  type        = string
  default     = "db.t4g.micro"
}

variable "db_allocated_storage" {
  description = "RDS allocated storage (GB)."
  type        = number
  default     = 20
}

variable "db_backup_retention_period" {
  description = "RDS backup retention in days."
  type        = number
  default     = 7
}

variable "db_skip_final_snapshot" {
  description = "Skip final snapshot when destroying RDS."
  type        = bool
  default     = true
}
# 本番推奨: false（削除時に最終スナップショットを残す）

variable "db_deletion_protection" {
  description = "Enable deletion protection for RDS."
  type        = bool
  default     = false
}
# 本番推奨: true（誤削除防止）
