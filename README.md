# taniawsdeploy

GitHub Actions -> AWS deploy setup by Terraform.

## 1. Build AWS side with Terraform

```powershell
cd infra/terraform
copy terraform.tfvars.example terraform.tfvars
```

Edit `terraform.tfvars` if needed, then:

```powershell
terraform init
terraform apply
```

After apply, copy output `github_actions_role_arn`.

## 2. Set GitHub repository variables

Repository Settings -> Secrets and variables -> Actions -> Variables:

- `AWS_ROLE_ARN`: output `github_actions_role_arn`
- `AWS_REGION`: deployment region (example: `ap-northeast-1`)

## 3. Run GitHub Actions

Workflow file: `.github/workflows/deploy.yml`

- `push` to `main`, or
- run manually with `workflow_dispatch`

Current deploy step is placeholder. Replace `Deploy` step with your actual command.

## Notes

- This configuration gives full AWS permissions via `AdministratorAccess` by default.
- For production, set `attach_administrator_access = false` and attach minimum required policies.
- If your account already has the GitHub OIDC provider, set:
  - `create_github_oidc_provider = false`
  - `existing_github_oidc_provider_arn = "arn:aws:iam::<account-id>:oidc-provider/token.actions.githubusercontent.com"`
