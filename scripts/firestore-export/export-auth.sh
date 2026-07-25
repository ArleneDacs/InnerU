#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

PROJECT_ID="${1:-selfcare-1476e}"
OUT_DIR="${2:-snapshot}"
SERVICE_ACCOUNT="${3:-$SCRIPT_DIR/service-account.json}"

mkdir -p "$OUT_DIR"

firebase auth:export "$OUT_DIR/auth-users.json" \
  --format=JSON \
  --project "$PROJECT_ID" \
  | tee "$OUT_DIR/auth-export.log"

# The Firebase CLI does not print the SCRYPT hash-config parameters to the
# console (verified empirically against a real project - the original
# console-log-scraping approach in parse-hash-config.js never finds a
# match). Fetch them directly from the Identity Toolkit Admin API instead,
# using the same service account credentials as the Firestore export.
node "$SCRIPT_DIR/fetch-hash-config.js" "$SERVICE_ACCOUNT" "$PROJECT_ID" "$OUT_DIR/hash-config.json"

echo "Auth export complete: $OUT_DIR/auth-users.json, $OUT_DIR/hash-config.json"
