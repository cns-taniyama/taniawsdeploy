# -----------------------------------------------------------------------------
# Terraform / Provider バージョン制約
# -----------------------------------------------------------------------------
# このファイルの目的:
# - ローカル実行と CI 実行の挙動差を減らす
# - 意図しないメジャーアップグレードを防ぐ
# - .terraform.lock.hcl と組み合わせてプラグインを安定化する
#
# 運用メモ:
# - Provider のメジャー更新時は次を実行して差分を必ず確認
#   terraform init -upgrade
#   terraform plan
#   その後に apply
terraform {
  required_version = ">= 1.6.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }
}
