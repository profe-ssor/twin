#!/usr/bin/env bash
# Manual helper: same logic as deploy.sh auto-import. Requires terraform init + workspace first.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT/terraform"
exec bash "$ROOT/scripts/terraform-import-existing-if-present.sh" "${1:-dev}" "${2:-twin}"
