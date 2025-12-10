#!/usr/bin/env bash
set -euo pipefail

# Quick smoke test against the customer-facing API.
# Usage: API_BASE=http://localhost:3000 ./scripts/smoke.sh

API_BASE="${API_BASE:-http://localhost:3000}"
USER_ID="u-$(date +%s)"

echo "Using API_BASE=${API_BASE}"
echo "Creating purchase for user ${USER_ID}..."

curl -sSf -X POST "${API_BASE}/buy" \
  -H "Content-Type: application/json" \
  -d "{\"username\":\"demo\",\"userid\":\"${USER_ID}\",\"price\":12.34}"

echo
echo "Fetching purchases for ${USER_ID}..."

curl -sSf "${API_BASE}/getAllUserBuys/${USER_ID}" | tee /tmp/purchases.json

echo
echo "Smoke test complete."


