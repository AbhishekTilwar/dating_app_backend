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
| `FIREBASE_SERVICE_ACCOUNT_JSON` | **Entire contents** of the JSON file, as **one line** (minify: remove newlines) or paste in Render’s multiline secret field if available |
| `GCLOUD_PROJECT` | `dapp-79473` |
| `FIREBASE_STORAGE_BUCKET` | `dapp-79473.firebasestorage.app` |
| `PORT` | `8080` (Render sets this automatically; optional) |

Optional for KYC (face check): `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, `AWS_REGION`, or `KYC_DEV_APPROVE=1` to skip Rekognition in dev.

## 3. Redeploy

**Manual Deploy** → Clear build cache (optional) → Deploy.

After deploy, the app’s selfie step should succeed (no “wrong Firebase project”).

## Minify JSON for one-line paste (terminal)

```bash
node -e "console.log(JSON.stringify(require('./service-account.json')))"
```

Copy the output into `FIREBASE_SERVICE_ACCOUNT_JSON` on Render.
