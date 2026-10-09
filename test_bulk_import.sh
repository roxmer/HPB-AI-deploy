#!/bin/bash
#=============================================================
#   Smoke test for POST /api/bulk-import/hpb-multiomics.
#
#   Uploads the worked-example row already filled in on
#   "Research data/HPB_Multiomics_Bulk_Upload_Template.xlsx"
#   (patient IHPB-1, one radiology_reports row, one lab_draws row)
#   and prints back the per-patient import outcome.
#
#   Before running: in the app, Admin -> Role -> your role ->
#   grant BULK_IMPORT_C (and confirm EVENT_C / LAB_TEST_RESULT_C
#   are already granted). No logout/login needed after saving --
#   authorities are re-read from the DB on every request.
#
#   Usage:
#     chmod +x test_bulk_import.sh
#     ./test_bulk_import.sh [path/to/workbook.xlsx]
#
#   Credentials load from deploy_HPB/.env, same as the other test
#   scripts in this folder.
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

WORKBOOK="${1:-$SCRIPT_DIR/../Research data/HPB_Multiomics_Bulk_Upload_Template.xlsx}"
if [ ! -f "$WORKBOOK" ]; then
  echo "❌ Workbook not found: $WORKBOOK"
  echo "   Pass a path explicitly: ./test_bulk_import.sh /path/to/workbook.xlsx"
  exit 1
fi

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

echo "▶ Uploading $WORKBOOK ..."
RESP=$(curl -s -X POST "$BASE_URL/api/bulk-import/hpb-multiomics" \
  -H "Authorization: Bearer $TOKEN" \
  -F "excelFile=@${WORKBOOK}")

echo "$RESP" | python3 -m json.tool 2>/dev/null || echo "$RESP"
echo ""

echo "▶ Summary:"
echo "$RESP" | python3 -c "
import json, sys
try:
    d = json.load(sys.stdin)
except Exception as e:
    print(f'   Could not parse response as JSON: {e}')
    sys.exit(0)

if d.get('status') is False:
    print(f\"   ❌ Request failed: {d.get('message')}\")
    sys.exit(0)

result = d.get('data', {}).get('result', {})
fatal = result.get('fatalErrors', [])
if fatal:
    print('   ❌ Import aborted before any patient was processed:')
    for e in fatal:
        print(f'      - {e}')
    sys.exit(0)

print(f\"   Total rows:   {result.get('totalPatientRows')}\")
print(f\"   Imported:     {result.get('importedPatientCount')}\")
print(f\"   Failed:       {result.get('failedPatientCount')}\")
for w in result.get('warnings', []):
    print(f'   ⚠️  {w}')
for p in result.get('patients', []):
    status = '✅' if p.get('imported') else '❌'
    print(f\"   {status} {p.get('patientId')} (row {p.get('sourceRowNumber')}): \"
          f\"patientDbId={p.get('patientDbId')} rootEventsCreated={p.get('rootEventsCreated')}\")
    for err in p.get('errors', []):
        print(f'        - {err}')
"

echo ""
echo "=============================================="
echo "  Done. 'imported: true' + rootEventsCreated > 0"
echo "  for IHPB-1 means the import worked end-to-end."
echo "  Next: check tbl_event_log / tbl_sub_event_log"
echo "  rows exist for that patient, same as a manual"
echo "  event entry would produce (see below)."
echo "=============================================="
