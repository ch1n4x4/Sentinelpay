output "terraform_state_bucket" {
  value = aws_s3_bucket.terraform_state.bucket
}

output "terraform_lock_table" {
  value = aws_dynamodb_table.terraform_locks.name
}

#output "github_actions_role_arn" {
#  description = "IAM role ARN used by GitHub Actions through OIDC"
#  value       = module.github_oidc.role_arn
#}

#output "github_oidc_provider_arn" {
#  description = "GitHub OIDC provider ARN"
#  value       = module.github_oidc.oidc_provider_arn
#}