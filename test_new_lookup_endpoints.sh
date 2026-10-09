#!/bin/bash
#=============================================================
#   Smoke test for the new /api/panelContextType and
#   /api/assessmentPurposeType endpoints.
#
#   Usage:
#     chmod +x test_new_lookup_endpoints.sh
#     ./test_new_lookup_endpoints.sh
#
#   Credentials load from deploy_HPB/.env, same as imports_fixed.sh.
# =============================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ -f "$SCRIPT_DIR/.env" ]; then
    set -a
    source "$SCRIPT_DIR/.env"
    set +a
fi

BASE_URL="${BASE_URL:-http://localhost:9080}"
USERNAME="${HPB_ADMIN_USERNAME:?Set HPB_ADMIN_USERNAME in deploy_HPB/.env}"
PASSWORD="${HPB_ADMIN_PASSWORD:?Set HPB_ADMIN_PASSWORD in deploy_HPB/.env}"

echo "▶ Logging in as $USERNAME..."
TOKEN=$(curl -s -X POST "$BASE_URL/auth/login" \
  -H "Content-Type: application/json" \
  -d "{\"username\": \"$USERNAME\", \"password\": \"$PASSWORD\"}" \
  | python3 -c "import json,sys; print(json.load(sys.stdin)['data']['token'])")

if [ -z "$TOKEN" ]; then
  echo "❌ Login failed."
  exit 1
fi
echo "✅ Login OK."
echo ""

check() {
  local label="$1" method="$2" url="$3" body="$4"
  echo "▶ $label"
  if [ -n "$body" ]; then
    RESP=$(curl -s -X "$method" "$BASE_URL$url" -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" -d "$body")
  else
    RESP=$(curl -s -X "$method" "$BASE_URL$url" -H "Authorization: Bearer $TOKEN")
  fi
  echo "$RESP" | python3 -m json.tool 2>/dev/null || echo "$RESP"
  echo ""
}

for API in panelContextType assessmentPurposeType; do
  echo "=============================================="
  echo "  Testing /api/$API"
  echo "=============================================="

  check "GET  /api/$API (list seeded data)" GET "/api/$API"

  check "POST /api/$API (create test row)" POST "/api/$API" \
    "{\"name\":\"ZZ_SMOKE_TEST\",\"description\":\"Created by test_new_lookup_endpoints.sh\"}"

  check "GET  /api/$API?searchTerm=ZZ_SMOKE_TEST" GET "/api/$API?searchTerm=ZZ_SMOKE_TEST"

  # Pull the id back out so we can update/delete it
  NEW_ID=$(curl -s "$BASE_URL/api/$API?searchTerm=ZZ_SMOKE_TEST" -H "Authorization: Bearer $TOKEN" \
    | python3 -c "
import json,sys
d = json.load(sys.stdin)
try:
    rows = d['data']['data']
    print(rows[0]['id'] if rows else '')
except Exception:
    print('')
")

  if [ -n "$NEW_ID" ]; then
    check "PUT  /api/$API (update test row $NEW_ID)" PUT "/api/$API" \
      "{\"id\":$NEW_ID,\"name\":\"ZZ_SMOKE_TEST_RENAMED\",\"description\":\"Updated by smoke test\"}"

    check "DELETE /api/$API/$NEW_ID (cleanup)" DELETE "/api/$API/$NEW_ID"
  else
    echo "⚠️  Could not resolve id for the test row; skipping update/delete."
  fi

  echo "▶ GET /api/$API/download_template (headers only)"
  curl -s -D - -o /dev/null "$BASE_URL/api/$API/download_template" -H "Authorization: Bearer $TOKEN" | grep -i "HTTP\|Content-Disposition"
  echo ""

  echo "▶ GET /api/$API/export (headers only)"
  curl -s -D - -o /dev/null "$BASE_URL/api/$API/export" -H "Authorization: Bearer $TOKEN" | grep -i "HTTP\|Content-Disposition"
  echo ""
done

echo "=============================================="
echo "  Done. Review the JSON above for status:true"
echo "  on every call, and check the seeded rows are"
echo "  still 5 (panelContextType) and 3"
echo "  (assessmentPurposeType) after the test row"
echo "  was created+deleted."
echo "=============================================="
