# App Store Connect API — Integration Guide

This guide covers how to set up credentials, generate JWT tokens, use the Postman collection, and understand each API endpoint.

---

## Files Overview

| File | Purpose |
|---|---|
| `.env.example` | Template for your credentials — copy to `.env` |
| `AuthKey_XXXXXXXXXX.p8` | Your private key — **never commit this** |
| `generate_jwt.py` | Generates a Bearer token valid for 20 min |
| `test_all_apis.sh` | Runs all endpoints in one go (terminal) |
| `AppStoreConnect_v4.postman_collection.json` | All API requests pre-configured for Postman |

> **Security:** Never commit the `.p8` file to git or share it over Slack/email.
> Share it via a password manager (1Password, Bitwarden Send, etc.)

---

## Setup

### 1. Install Python dependencies

```bash
pip install PyJWT cryptography
```

### 2. Configure credentials

```bash
cp .env.example .env
```

Edit `.env` and fill in:
- `ASC_ISSUER_ID` — from App Store Connect → Users and Access → API Keys
- `ASC_KEY_ID` — the 10-character key ID shown next to your key
- `ASC_VENDOR_NUMBER` — from Agreements, Tax, and Banking or Reports
- `ASC_APP_ID` — numeric App ID from App Store Connect → App Information

### 3. Place the private key

Download your `.p8` file from App Store Connect and place it in this folder:

```
appstore-connect-api-toolkit/
├── AuthKey_XXXXXXXXXX.p8    ← place it here
├── .env                     ← your credentials (gitignored)
├── .env.example
├── generate_jwt.py
├── test_all_apis.sh
└── AppStoreConnect_v4.postman_collection.json
```

---

## Generating a Token

Run this every time you need a fresh token (valid for **20 minutes**):

```bash
python3 generate_jwt.py
```

Output:

```
 Bearer token (valid 20 min):

eyJhbGciOiJFUzI1NiIsImtpZCI6IlhYWFhYWFhYWFgi...

 Copy into Postman → Collection Variables → bearer_token
```

> If you get a `401 Unauthorized` in Postman, your token expired. Re-run `generate_jwt.py`.

---

## Running the Full Test Suite (Terminal)

```bash
chmod +x test_all_apis.sh
./test_all_apis.sh
```

The script auto-reads your `.env`, generates a JWT from the `.p8` file, then runs all endpoints in sequence with colored output.

---

## Postman Setup

### Import the collection

1. Open Postman
2. Click **Import** (top left)
3. Drag in `AppStoreConnect_v4.postman_collection.json`
4. The collection **"App Store Connect — Reporting Toolkit"** appears in the sidebar

### Configure variables

1. Click the collection name → **Variables** tab
2. Fill in:
   - `bearer_token` — paste from `generate_jwt.py`
   - `vendor_number` — your vendor number
   - `app_apple_id` — your app's numeric Apple ID
   - `daily_date` — e.g. `2025-06-15`
   - `monthly_date` — e.g. `2025-05`
3. Press **Cmd+S** (Mac) / **Ctrl+S** (Windows) to save

---

## Endpoint Reference

Run requests **in order** — Analytics requests depend on IDs from earlier responses.

### Sales Reports

These return gzip-compressed TSV files (not JSON).

| # | Name | Notes |
|---|---|---|
| 1 | Daily Downloads | `daily_date` variable, format `YYYY-MM-DD` |
| 1b | Monthly Downloads | `monthly_date` variable, format `YYYY-MM` |
| 1c | Subscription Report | Monthly only — `400` if you use a daily date |

### Analytics Reports

Require an **Admin** API key.

| # | Name | Notes |
|---|---|---|
| 2b | Get Existing Report Request ID | Check if already activated |
| 2 | Activate Analytics *(once)* | Creates ongoing report generation |
| 3 | List All Reports | Returns all report types; filter client-side |
| 4 | Get Report Download URL | Returns presigned S3 URL |

**Report types in Request 3:**

| `reportType` | Covers |
|---|---|
| `APP_STORE_ENGAGEMENT` | Installs, Uninstalls, Active Devices |
| `APP_CRASHES` | Crash counts by version and device |
| `APP_STORE_DISCOVERY` | Impressions, Product Page Views, Downloads |
| `APP_USAGE` | Sessions, Average Duration, Retention |

### App Info

| # | Name | Notes |
|---|---|---|
| 5 | Customer Reviews | Latest 20, sorted by date |
| 6 | App Store Versions | Status: `READY_FOR_SALE`, `IN_REVIEW`, etc. |
| 7 | Builds List | Latest 10 uploaded builds |

---

## Reading Sales Report Files

Sales reports return a gzip-compressed TSV — Postman shows garbled text, which is normal.

**Save and open:**
```bash
# In Postman: Send → Save Response → Save to file → save as report.tsv.gz
gunzip report.tsv.gz
open report.tsv   # opens in Excel or Numbers
```

**Key TSV columns:**

| Column | Meaning |
|---|---|
| `Units` | Download / event count |
| `Product Type Identifier = 1` | First-time downloads |
| `Product Type Identifier = 1F` | Re-downloads |
| `Product Type Identifier = 7` | App updates |
| `Country Code` | Store country (e.g. `US`, `GB`) |
| `Begin Date / End Date` | Report date range |

---

## Analytics Admin Key Setup

Analytics endpoints (2, 3, 4) return `403 Forbidden` if the API key lacks **Admin** access.

**To fix:**
1. App Store Connect → Users and Access → Integrations → API Keys
2. Click **+** → set **Access: Admin**
3. Download the new `.p8` file and update your `.env`

---

## Error Reference

| HTTP Status | Meaning | Fix |
|---|---|---|
| `200 OK` | Success | — |
| `201 Created` | Resource created | — |
| `401 Unauthorized` | Token expired | Re-run `generate_jwt.py`, update `bearer_token` |
| `403 Forbidden` | Key lacks permission | Create new Admin key |
| `404 Not Found` | No data for this period | Normal for subscription/analytics with no activity |
| `410 Gone` | Date out of range | Daily: last 365 days; Monthly: last 12 months |
| `400 Bad Request` | Invalid parameter | Check date format: daily `YYYY-MM-DD`, monthly `YYYY-MM` |

---

## Date Variables Reference

| Variable | Format | Example | Max Range |
|---|---|---|---|
| `daily_date` | `YYYY-MM-DD` | `2025-06-15` | Last 365 days |
| `monthly_date` | `YYYY-MM` | `2025-05` | Last 12 months |

Never use a future date — it returns `404` or `410`.
