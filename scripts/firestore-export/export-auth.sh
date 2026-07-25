#!/usr/bin/env bash
set -euo pipefail

PROJECT_ID="${1:-selfcare-1476e}"
OUT_DIR="${2:-snapshot}"

mkdir -p "$OUT_DIR"

firebase auth:export "$OUT_DIR/auth-users.json" \
  --format=JSON \
  --project "$PROJECT_ID" \
  | tee "$OUT_DIR/auth-export.log"

node parse-hash-config.js "$OUT_DIR/auth-export.log" "$OUT_DIR/hash-config.json"

echo "Auth export complete: $OUT_DIR/auth-users.json, $OUT_DIR/hash-config.json"
