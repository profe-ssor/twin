output "api_gateway_url" {
  description = "Base URL for the HTTP API (use for NEXT_PUBLIC_API_URL); no trailing slash"
  value       = trimsuffix(aws_apigatewayv2_stage.default.invoke_url, "/")
}

output "s3_frontend_bucket" {
  description = "S3 bucket hosting the static Next.js export"
  value       = aws_s3_bucket.frontend.id
}

output "cloudfront_url" {
  description = "HTTPS URL for the CloudFront distribution"
  value       = "https://${aws_cloudfront_distribution.main.domain_name}"
}

output "custom_domain_url" {
  description = "Primary site URL when use_custom_domain is enabled"
  value       = var.use_custom_domain && var.root_domain != "" ? "https://${var.root_domain}" : ""
}

output "cloudfront_distribution_id" {
  description = "CloudFront distribution ID (for cache invalidation after deploys)"
  value       = aws_cloudfront_distribution.main.id
}
