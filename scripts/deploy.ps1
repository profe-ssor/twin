param(
    [string]$Environment = "dev",   # dev | test | prod
    [string]$ProjectName = "twin"
)
$ErrorActionPreference = "Stop"

Write-Host "Deploying $ProjectName to $Environment ..." -ForegroundColor Green

# 1. Build Lambda package
Set-Location (Split-Path $PSScriptRoot -Parent)   # project root
Write-Host "Building Lambda package..." -ForegroundColor Yellow
Set-Location backend
uv run deploy.py
Set-Location ..

# 2. Terraform workspace & apply
Set-Location terraform
$awsAccountId = aws sts get-caller-identity --query Account --output text
$awsRegion = if ($env:DEFAULT_AWS_REGION) { $env:DEFAULT_AWS_REGION } else { "us-east-1" }
$env:TF_INPUT = "0"
$env:TF_IN_AUTOMATION = "1"
if ($env:CI) { Remove-Item -Recurse -Force .terraform -ErrorAction SilentlyContinue }
# Linux/macOS: `yes` feeds migration prompts. On Windows without `yes`, use Git Bash or init once interactively.
if (Get-Command yes -ErrorAction SilentlyContinue) {
  yes | terraform init -input=false -migrate-state -force-copy `
    -backend-config="bucket=twin-terraform-state-$awsAccountId" `
    -backend-config="key=$Environment/terraform.tfstate" `
    -backend-config="region=$awsRegion" `
    -backend-config="encrypt=true"
} else {
  terraform init -input=false -migrate-state -force-copy `
    -backend-config="bucket=twin-terraform-state-$awsAccountId" `
    -backend-config="key=$Environment/terraform.tfstate" `
    -backend-config="region=$awsRegion" `
    -backend-config="encrypt=true"
}

if (-not (terraform workspace list | Select-String $Environment)) {
    terraform workspace new $Environment
} else {
    terraform workspace select $Environment
}

Write-Host "Importing existing AWS resources into state (if any)..." -ForegroundColor Yellow
$importScript = Join-Path (Split-Path $PSScriptRoot -Parent) "scripts/terraform-import-existing-if-present.sh"
if (Get-Command bash -ErrorAction SilentlyContinue) {
    bash $importScript $Environment $ProjectName
} else {
    Write-Host "bash not found; skip auto-import. Run the import script from Git Bash if apply fails on existing resources." -ForegroundColor Yellow
}

$tfCommon = @(
    "-var=project_name=$ProjectName",
    "-var=environment=$Environment"
)
if ($Environment -eq "prod") {
    $tfExtra = @("-var-file=prod.tfvars")
} else {
    $tfExtra = @()
}

terraform apply @tfExtra @tfCommon -auto-approve
Write-Host "Refreshing state so outputs are available..." -ForegroundColor Yellow
terraform apply -refresh-only @tfExtra @tfCommon -auto-approve

$ApiUrl        = terraform output -raw api_gateway_url
$FrontendBucket = terraform output -raw s3_frontend_bucket
try { $CustomUrl = terraform output -raw custom_domain_url } catch { $CustomUrl = "" }

# 3. Build + deploy frontend
Set-Location ..\frontend

# Create production environment file with API URL
Write-Host "Setting API URL for production..." -ForegroundColor Yellow
"NEXT_PUBLIC_API_URL=$ApiUrl" | Out-File .env.production -Encoding utf8

npm install
npm run build
aws s3 sync .\out "s3://$FrontendBucket/" --delete

Write-Host "Invalidating CloudFront edge cache (HTML)..." -ForegroundColor Yellow
$CfDist = terraform -chdir=../terraform output -raw cloudfront_distribution_id
aws cloudfront create-invalidation --distribution-id $CfDist --paths "/index.html" "/" "/404.html" | Out-Null

Set-Location ..

# 4. Final summary
$CfUrl = terraform -chdir=terraform output -raw cloudfront_url
Write-Host "Deployment complete!" -ForegroundColor Green
Write-Host "CloudFront URL : $CfUrl" -ForegroundColor Cyan
if ($CustomUrl) {
    Write-Host "Custom domain  : $CustomUrl" -ForegroundColor Cyan
}
Write-Host "API Gateway    : $ApiUrl" -ForegroundColor Cyan
