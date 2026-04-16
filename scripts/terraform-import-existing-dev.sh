#!/usr/bin/env bash
# One-time: import resources that already exist in AWS but are missing from the current
# Terraform remote state (common after switching to the S3 backend or a new state key).
#
# Usage (from repo root, after terraform init + workspace select dev):
#   ./scripts/terraform-import-existing-dev.sh
#
# Requires: AWS CLI credentials with read/list + import permissions for the resources below.

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT/terraform"

ACCOUNT="$(aws sts get-caller-identity --query Account --output text)"
ENV="${1:-dev}"
PROJECT="${2:-twin}"
PREFIX="${PROJECT}-${ENV}"

echo "Importing into workspace: $(terraform workspace show)"
echo "Account: ${ACCOUNT}  prefix: ${PREFIX}"

import_if_needed() {
  local addr=$1
  local id=$2
  if terraform state show -no-color "$addr" >/dev/null 2>&1; then
    echo "  skip (already in state): $addr"
  else
    echo "  import: $addr <- $id"
    terraform import "$addr" "$id"
  fi
}

import_if_needed "aws_s3_bucket.memory" "${PREFIX}-memory-${ACCOUNT}"
import_if_needed "aws_s3_bucket.frontend" "${PREFIX}-frontend-${ACCOUNT}"
import_if_needed "aws_iam_role.lambda_role" "${PREFIX}-lambda-role"
import_if_needed "aws_iam_role.github_actions" "github-actions-twin-deploy"

echo "Done. Run: terraform plan"
echo "If plan still reports existing resources, import those addresses the same way."
