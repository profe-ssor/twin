# S3 backend: locking uses a lock object in the bucket (use_lockfile), not DynamoDB.
# Requires Terraform >= 1.11 (use_lockfile). CI pins 1.12.x. Bucket/key/region via -backend-config.
terraform {
  required_version = ">= 1.11.0"

  backend "s3" {
    use_lockfile = true
  }
}
