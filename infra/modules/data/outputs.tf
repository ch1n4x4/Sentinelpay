output "kyc_bucket_name" {
  value = aws_s3_bucket.kyc.bucket
}

output "redis_endpoint" {
  value = aws_elasticache_replication_group.this.primary_endpoint_address
}

output "redis_secret_arn" {
  value = aws_secretsmanager_secret.redis.arn
}

output "redis_security_group_id" {
  value = aws_security_group.redis.id
}

output "access_logs_bucket_name" {
  description = "Name of the S3 bucket used for ALB access logs"
  value       = aws_s3_bucket.access_logs.bucket
}

output "redis_password" {
  description = "Redis authentication password"
  value       = random_password.redis_auth.result
  sensitive   = true
}