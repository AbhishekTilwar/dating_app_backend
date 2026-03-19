# Dating app backend (Spark API)

Node.js + Express API for the Crossed dating app: Firebase Auth verification, Firestore, Storage, and KYC identity verification using **@vladmandic/human** (local gender detection). On the server this pulls in **@tensorflow/tfjs-node** (declared in `package.json`) — without it, KYC fails with `Cannot find module '@tensorflow/tfjs-node'`.

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
| `KYC_DEV_APPROVE=1` | Skip face gender check in local dev (approve all selfies) |

See `.env.example` for full list.

## Scaling & concurrency (built-in)

The API is stateless per instance; scale **horizontally** on your host (e.g. multiple Render instances). Firestore handles data concurrency.

| Mechanism | Purpose |
|-----------|---------|
| **`helmet`** | Sensible security headers |
| **Global rate limit** | Per-IP cap (15 min window); `/health` is excluded |
| **Discovery rate limit** | Per authenticated user / minute (heavy Firestore reads) |
| **KYC rate limit** | Per user / hour + **semaphore** limiting parallel face-detection jobs per instance |
| **Discovery prep cache** | Short TTL LRU for exclusion + incoming-like queries; **busted** on pass / like / block |
| **Firestore `.select()`** | Smaller reads for discovery candidates and swipe exclusion queries |
| **`getAll` batching** | Matches list + rooms list fetch owner profiles in chunks, not N sequential reads |
| **`TRUST_PROXY=1`** | Use real client IP behind Render/nginx (required for accurate rate limits) |

### Render: fix KYC / “wrong Firebase project”

Set **`FIREBASE_SERVICE_ACCOUNT_JSON`** to the full service account JSON from Firebase project **`dapp-79473`** (same as the app’s `google-services.json`). See **`RENDER_DEPLOY.md`** in this folder.

## API (Bearer: Firebase ID token)

- `GET /health` — Health check
- `GET/PUT /api/users/me` — Current user profile
- `GET /api/discovery` — Discovery feed
- `POST /api/likes`, `POST /api/passes` — Swipe actions
- `GET /api/matches` — Matches
- `POST /api/matches/:matchId/unmatch` — Remove chat for both + block
- `GET/POST /api/chats/:matchId/messages` — Chat
- `POST /api/reports`, `POST /api/blocks` — Safety (block also removes an existing 1:1 match chat)
- KYC and rooms routes as implemented in `src/index.js`

## Firestore indexes (Meetup)

The Meetup (rooms) discovery query uses a composite index on `status` + `eventAt`. If you see **"The query requires an index"** in the app:

1. From the **project root** (where `firebase.json` and `firestore.indexes.json` live), run:
   ```bash
   firebase deploy --only firestore:indexes
   ```
   (Requires [Firebase CLI](https://firebase.google.com/docs/cli) and `firebase use dapp-79473` or your project.)

2. Or click the link in the error message in the app to create the index in Firebase Console. Wait until the index status is **Ready**, then tap **Retry** in the Meetup screen.

## Scripts

- `npm start` — Production
- `npm run dev` — Dev with `--watch`

## License

Private / your project terms.
