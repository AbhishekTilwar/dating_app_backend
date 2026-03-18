# Deploy API to Render (fix “wrong Firebase project” / KYC errors)

The Flutter app uses Firebase project **`dapp-79473`** (`google-services.json`). Render **must** verify ID tokens with a service account from **that same project**.

## 1. Download the key

1. [Firebase Console](https://console.firebase.google.com) → project **dapp-79473**
2. ⚙️ Project settings → **Service accounts**
3. **Generate new private key** → save the JSON file (do not commit it)

## 2. Render environment variables

Open your Web Service → **Environment**:

| Key | Value |
|-----|--------|
| `FIREBASE_SERVICE_ACCOUNT_JSON` | **Entire contents** of the JSON file, as **one line** (minify with the command below) |
| `GCLOUD_PROJECT` | `dapp-79473` |
| `FIREBASE_STORAGE_BUCKET` | `dapp-79473.firebasestorage.app` |

Optional: `AWS_*` for Rekognition, or `KYC_DEV_APPROVE=1`.

## 3. Redeploy

**Manual Deploy** on Render after saving env vars.

## Minify JSON (terminal)

```bash
cd backend && node -e "console.log(JSON.stringify(require('./service-account.json')))"
```

Paste output into `FIREBASE_SERVICE_ACCOUNT_JSON` on Render.
