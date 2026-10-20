output "artifacts_bucket_name" {
  description = "Name of the S3 bucket provisioned in LocalStack."
  value       = aws_s3_bucket.artifacts.bucket
}
