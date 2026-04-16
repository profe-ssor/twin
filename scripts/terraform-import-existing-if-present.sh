#!/usr/bin/env bash
# Run from the terraform/ directory after terraform init and workspace select.
# Imports resources that already exist in AWS but are not in the current Terraform state
# (e.g. new remote state file, or first CI deploy after manual apply).
#
# Usage: bash ../scripts/terraform-import-existing-if-present.sh <environment> [project_name]

set -euo pipefail

ENV="${1:?environment (dev|test|prod) required}"
PROJECT="${2:-twin}"
PREFIX="${PROJECT}-${ENV}"
ACCOUNT="$(aws sts get-caller-identity --query Account --output text)"

in_state() {
  terraform state show -no-color "$1" >/dev/null 2>&1
}

import_role() {
  local addr=$1 name=$2
  in_state "$addr" && return 0
  if ! aws iam get-role --role-name "$name" >/dev/null 2>&1; then
    return 0
  fi
  echo "terraform import: $addr (IAM role $name)"
  terraform import -input=false "$addr" "$name"
}

import_bucket() {
  local addr=$1 bucket=$2
  in_state "$addr" && return 0
  if ! aws s3api head-bucket --bucket "$bucket" 2>/dev/null; then
    return 0
  fi
  echo "terraform import: $addr (S3 $bucket)"
  terraform import -input=false "$addr" "$bucket"
}

import_attachment() {
  local addr=$1 role=$2 policy_arn=$3
  in_state "$addr" && return 0
  if ! aws iam get-role --role-name "$role" >/dev/null 2>&1; then
    return 0
  fi
  if ! aws iam list-attached-role-policies --role-name "$role" --output json \
    | jq -e --arg arn "$policy_arn" '.AttachedPolicies[] | select(.PolicyArn == $arn)' >/dev/null 2>&1; then
    return 0
  fi
  echo "terraform import: $addr (attach $policy_arn to $role)"
  terraform import -input=false "$addr" "${role}/${policy_arn}"
}

import_inline_policy() {
  local addr=$1 role=$2 policy_name=$3
  in_state "$addr" && return 0
  if ! aws iam get-role-policy --role-name "$role" --policy-name "$policy_name" >/dev/null 2>&1; then
    return 0
  fi
  echo "terraform import: $addr (inline policy $policy_name on $role)"
  terraform import -input=false "$addr" "${role}:${policy_name}"
}

import_lambda_function() {
  local addr=$1 name=$2
  in_state "$addr" && return 0
  if ! aws lambda get-function --function-name "$name" >/dev/null 2>&1; then
    return 0
  fi
  echo "terraform import: $addr (Lambda $name)"
  terraform import -input=false "$addr" "$name"
}

# Import ID is function_name/statement_id (AWS provider docs).
import_lambda_permission() {
  local addr=$1 fn=$2 sid=$3
  in_state "$addr" && return 0
  if ! aws lambda get-function --function-name "$fn" >/dev/null 2>&1; then
    return 0
  fi
  echo "terraform import: $addr ($fn/$sid)"
  # Import can fail (provider/config drift). Reconcile step below removes stale AWS permissions.
  terraform import -input=false "$addr" "${fn}/${sid}" || true
}

# If the permission exists in AWS but is still not in state after import, RemovePermission
# avoids AddPermission 409 on the next apply (same Sid).
reconcile_lambda_permission_not_in_state() {
  local addr=$1 fn=$2 sid=$3
  in_state "$addr" && return 0
  if ! aws lambda get-function --function-name "$fn" >/dev/null 2>&1; then
    return 0
  fi
  echo "Reconcile: $addr not in state — removing $sid on $fn if present so apply can recreate it."
  aws lambda remove-permission --function-name "$fn" --statement-id "$sid" 2>/dev/null || true
}

LAMBDA_ROLE="${PREFIX}-lambda-role"
GITHUB_ROLE="github-actions-twin-deploy"

echo "Checking for existing AWS resources to import (env=$ENV project=$PROJECT account=$ACCOUNT)..."

import_role aws_iam_role.github_actions "$GITHUB_ROLE"
import_role aws_iam_role.lambda_role "$LAMBDA_ROLE"

import_bucket aws_s3_bucket.memory "${PREFIX}-memory-${ACCOUNT}"
import_bucket aws_s3_bucket.frontend "${PREFIX}-frontend-${ACCOUNT}"

# Lambda execution role — managed policy attachments (common after a prior partial apply)
import_attachment aws_iam_role_policy_attachment.lambda_basic "$LAMBDA_ROLE" \
  "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
import_attachment aws_iam_role_policy_attachment.lambda_bedrock "$LAMBDA_ROLE" \
  "arn:aws:iam::aws:policy/AmazonBedrockFullAccess"
import_attachment aws_iam_role_policy_attachment.lambda_s3 "$LAMBDA_ROLE" \
  "arn:aws:iam::aws:policy/AmazonS3FullAccess"

# Lambda function (must exist in AWS and role must be importable first)
import_lambda_function aws_lambda_function.api "${PREFIX}-api"
import_lambda_permission aws_lambda_permission.api_gw "${PREFIX}-api" "AllowExecutionFromAPIGateway"
reconcile_lambda_permission_not_in_state aws_lambda_permission.api_gw "${PREFIX}-api" "AllowExecutionFromAPIGateway"

# GitHub Actions deploy role — managed attachments
import_attachment aws_iam_role_policy_attachment.github_lambda "$GITHUB_ROLE" \
  "arn:aws:iam::aws:policy/AWSLambda_FullAccess"
import_attachment aws_iam_role_policy_attachment.github_s3 "$GITHUB_ROLE" \
  "arn:aws:iam::aws:policy/AmazonS3FullAccess"
import_attachment aws_iam_role_policy_attachment.github_apigateway "$GITHUB_ROLE" \
  "arn:aws:iam::aws:policy/AmazonAPIGatewayAdministrator"
import_attachment aws_iam_role_policy_attachment.github_cloudfront "$GITHUB_ROLE" \
  "arn:aws:iam::aws:policy/CloudFrontFullAccess"
import_attachment aws_iam_role_policy_attachment.github_iam_read "$GITHUB_ROLE" \
  "arn:aws:iam::aws:policy/IAMReadOnlyAccess"
import_attachment aws_iam_role_policy_attachment.github_bedrock "$GITHUB_ROLE" \
  "arn:aws:iam::aws:policy/AmazonBedrockFullAccess"
import_attachment aws_iam_role_policy_attachment.github_dynamodb "$GITHUB_ROLE" \
  "arn:aws:iam::aws:policy/AmazonDynamoDBFullAccess"
import_attachment aws_iam_role_policy_attachment.github_acm "$GITHUB_ROLE" \
  "arn:aws:iam::aws:policy/AWSCertificateManagerFullAccess"
import_attachment aws_iam_role_policy_attachment.github_route53 "$GITHUB_ROLE" \
  "arn:aws:iam::aws:policy/AmazonRoute53FullAccess"

import_inline_policy aws_iam_role_policy.github_additional "$GITHUB_ROLE" "github-actions-additional"

echo "Import sync finished."
