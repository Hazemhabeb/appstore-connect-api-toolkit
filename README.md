# App Store Connect API Toolkit

A ready-to-use toolkit for querying the **Apple App Store Connect API** — covering sales reports, analytics, customer reviews, builds, and more.

Includes a JWT generator, a full-suite shell test runner, and a pre-built Postman collection that works with any iOS/macOS app.

---

## What's Inside

| File | What it does |
|---|---|
| `generate_jwt.py` | Generates a signed Bearer token (valid 20 min) from your `.p8` key |
| `test_all_apis.sh` | Runs every endpoint in sequence with colored output |
| `AppStoreConnect_v4.postman_collection.json` | Postman collection — import and run immediately |
| `BACKEND_GUIDE.md` | Full reference: endpoints, variables, error codes, TSV format |
| `.env.example` | Credential template — copy to `.env` |

---

## Endpoints Covered

### Sales Reports
- **Daily downloads** — units per day by country and product type
- **Monthly downloads** — same, aggregated per month
- **Subscription report** — renewals, cancellations, introductory conversions *(monthly only)*

### Analytics Reports *(Admin key required)*
- **Activate** ongoing report generation for your app *(run once)*
- **Installs / Uninstalls / Active Devices** (`APP_STORE_ENGAGEMENT`)
- **Crash rates** by version and device (`APP_CRASHES`)
- **Impressions / Product Page Views / Downloads** (`APP_STORE_DISCOVERY`)
- **Sessions / Average Duration / Retention** (`APP_USAGE`)
- **Download presigned S3 URLs** for any report file

### App Info
- **Customer Reviews** — latest reviews with rating, body, and date
- **App Store Versions** — version history with submission status
- **Builds** — most recent TestFlight / App Store builds

---

## Quick Start

### 1. Prerequisites

```bash
pip install PyJWT cryptography
```

### 2. Get your credentials

Go to [App Store Connect → Users and Access → Integrations → API Keys](https://appstoreconnect.apple.com/access/api) and:

1. Click **+** to create a new key
2. Set **Access: Admin** *(required for analytics endpoints)*
3. Note your **Issuer ID** and **Key ID**
4. Download the `.p8` private key file *(you can only download it once)*

### 3. Configure

```bash
cp .env.example .env
```

Edit `.env`:

```env
ASC_ISSUER_ID=xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
ASC_KEY_ID=XXXXXXXXXX
ASC_VENDOR_NUMBER=12345678
ASC_APP_ID=1234567890
```

Place your `AuthKey_XXXXXXXXXX.p8` in the project root (same folder as the scripts).

### 4. Generate a token

```bash
python3 generate_jwt.py
```

```
 Bearer token (valid 20 min):

eyJhbGciOiJFUzI1NiIs...

 Copy into Postman → Collection Variables → bearer_token
```

### 5. Run all endpoints

```bash
chmod +x test_all_apis.sh
./test_all_apis.sh
```

Sample output:

```
╔══════════════════════════════════════════════════╗
║   App Store Connect API — Full Test Suite        ║
║   Vendor: 12345678  |  App: 1234567890           ║
╚══════════════════════════════════════════════════╝

┌─ SALES REPORTS ─────────────────────────────────┐

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
▶ 1 — Daily Downloads (2025-06-22)
  GET https://api.appstoreconnect.apple.com/v1/salesReports?...
  ✅  HTTP 200 — OK
  → Gzipped report file received (binary TSV — save to file to read)
```

---

## Postman Setup

1. Open Postman → **Import** → drag in `AppStoreConnect_v4.postman_collection.json`
2. Click the collection → **Variables** tab
3. Fill in `bearer_token`, `vendor_number`, `app_apple_id`, `daily_date`, `monthly_date`
4. Run requests in order: **1 → 2b → 3 → 4**

> Sales report responses look like garbled text in Postman — that is normal.
> The API returns gzip-compressed TSV. Use **Save Response → Save to file**, then `gunzip`.

---

## Reading Sales Reports

```bash
# After saving the response from Postman as report.tsv.gz:
gunzip report.tsv.gz
open report.tsv   # opens in Excel or Numbers on macOS
```

Key TSV columns:

| Column | Meaning |
|---|---|
| `Units` | Download / event count |
| `Product Type Identifier = 1` | First-time downloads |
| `Product Type Identifier = 1F` | Re-downloads |
| `Product Type Identifier = 7` | App updates |
| `Country Code` | Store country (e.g. `US`, `GB`) |

---

## Analytics: Admin Key Note

Requests 2, 3, and 4 require an API key with **Admin** access.  
If you see `403 Forbidden`, create a new key with Admin role in App Store Connect and update your `.env`.

---

## Error Reference

| HTTP | Meaning | Fix |
|---|---|---|
| `401` | Token expired | Re-run `generate_jwt.py` |
| `403` | Missing permission | Use an Admin API key |
| `404` | No data for this period | Normal if no activity that month |
| `410` | Date out of range | Daily: last 365 days · Monthly: last 12 months |
| `400` | Invalid parameter | Check date format: `YYYY-MM-DD` (daily) or `YYYY-MM` (monthly) |

---

## Security

- **Never commit** your `.p8` file or `.env` — both are in `.gitignore`
- Share the `.p8` file only via a password manager (1Password, Bitwarden, etc.)
- JWT tokens expire after 20 minutes — regenerate as needed

---

## Requirements

- Python 3.7+
- `pip install PyJWT cryptography`
- `bash` + `curl` (for `test_all_apis.sh`)
- [Postman](https://www.postman.com/downloads/) (optional)
- An App Store Connect account with API key access

---

## License

MIT
