# このリポジトリ/アカウント向けの環境別上書き設定です。
# このプロジェクトでは git で追跡しない前提です。
aws_region        = "ap-northeast-1"
github_owner      = "cns-taniyama"
github_repository = "taniawsdeploy"
github_branch     = "main"
iam_role_name     = "gha-taniawsdeploy-deploy"

# この AWS アカウントに既存の OIDC Provider を再利用します。
create_github_oidc_provider       = false
existing_github_oidc_provider_arn = "arn:aws:iam::431057452232:oidc-provider/token.actions.githubusercontent.com"
# AWS アカウントを変更する場合は上記 ARN を更新してください。

# 全権限付与。最小権限化する場合は false に変更します。
attach_administrator_access = true

# 必要に応じて追加ポリシーを指定します。
additional_policy_arns = []
