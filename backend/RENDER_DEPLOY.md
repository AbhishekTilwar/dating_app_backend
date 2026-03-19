# Deploy API to Render (fix “wrong Firebase project” / KYC errors)

The Flutter app uses Firebase project **`dapp-79473`** (`google-services.json`). Render **must** verify ID tokens with a service account from **that same project**.

## KYC on Render (proper fix)

Photo verification uses **`@vladmandic/human`** with **`@tensorflow/tfjs-node`**, which ships **native Node addons**. On Render, the default **Node native runtime** often fails (missing `g++` / `make` / `python3`, or prebuild glibc mismatch), which surfaces as KYC / module errors in the app.

**Use Docker for the web service** (this repo includes `backend/Dockerfile` — Debian + toolchain + `npm ci`):

1. **Root directory:** set **Root Directory** to **`backend`** (monorepo — avoids shipping the whole repo into the build and scopes autodeploys).
2. **New service:** Runtime **Docker** → Dockerfile Path **`Dockerfile`** (relative to root dir) → Docker Context **`.`** → add env vars below → Deploy.
3. **Existing Node service:** Settings → **Root Directory** **`backend`** → change **Language** to **Docker** → Dockerfile **`Dockerfile`**, Context **`.`** → **Clear build cache** → **Manual Deploy**.

If you **do not** set a root directory (repo root as root), use Dockerfile Path **`backend/Dockerfile`** and Docker Context **`backend`** instead.

The root **`render.yaml`** blueprint uses **`rootDir: backend`**, **`dockerfilePath: ./Dockerfile`**, and **`dockerContext: .`**.

If you already have a Web Service (e.g. `dating-app-backend-…`), **change that service** to Docker as above instead of creating a second service, unless you intend to replace the URL in the Flutter app.

Optional native Node workaround (less reliable): keep Node runtime, set **`NODE_VERSION`** to **20** on Render, use root directory **`backend`**, build **`npm ci`**, and inspect logs for `node-gyp` / `tfjs` errors — if they persist, switch to Docker.

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
| `TRUST_PROXY` | `1` — use real client IP for rate limits (Render is behind a proxy). |
| `FIREBASE_STORAGE_BUCKET` | Optional. Your bucket is often `dapp-79473.firebasestorage.app` (see Storage in Console). The API tries that and `.appspot.com`. |

**KYC “default credentials” on Render:** the server writes `FIREBASE_SERVICE_ACCOUNT_JSON` to a temp file and sets `GOOGLE_APPLICATION_CREDENTIALS` so **Cloud Storage** can download the selfie (Auth alone was not enough for GCS).

KYC uses **Human.js + tfjs-node** (see **KYC on Render** above — deploy with **`backend/Dockerfile`**). Optional: `KYC_DEV_APPROVE=1` to skip face checks (dev/staging only).

## 3. Redeploy

After switching to Docker or changing env vars: **Manual Deploy**. If the previous image failed to compile native modules, use **Clear build cache** once, then deploy.

## Minify JSON (terminal)

```bash
cd backend && node -e "console.log(JSON.stringify(require('./service-account.json')))"
```

Paste output into `FIREBASE_SERVICE_ACCOUNT_JSON` on Render.
