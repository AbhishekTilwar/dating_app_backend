# Dating app backend (Spark API)

Node.js + Express API for the Crossed dating app: Firebase Auth verification, Firestore, Storage, optional AWS Rekognition for KYC.

## Prerequisites

- **Node.js** 18+
- Firebase project (Firestore + Storage)
- Service account JSON from Firebase Console → Project settings → Service accounts

## Setup

```bash
npm install
cp .env.example .env
# Edit .env: GCLOUD_PROJECT, GOOGLE_APPLICATION_CREDENTIALS, FIREBASE_STORAGE_BUCKET, etc.
npm run dev
```

## Environment variables

| Variable | Description |
|----------|-------------|
| `PORT` | Server port (default `8080`) |
| `GCLOUD_PROJECT` | Firebase / GCP project ID |
| `GOOGLE_APPLICATION_CREDENTIALS` | Path to service account JSON |
| `FIREBASE_STORAGE_BUCKET` | e.g. `your-project.appspot.com` |
| `KYC_DEV_APPROVE=1` | Skip Rekognition in local dev |
| `AWS_*` | For production KYC face gender check |

See `.env.example` for full list.

### Render: fix KYC / “wrong Firebase project”

Set **`FIREBASE_SERVICE_ACCOUNT_JSON`** to the full service account JSON from Firebase project **`dapp-79473`** (same as the app’s `google-services.json`). See **`RENDER_DEPLOY.md`** in this folder.

## API (Bearer: Firebase ID token)

- `GET /health` — Health check
- `GET/PUT /api/users/me` — Current user profile
- `GET /api/discovery` — Discovery feed
- `POST /api/likes`, `POST /api/passes` — Swipe actions
- `GET /api/matches` — Matches
- `GET/POST /api/chats/:matchId/messages` — Chat
- `POST /api/reports`, `POST /api/blocks` — Safety
- KYC and rooms routes as implemented in `src/index.js`

## Scripts

- `npm start` — Production
- `npm run dev` — Dev with `--watch`

## License

Private / your project terms.
