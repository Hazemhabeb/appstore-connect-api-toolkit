#!/bin/bash
# App Store Connect API — Full Test Suite
# Loads credentials from .env (copy .env.example → .env and fill in your values)

SCRIPT_DIR="$(dirname "$0")"

# ── Load .env ──────────────────────────────────────────────────────────────────
if [ -f "$SCRIPT_DIR/.env" ]; then
  export $(grep -v '^#' "$SCRIPT_DIR/.env" | xargs)
fi

# ── Configuration ──────────────────────────────────────────────────────────────
ISSUER_ID="${ASC_ISSUER_ID:-}"
KEY_ID="${ASC_KEY_ID:-}"
VENDOR="${ASC_VENDOR_NUMBER:-}"
APP_ID="${ASC_APP_ID:-}"
DAILY_DATE="${ASC_DAILY_DATE:-$(date -v-1d +%Y-%m-%d 2>/dev/null || date -d yesterday +%Y-%m-%d)}"
MONTHLY_DATE="${ASC_MONTHLY_DATE:-$(date -v-1m +%Y-%m 2>/dev/null || date -d 'last month' +%Y-%m)}"
P8_PATH="${ASC_KEY_PATH:-$SCRIPT_DIR/AuthKey_${KEY_ID}.p8}"
BASE="https://api.appstoreconnect.apple.com"

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# ── Validate required config ───────────────────────────────────────────────────
if [ -z "$ISSUER_ID" ] || [ -z "$KEY_ID" ] || [ -z "$VENDOR" ] || [ -z "$APP_ID" ]; then
  echo -e "${RED}Error: Missing required credentials.${NC}"
  echo -e "Copy ${YELLOW}.env.example${NC} → ${YELLOW}.env${NC} and fill in:"
  echo -e "  ASC_ISSUER_ID, ASC_KEY_ID, ASC_VENDOR_NUMBER, ASC_APP_ID"
  exit 1
fi

# ── Auto-generate JWT if .p8 is present ───────────────────────────────────────
if [ -f "$P8_PATH" ]; then
  TOKEN=$(python3 - <<PYEOF
import jwt, time, sys
with open("$P8_PATH") as f:
    key = f.read()
now = int(time.time())
print(jwt.encode(
    {"iss": "$ISSUER_ID", "iat": now, "exp": now + 1200, "aud": "appstoreconnect-v1"},
    key, algorithm="ES256", headers={"kid": "$KEY_ID"}
))
PYEOF
)
  if [ -z "$TOKEN" ]; then
    echo -e "${RED}Failed to generate JWT. Is PyJWT installed? (pip install PyJWT cryptography)${NC}"
    exit 1
  fi
  echo -e "${GREEN}✅  JWT generated from $P8_PATH (valid 20 min)${NC}"
else
  TOKEN="${ASC_BEARER_TOKEN:-}"
  echo -e "${YELLOW}⚠️  $P8_PATH not found — trying ASC_BEARER_TOKEN from .env${NC}"
  if [ -z "$TOKEN" ] || [ "$TOKEN" = "PASTE_JWT_HERE" ]; then
    echo -e "${RED}❌  No token available. Place your .p8 file or set ASC_BEARER_TOKEN in .env${NC}"
    exit 1
  fi
fi

REPORT_REQUEST_ID=""
REPORT_ID=""

