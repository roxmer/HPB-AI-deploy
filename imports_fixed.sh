#!/bin/bash
#=============================================================
#   HPB List Import Script
#   Reads a CSV mapping file and imports all lists via API.
#
#   Usage:
#     chmod +x import_lists.sh
#     ./import_lists.sh /path/to/mapping.csv
#
#   CSV format (with header row):
#     api_path,filename
#     relativeType,5. RelativeType.xlsx
#     chronicCondition,ChronicCondition_export.xlsx
# =============================================================

# ── CONFIGURATION ─────────────────────────────────────────────
# Paths resolve relative to this script's own location; credentials load
# from a local .env file if present (copy .env.example to get started --
# .env is gitignored, never commit real credentials).
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ -f "$SCRIPT_DIR/.env" ]; then
    set -a
    source "$SCRIPT_DIR/.env"
    set +a
fi

BASE_URL="${BASE_URL:-http://localhost:9080}"
USERNAME="${HPB_ADMIN_USERNAME:?Set HPB_ADMIN_USERNAME in deploy_HPB/.env (copy .env.example to get started)}"
PASSWORD="${HPB_ADMIN_PASSWORD:?Set HPB_ADMIN_PASSWORD in deploy_HPB/.env (copy .env.example to get started)}"
LISTS_DIR="${LISTS_DIR:-$SCRIPT_DIR/HPB_Templates}"
# ────────────────────────────────────────────────────────────

# ── CHECK INPUT PARAMETER ────────────────────────────────────
if [ -z "$1" ]; then
  echo "❌ No CSV file provided."
  echo "   Usage: ./import_lists.sh /path/to/mapping.csv"
  exit 1
fi

CSV_FILE="$1"

if [ ! -f "$CSV_FILE" ]; then
  echo "❌ CSV file not found: $CSV_FILE"
  exit 1
fi

echo ""
echo "======================================"
echo "  HPB List Import Script"
echo "  CSV: $CSV_FILE"
echo "======================================"
echo ""

# ── STEP 1: Login and get token ──────────────────────────────
echo "▶ Logging in as $USERNAME..."
TOKEN=$(curl -s -X POST "$BASE_URL/auth/login" \
  -H "Content-Type: application/json" \
  -d "{\"username\": \"$USERNAME\", \"password\": \"$PASSWORD\"}" \
  | python3 -c "import json,sys; data=json.load(sys.stdin); print(data['data']['token'])")

if [ -z "$TOKEN" ]; then
  echo "❌ Login failed. Check your credentials."
  exit 1
fi
echo "✅ Login successful."
echo ""

# ── STEP 2: Read CSV and import each list ────────────────────
SUCCESS=0
FAILED=0
SKIPPED=0

# Skip header row with tail -n +2
while IFS=',' read -r API_PATH FILENAME; do
  # Trim whitespace and carriage returns
  API_PATH=$(echo "$API_PATH" | tr -d '\r' | xargs)
  FILENAME=$(echo "$FILENAME" | tr -d '\r' | xargs)

  FILE_PATH="$LISTS_DIR/$FILENAME"

  # Check if file exists
  if [ ! -f "$FILE_PATH" ]; then
    echo "⚠️  SKIPPED  [$API_PATH] — File not found: $FILENAME"
    SKIPPED=$((SKIPPED + 1))
    continue
  fi

  # Determine the import endpoint suffix
  # technique, organList/organ-list, and primaryParameter/primary-parameter contain multiple sheets/entities.
  # We use the specialized 'data-import-all' endpoint for these to import all sheets.
  IMPORT_ENDPOINT="data_import"
  if [ "$API_PATH" = "technique" ] || [ "$API_PATH" = "organList" ] || [ "$API_PATH" = "organ-list" ] || [ "$API_PATH" = "primaryParameter" ] || [ "$API_PATH" = "primary-parameter" ]; then
    IMPORT_ENDPOINT="data-import-all"
  fi

  # Call the import API
  RESPONSE=$(curl -s -X POST "$BASE_URL/api/$API_PATH/$IMPORT_ENDPOINT" \
    -H "Authorization: Bearer $TOKEN" \
    -F "excelFile=@$FILE_PATH")

  # Check response status
  STATUS=$(echo "$RESPONSE" | python3 -c "import json,sys; data=json.load(sys.stdin); print(data.get('status', False))" 2>/dev/null)

  if [ "$STATUS" = "True" ]; then
    echo "✅ SUCCESS  [$API_PATH] — $FILENAME (Endpoint: $IMPORT_ENDPOINT)"
    SUCCESS=$((SUCCESS + 1))
  else
    MESSAGE=$(echo "$RESPONSE" | python3 -c "import json,sys; data=json.load(sys.stdin); print(data.get('message', 'Unknown error'))" 2>/dev/null)
    echo "❌ FAILED   [$API_PATH] — $FILENAME — $MESSAGE (Endpoint: $IMPORT_ENDPOINT)"
    FAILED=$((FAILED + 1))
  fi

done < <(tail -n +2 "$CSV_FILE")

# ── SUMMARY ──────────────────────────────────────────────────
echo ""
echo "======================================"
echo "  Import Complete!"
echo "  ✅ Success:  $SUCCESS"
echo "  ❌ Failed:   $FAILED"
echo "  ⚠️  Skipped:  $SKIPPED"
echo "======================================"