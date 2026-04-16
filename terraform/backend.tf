# S3 backend: locking uses a lock object in the bucket (use_lockfile), not DynamoDB.
# Requires Terraform >= 1.11. Bucket/key/region are supplied via -backend-config in scripts/CI.
terraform {
  required_version = ">= 1.11.0"

  backend "s3" {
    use_lockfile = true
  }
}
