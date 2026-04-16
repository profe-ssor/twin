#!/bin/bash
set -e

ENVIRONMENT=${1:-dev}          # dev | test | prod
PROJECT_NAME=${2:-twin}

echo "🚀 Deploying ${PROJECT_NAME} to ${ENVIRONMENT}..."

# 1. Build Lambda package
cd "$(dirname "$0")/.."        # project root
echo "📦 Building Lambda package..."
(cd backend && uv run deploy.py)

# 2. Terraform workspace & apply
cd terraform
AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
AWS_REGION=${DEFAULT_AWS_REGION:-us-east-1}

# Non-interactive init: some Terraform versions still prompt for "state migration" even with
# -force-copy; piping yes answers it. In CI, drop .terraform so no stale backend metadata.
export TF_INPUT=0
export TF_IN_AUTOMATION=1
if [ -n "${CI:-}" ]; then
  rm -rf .terraform
fi
yes | terraform init -input=false -migrate-state -force-copy \
  -backend-config="bucket=twin-terraform-state-${AWS_ACCOUNT_ID}" \
  -backend-config="key=${ENVIRONMENT}/terraform.tfstate" \
  -backend-config="region=${AWS_REGION}" \
  -backend-config="encrypt=true"


if ! terraform workspace list | grep -q "$ENVIRONMENT"; then
  terraform workspace new "$ENVIRONMENT"
else
  terraform workspace select "$ENVIRONMENT"
fi

# If AWS already has resources from a prior apply but this state file is empty/new, import them
# so apply does not fail with EntityAlreadyExists / BucketAlreadyExists.
echo "🔗 Importing existing AWS resources into state (no-op if none or already in state)..."
bash "../scripts/terraform-import-existing-if-present.sh" "$ENVIRONMENT" "$PROJECT_NAME"

# Shared Terraform arguments (workspace already selected above)
TF_COMMON_VARS=(-var="project_name=$PROJECT_NAME" -var="environment=$ENVIRONMENT")
if [ "$ENVIRONMENT" = "prod" ]; then
  TF_EXTRA=(-var-file=prod.tfvars)
else
  TF_EXTRA=()
fi

echo "🎯 Applying Terraform..."
terraform apply "${TF_EXTRA[@]}" "${TF_COMMON_VARS[@]}" -auto-approve

# New or updated output {} blocks are not readable via `terraform output` until state
# is refreshed (see terminal warning: "No outputs found"). One refresh-only apply
# fixes stacks that were first applied before outputs.tf existed.
echo "🔄 Refreshing state so outputs are available..."
terraform apply -refresh-only "${TF_EXTRA[@]}" "${TF_COMMON_VARS[@]}" -auto-approve

API_URL=$(terraform output -raw api_gateway_url)
FRONTEND_BUCKET=$(terraform output -raw s3_frontend_bucket)
CUSTOM_URL=$(terraform output -raw custom_domain_url 2>/dev/null || true)

# 3. Build + deploy frontend
cd ../frontend

# Create production environment file with API URL
echo "📝 Setting API URL for production..."
echo "NEXT_PUBLIC_API_URL=$API_URL" > .env.production

npm install
npm run build
aws s3 sync ./out "s3://$FRONTEND_BUCKET/" --delete

echo "🧹 Invalidating CloudFront edge cache (HTML)..."
aws cloudfront create-invalidation \
  --distribution-id "$(terraform -chdir=../terraform output -raw cloudfront_distribution_id)" \
  --paths "/index.html" "/" "/404.html" >/dev/null

cd ..

# 4. Final messages
echo -e "\n✅ Deployment complete!"
echo "🌐 CloudFront URL : $(terraform -chdir=terraform output -raw cloudfront_url)"
if [ -n "$CUSTOM_URL" ]; then
  echo "🔗 Custom domain  : $CUSTOM_URL"
fi
echo "📡 API Gateway    : $API_URL"