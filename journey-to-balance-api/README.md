# Journey To Balance API (Cloudflare Worker)

Protected finance API for the Flutter app on the **Firebase Spark** plan (no Cloud Functions / Blaze).

Worker URL: `https://journey-to-balance-api.nu-clouds.workers.dev`

## Architecture

```text
Flutter → Firebase ID Token → Cloudflare Worker
  → verify token (UID from JWT)
  → Durable Object rate limit + idempotency (per UID)
  → validate + mutate Firestore
Flutter realtime listeners sync UI
```

## Rate limiting (Workers Free)

Uses **SQLite-backed Durable Objects** (available on Cloudflare Workers Free).

- One Durable Object per Firebase UID (`idFromName(uid)`)
- Requests to the same UID are serialized → safe fixed 60s windows
- Operation bucket + general (60/min) bucket

**Not used:** Workers KV for counters (eventually consistent; Free write limits too low).

## Setup secrets (required before finance works)

1. Firebase Console → Project settings → Service accounts → Generate new private key
2. Grant the service account access to Firestore (Editor or Cloud Datastore User)
3. Grant the same service account **Firebase Authentication Admin** so the
   password-reset endpoints can look up users, update passwords, and revoke
   refresh tokens through Identity Toolkit.
4. Set secrets:

```bash
cd journey-to-balance-api
npx wrangler secret put FIREBASE_PROJECT_ID
# value: journey-to-balance

npx wrangler secret put FIREBASE_SERVICE_ACCOUNT_JSON
# paste the full JSON file contents

npx wrangler secret put BREVO_API_KEY
# Brevo Transactional Email API key for Forgot PIN emails

npx wrangler secret put BREVO_SENDER_EMAIL
# email address for a verified Brevo sender

npx wrangler secret put BREVO_SENDER_NAME
# sender name shown on Forgot PIN emails
```

Local dev (never commit):

```bash
cp .dev.vars.example .dev.vars
# fill FIREBASE_PROJECT_ID and FIREBASE_SERVICE_ACCOUNT_JSON
npx wrangler dev
```

## Deploy

```bash
cd journey-to-balance-api
npm install
npx wrangler deploy
```

## Endpoints

Public password-reset routes do not require a Firebase ID token. Request
responses are intentionally neutral to prevent account enumeration.

| Path | Purpose |
|------|---------|
| `POST /auth/password-reset/request` | Request a six-digit email code |
| `POST /auth/password-reset/verify` | Exchange a valid code for a short-lived reset token |
| `POST /auth/password-reset/confirm` | Set the new password and revoke refresh tokens |

They reuse `USER_GATE`, `FIREBASE_PROJECT_ID`,
`FIREBASE_SERVICE_ACCOUNT_JSON`, and the existing Brevo secrets. No additional
binding or secret is required.

All finance routes: `POST` + `Authorization: Bearer <Firebase ID token>`

| Path | Rate bucket |
|------|-------------|
| `/api/auth/forgot-pin/request` | 3/min |
| `/api/auth/forgot-pin/verify` | 10/min |
| `/api/finance/receive-salary` | 10/min |
| `/api/finance/add-money` | 20/min |
| `/api/finance/update-available-balance` | 20/min |
| `/api/finance/update-percentages` | 10/min |
| `/api/finance/update-monthly-salary` | 20/min |
| `/api/finance/add-transaction` | 30/min |
| `/api/finance/update-transaction` | 30/min |
| `/api/finance/delete-transaction` | 20/min |
| `/api/finance/contribute-to-savings-goal` | 20/min |
| `/api/finance/update-savings-goal-settings` | 20/min |

Rate exceeded → **HTTP 429** `{ error: { code: "resource-exhausted", message: "..." } }`

## Status

Rate limiting is **active only after** this Worker is deployed with secrets configured and a 429 test succeeds.
The Firebase Cloud Functions code under `/functions` is kept for reference and is not used on Spark.
