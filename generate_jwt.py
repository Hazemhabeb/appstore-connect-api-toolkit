#!/usr/bin/env python3
"""
App Store Connect JWT Generator
Run: python3 generate_jwt.py
Requires: pip install PyJWT cryptography

Set credentials via environment variables or a .env file:
  ASC_ISSUER_ID   — from App Store Connect → Users and Access → API Keys
  ASC_KEY_ID      — the 10-character key ID (e.g. XXXXXXXXXX)
  ASC_KEY_PATH    — path to your .p8 file (default: ./AuthKey_<KEY_ID>.p8)
"""
import jwt, time, sys, os

def load_env(path=".env"):
    """Load key=value pairs from .env if present."""
    if os.path.exists(path):
        with open(path) as f:
            for line in f:
                line = line.strip()
                if line and not line.startswith("#") and "=" in line:
                    k, v = line.split("=", 1)
                    os.environ.setdefault(k.strip(), v.strip())

load_env()

ISSUER_ID = os.environ.get("ASC_ISSUER_ID", "")
KEY_ID    = os.environ.get("ASC_KEY_ID", "")
P8_PATH   = os.environ.get("ASC_KEY_PATH",
            os.path.join(os.path.dirname(__file__), f"AuthKey_{KEY_ID}.p8"))

if not ISSUER_ID or not KEY_ID:
    print("Error: ASC_ISSUER_ID and ASC_KEY_ID must be set.")
    print("Copy .env.example → .env and fill in your credentials.")
    sys.exit(1)

try:
    with open(P8_PATH, "r") as f:
        private_key = f.read()
except FileNotFoundError:
    print(f"Cannot find {P8_PATH}")
    print(f"Place your AuthKey_{KEY_ID}.p8 file in this folder (or set ASC_KEY_PATH).")
    sys.exit(1)

now = int(time.time())
token = jwt.encode(
    payload={
        "iss": ISSUER_ID,
        "iat": now,
        "exp": now + 1200,
        "aud": "appstoreconnect-v1"
    },
    key=private_key,
    algorithm="ES256",
    headers={"kid": KEY_ID}
)

print("\n Bearer token (valid 20 min):\n")
print(token)
print("\n Copy into Postman → Collection Variables → bearer_token\n")