call() {
  local NAME="$1"
  local METHOD="$2"
  local URL="$3"
  local BODY="$4"

  echo ""
  echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  echo -e "${YELLOW}▶ $NAME${NC}"
  echo -e "  $METHOD $URL"

  if [ "$METHOD" = "POST" ]; then
    RESPONSE=$(curl -s -w "\n__STATUS__%{http_code}" \
      -X POST \
      -H "Authorization: Bearer $TOKEN" \
      -H "Content-Type: application/json" \
      -d "$BODY" \
      "$URL")
  else
    RESPONSE=$(curl -s -w "\n__STATUS__%{http_code}" \
      -H "Authorization: Bearer $TOKEN" \
      -H "Accept-Encoding: gzip" \
      --compressed \
      "$URL")
  fi

  STATUS=$(echo "$RESPONSE" | grep "__STATUS__" | sed 's/__STATUS__//')
  BODY_OUT=$(echo "$RESPONSE" | grep -v "__STATUS__")

  if [[ "$STATUS" == "200" || "$STATUS" == "201" ]]; then
    echo -e "  ${GREEN}✅  HTTP $STATUS — OK${NC}"
    echo "$BODY_OUT" | python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
    if 'data' in d:
        data = d['data']
        if isinstance(data, list):
            print(f'  → {len(data)} item(s) returned')
            if len(data) > 0:
                print(f'  → First item id: {data[0].get(\"id\",\"n/a\")}')
                print(f'  → First item type: {data[0].get(\"type\",\"n/a\")}')
        else:
            print(f'  → id: {data.get(\"id\",\"n/a\")}')
            print(f'  → type: {data.get(\"type\",\"n/a\")}')
    elif 'errors' in d:
        for e in d['errors']:
            print(f'  → Error: {e.get(\"title\")} — {e.get(\"detail\")}')
except Exception:
    print('  → Gzipped report file received (binary TSV — save to file to read)')
" 2>/dev/null || echo "  → Gzipped report file received (binary TSV — save to file to read)"
  elif [[ "$STATUS" == "404" ]]; then
    DETAIL=$(echo "$BODY_OUT" | python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
    for e in d.get('errors', []):
        print(e.get('detail',''))
except: pass
" 2>/dev/null)
    if echo "$DETAIL" | grep -qi "no report is available\|no data"; then
      echo -e "  ${YELLOW}ℹ️   HTTP 404 — No data for this period (expected if no activity)${NC}"
      echo -e "  → $DETAIL"
    else
      echo -e "  ${RED}❌  HTTP 404 — Not found. Check IDs in URL.${NC}"
      echo "$BODY_OUT" | python3 -c "import sys,json; d=json.load(sys.stdin); [print(f'  → {e[\"title\"]}: {e[\"detail\"]}') for e in d.get('errors',[])]" 2>/dev/null
    fi
  elif [[ "$STATUS" == "410" ]]; then
    echo -e "  ${RED}❌  HTTP 410 — Date out of range. Update ASC_DAILY_DATE or ASC_MONTHLY_DATE in .env${NC}"
  elif [[ "$STATUS" == "401" ]]; then
    echo -e "  ${RED}❌  HTTP 401 — Token expired. Re-run the script (auto-generates a new JWT if .p8 is present).${NC}"
  elif [[ "$STATUS" == "403" ]]; then
    echo -e "  ${RED}❌  HTTP 403 — Forbidden.${NC}"
    echo "$BODY_OUT" | python3 -c "import sys,json; d=json.load(sys.stdin); [print(f'  → {e[\"title\"]}: {e[\"detail\"]}') for e in d.get('errors',[])]" 2>/dev/null
    echo -e "  ${YELLOW}  Fix: In App Store Connect → Users and Access → Integrations → API Keys,${NC}"
    echo -e "  ${YELLOW}  create a new key with 'Admin' access and update your .env file.${NC}"
  else
    echo -e "  ${RED}❌  HTTP $STATUS${NC}"
    echo "$BODY_OUT" | python3 -c "import sys,json; d=json.load(sys.stdin); [print(f'  → {e[\"title\"]}: {e[\"detail\"]}') for e in d.get('errors',[])]" 2>/dev/null
  fi
}

echo ""
echo -e "${BLUE}╔══════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║   App Store Connect API — Full Test Suite        ║${NC}"
echo -e "${BLUE}║   Vendor: $VENDOR  |  App: $APP_ID              ║${NC}"
echo -e "${BLUE}╚══════════════════════════════════════════════════╝${NC}"

# ── SALES REPORTS ──────────────────────────────────────────────────────────────

echo ""
echo -e "${BLUE}┌─ SALES REPORTS ─────────────────────────────────┐${NC}"

call "1 — Daily Downloads ($DAILY_DATE)" GET \
  "$BASE/v1/salesReports?filter%5BreportType%5D=SALES&filter%5BreportSubType%5D=SUMMARY&filter%5Bfrequency%5D=DAILY&filter%5BvendorNumber%5D=$VENDOR&filter%5BreportDate%5D=$DAILY_DATE"

call "1b — Monthly Downloads ($MONTHLY_DATE)" GET \
  "$BASE/v1/salesReports?filter%5BreportType%5D=SALES&filter%5BreportSubType%5D=SUMMARY&filter%5Bfrequency%5D=MONTHLY&filter%5BvendorNumber%5D=$VENDOR&filter%5BreportDate%5D=$MONTHLY_DATE"

# SUBSCRIPTION reports are MONTHLY only — DAILY returns a misleading 400
call "1c — Subscription Report ($MONTHLY_DATE)" GET \
  "$BASE/v1/salesReports?filter%5BreportType%5D=SUBSCRIPTION&filter%5BreportSubType%5D=SUMMARY&filter%5Bfrequency%5D=MONTHLY&filter%5BvendorNumber%5D=$VENDOR&filter%5BreportDate%5D=$MONTHLY_DATE"

# ── ANALYTICS REPORTS ──────────────────────────────────────────────────────────

echo ""
echo -e "${BLUE}┌─ ANALYTICS REPORTS ─────────────────────────────┐${NC}"

call "2b — Get Existing Report Request ID" GET \
  "$BASE/v1/apps/$APP_ID/analyticsReportRequests"

RRID_RESPONSE=$(curl -s \
  -H "Authorization: Bearer $TOKEN" \
  "$BASE/v1/apps/$APP_ID/analyticsReportRequests")

REPORT_REQUEST_ID=$(echo "$RRID_RESPONSE" | python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
    data = d.get('data', [])
    if data:
        print(data[0]['id'])
except:
    pass
" 2>/dev/null)

if [ -z "$REPORT_REQUEST_ID" ]; then
  echo ""
  echo -e "  ${YELLOW}⚠️  No existing report request found. Running Request 2 to activate...${NC}"
  ACTIVATE_BODY="{\"data\":{\"type\":\"analyticsReportRequests\",\"attributes\":{\"accessType\":\"ONGOING\"},\"relationships\":{\"app\":{\"data\":{\"type\":\"apps\",\"id\":\"$APP_ID\"}}}}}"
  call "2 — Activate Analytics Reports" POST \
    "$BASE/v1/analyticsReportRequests" \
    "$ACTIVATE_BODY"

  ACTIVATE_RESPONSE=$(curl -s -X POST \
    -H "Authorization: Bearer $TOKEN" \
    -H "Content-Type: application/json" \
    -d "$ACTIVATE_BODY" \
    "$BASE/v1/analyticsReportRequests")

  REPORT_REQUEST_ID=$(echo "$ACTIVATE_RESPONSE" | python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
    print(d['data']['id'])
except:
    pass
" 2>/dev/null)
fi

if [ -n "$REPORT_REQUEST_ID" ]; then
  echo ""
  echo -e "  ${GREEN}✅  report_request_id: $REPORT_REQUEST_ID${NC}"

  call "3a — Installs + Active Devices + Uninstalls" GET \
    "$BASE/v1/analyticsReportRequests/$REPORT_REQUEST_ID/reports?filter%5BreportType%5D=APP_STORE_ENGAGEMENT"

  call "3b — Crashes" GET \
    "$BASE/v1/analyticsReportRequests/$REPORT_REQUEST_ID/reports?filter%5BreportType%5D=APP_CRASHES"

  call "3c — Impressions + Downloads" GET \
    "$BASE/v1/analyticsReportRequests/$REPORT_REQUEST_ID/reports?filter%5BreportType%5D=APP_STORE_DISCOVERY"

  call "3d — Sessions + Retention" GET \
    "$BASE/v1/analyticsReportRequests/$REPORT_REQUEST_ID/reports?filter%5BreportType%5D=APP_USAGE"

  REPORT_ID=$(curl -s \
    -H "Authorization: Bearer $TOKEN" \
    "$BASE/v1/analyticsReportRequests/$REPORT_REQUEST_ID/reports?filter%5BreportType%5D=APP_STORE_ENGAGEMENT" | \
    python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
    data = d.get('data', [])
    if data: print(data[0]['id'])
except: pass
" 2>/dev/null)

  if [ -n "$REPORT_ID" ]; then
    echo ""
    echo -e "  ${GREEN}✅  report_id: $REPORT_ID${NC}"
    call "4 — Get Download URL for Engagement Report" GET \
      "$BASE/v1/analyticsReports/$REPORT_ID/segments"
  else
    echo ""
    echo -e "  ${YELLOW}⚠️  No report_id found — reports may still be generating (up to 24h after first activation)${NC}"
  fi
else
  echo ""
  echo -e "  ${RED}❌  Could not get or create report_request_id.${NC}"
  echo -e "  ${YELLOW}  The API key needs 'Admin' access to activate analytics.${NC}"
  echo -e "  ${YELLOW}  Go to: App Store Connect → Users and Access → Integrations → API Keys${NC}"
fi

# ── APP INFO ───────────────────────────────────────────────────────────────────

echo ""
echo -e "${BLUE}┌─ APP INFO ───────────────────────────────────────┐${NC}"

call "5 — Customer Reviews" GET \
  "$BASE/v1/apps/$APP_ID/customerReviews?sort=-createdDate&limit=5"

call "6 — App Store Versions" GET \
  "$BASE/v1/apps/$APP_ID/appStoreVersions"

call "7 — Builds List" GET \
  "$BASE/v1/apps/$APP_ID/builds?limit=5"

echo ""
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN}Test suite complete.${NC}"
echo ""
