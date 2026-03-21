import express from 'express';
import cors from 'cors';
import helmet from 'helmet';
import rateLimit, { ipKeyGenerator } from 'express-rate-limit';
import dotenv from 'dotenv';
import multer from 'multer';
import { initializeApp, getApps, cert } from 'firebase-admin/app';
import { getFirestore } from 'firebase-admin/firestore';
import { getAuth } from 'firebase-admin/auth';
import { getStorage } from 'firebase-admin/storage';
import { readFileSync, writeFileSync, existsSync } from 'fs';
import { join, dirname } from 'path';
import { tmpdir } from 'os';
import { fileURLToPath } from 'url';

dotenv.config();

const __dirname = dirname(fileURLToPath(import.meta.url));

/** Set during Firebase init — used to try both *.appspot.com and *.firebasestorage.app for KYC downloads. */
let firebaseProjectId = 'dapp-79473';

function kycStorageBucketCandidates() {
  const env = process.env.FIREBASE_STORAGE_BUCKET?.trim();
  const pid = firebaseProjectId;
  // New projects often use *.firebasestorage.app (matches google-services storage_bucket).
  const names = [env, `${pid}.firebasestorage.app`, `${pid}.appspot.com`].filter(Boolean);
  return [...new Set(names)];
}

/** Client uploads to project default bucket; Admin SDK bucket id is often *.appspot.com even when google-services shows *.firebasestorage.app */
async function downloadKycSelfie(uid) {
  const objectPath = `users/${uid}/kyc/face.jpg`;
  let lastErr = null;
  for (const bucketName of kycStorageBucketCandidates()) {
    try {
      const file = getStorage().bucket(bucketName).file(objectPath);
      const [exists] = await file.exists();
      if (!exists) continue;
      const [buf] = await file.download();
      if (buf?.length) {
        console.info(`[kyc] selfie from bucket ${bucketName}`);
        return buf;
      }
    } catch (e) {
      lastErr = e;
      console.warn(`[kyc] bucket ${bucketName}:`, e?.message || e);
    }
  }
  if (lastErr) throw lastErr;
  return null;
}

function resolveFirebaseCredentialsPath() {
  const placeholder = /path-to-service-account|placeholder/i;
  const envRaw = process.env.GOOGLE_APPLICATION_CREDENTIALS?.trim();
  if (envRaw && !placeholder.test(envRaw)) {
    const p = envRaw.startsWith('/') ? envRaw : join(process.cwd(), envRaw);
    if (existsSync(p)) return p;
  }
  let dir = process.cwd();
  for (let i = 0; i < 40; i++) {
    const f = join(dir, 'service-account.json');
    if (existsSync(f)) return f;
    const parent = dirname(dir);
    if (parent === dir) break;
    dir = parent;
  }
  const besideSrc = join(__dirname, '..', 'service-account.json');
  return existsSync(besideSrc) ? besideSrc : null;
}

/** Service account: Render/hosting should set FIREBASE_SERVICE_ACCOUNT_JSON (full JSON string). */
function loadServiceAccountJson() {
  const raw = process.env.FIREBASE_SERVICE_ACCOUNT_JSON?.trim();
  if (raw) {
    try {
      return JSON.parse(raw);
    } catch (e) {
      console.error('[firebase] FIREBASE_SERVICE_ACCOUNT_JSON is not valid JSON:', e.message);
      throw new Error('Invalid FIREBASE_SERVICE_ACCOUNT_JSON');
    }
  }
  const credPath = resolveFirebaseCredentialsPath();
  if (credPath) {
    return JSON.parse(readFileSync(credPath, 'utf8'));
  }
  return null;
}

const app = express();

// Render / nginx / Cloud Load Balancer: use X-Forwarded-For for rate limits
if (process.env.TRUST_PROXY === '1' || process.env.NODE_ENV === 'production') {
  app.set('trust proxy', Number(process.env.TRUST_PROXY_HOPS || 1));
}

app.use(
  helmet({
    crossOriginResourcePolicy: { policy: 'cross-origin' },
  }),
);
app.use(cors({ origin: true }));
app.use(express.json({ limit: '12mb' }));

/** Global API throttle (per IP). Skips health checks. */
const globalLimiter = rateLimit({
  windowMs: 15 * 60 * 1000,
  max: Number(process.env.RATE_LIMIT_GLOBAL_MAX || 800),
  standardHeaders: true,
  legacyHeaders: false,
  skip: (req) => req.path === '/health',
  message: { error: 'Too many requests. Try again shortly.' },
});
app.use(globalLimiter);

/** Discovery: expensive Firestore reads — per user after auth. */
const discoveryLimiter = rateLimit({
  windowMs: 60 * 1000,
  max: Number(process.env.RATE_LIMIT_DISCOVERY_MAX || 45),
  standardHeaders: true,
  legacyHeaders: false,
  keyGenerator: (req) =>
    req.uid ? req.uid : ipKeyGenerator(req.ip ?? '0.0.0.0'),
  message: { error: 'Too many discovery refreshes. Wait a minute.' },
});

/** KYC uses CPU-heavy local inference — cap per user per hour. */
const kycLimiter = rateLimit({
  windowMs: 60 * 60 * 1000,
  max: Number(process.env.RATE_LIMIT_KYC_MAX || 20),
  standardHeaders: true,
  legacyHeaders: false,
  keyGenerator: (req) =>
    req.uid ? req.uid : ipKeyGenerator(req.ip ?? '0.0.0.0'),
  message: { error: 'Too many verification attempts. Try again later.' },
});

/** Short TTL cache for discovery/nearby exclusion + incoming-like maps (cuts Firestore churn). */
class TtlLruCache {
  constructor(maxEntries, ttlMs) {
    this.maxEntries = maxEntries;
    this.ttlMs = ttlMs;
    this.map = new Map();
  }
  get(key) {
    const e = this.map.get(key);
    if (!e) return undefined;
    if (Date.now() > e.expiresAt) {
      this.map.delete(key);
      return undefined;
    }
    this.map.delete(key);
    this.map.set(key, e);
    return e.value;
  }
  set(key, value) {
    if (this.map.has(key)) this.map.delete(key);
    while (this.map.size >= this.maxEntries) {
      const first = this.map.keys().next().value;
      this.map.delete(first);
    }
    this.map.set(key, { value, expiresAt: Date.now() + this.ttlMs });
  }
  delete(key) {
    this.map.delete(key);
  }
}

const discoveryCacheTtlMs = Number(process.env.DISCOVERY_CACHE_TTL_MS || 20000);
const discoveryCacheMax = Number(process.env.DISCOVERY_CACHE_MAX_ENTRIES || 8000);
const discoveryPrepCache = new TtlLruCache(discoveryCacheMax, discoveryCacheTtlMs);

/** After pass/like/block, drop cached exclusion/incoming-like maps for affected users. */
function bustDiscoveryPrepCacheForUsers(...uids) {
  for (const uid of uids) {
    if (!uid) continue;
    discoveryPrepCache.delete(`excl:${uid}`);
    discoveryPrepCache.delete(`inlike:${uid}`);
  }
}

/** Limit parallel Human.js face runs so one instance doesn’t melt under spikes. */
class Semaphore {
  constructor(max) {
    this.max = max;
    this.active = 0;
    this.waiters = [];
  }
  acquire() {
    return new Promise((resolve) => {
      const tryTake = () => {
        if (this.active < this.max) {
          this.active++;
          resolve();
        } else {
          this.waiters.push(tryTake);
        }
      };
      tryTake();
    });
  }
  release() {
    this.active = Math.max(0, this.active - 1);
    const w = this.waiters.shift();
    if (w) w();
  }
}

const kycMaxConcurrent = Math.max(1, Number(process.env.KYC_MAX_CONCURRENT || 2));
const kycSemaphore = new Semaphore(kycMaxConcurrent);

const kycSelfieUpload = multer({
  storage: multer.memoryStorage(),
  limits: { fileSize: 4 * 1024 * 1024 },
});

if (!getApps().length) {
  // Cloud Storage (@google-cloud/storage) needs Application Default Credentials on Render.
  // FIREBASE_SERVICE_ACCOUNT_JSON alone + cert() verifies Auth tokens but Storage often still
  // looks for GOOGLE_APPLICATION_CREDENTIALS — write JSON to a temp file so GCS can auth.
  const jsonEnv = process.env.FIREBASE_SERVICE_ACCOUNT_JSON?.trim();
  if (jsonEnv) {
    try {
      JSON.parse(jsonEnv);
    } catch (e) {
      console.error('[firebase] FIREBASE_SERVICE_ACCOUNT_JSON is not valid JSON');
      throw e;
    }
    const tmpCred = join(tmpdir(), 'firebase-admin-credentials.json');
    writeFileSync(tmpCred, jsonEnv, { encoding: 'utf8', mode: 0o600 });
    process.env.GOOGLE_APPLICATION_CREDENTIALS = tmpCred;
  } else {
    const fileCred = resolveFirebaseCredentialsPath();
    if (fileCred) {
      process.env.GOOGLE_APPLICATION_CREDENTIALS = fileCred;
    } else {
      delete process.env.GOOGLE_APPLICATION_CREDENTIALS;
    }
  }

  const sa = loadServiceAccountJson();
  const projectId =
    process.env.GCLOUD_PROJECT?.trim() ||
    sa?.project_id ||
    'dapp-79473';
  firebaseProjectId = projectId;

  const options = { projectId };
  if (sa) {
    options.credential = cert(sa);
  }
  const storageBucket =
    process.env.FIREBASE_STORAGE_BUCKET?.trim() || `${projectId}.firebasestorage.app`;
  options.storageBucket = storageBucket;
  initializeApp(options);
  console.info(`[firebase] project=${projectId} storageBucket=${storageBucket} adc=${!!process.env.GOOGLE_APPLICATION_CREDENTIALS}`);
  if (!sa) {
    console.warn(
      '[firebase] No service account: set FIREBASE_SERVICE_ACCOUNT_JSON on Render or add service-account.json locally. Auth will fail until then.',
    );
  }
}

const db = getFirestore();
const auth = getAuth();

/** User fields returned to the Flutter app (matches UserProfile.fromDoc usage). */
const DISCOVERY_USER_FIELDS = [
  'displayName',
  'showFullName',
  'bio',
  'photos',
  'prompts',
  'relationshipGoal',
  'openingMove',
  'gender',
  'dateOfBirth',
  'age',
  'zodiacSign',
  'isPremium',
  'profileComplete',
  'onboardingDone',
  'kycVerified',
  'kycSkipped',
  'updatedAt',
  'locationVisible',
  'latitude',
  'longitude',
];

const INTERESTED_IN_ALLOWED = ['Male', 'Female', 'Transgender'];

/** Genders the Discover filter UI can request (comma `genders=` or legacy single `gender=`). */
const DISCOVERY_CLIENT_GENDERS = ['Male', 'Female', 'Transgender'];

const RELATIONSHIP_GOAL_FILTER_ALLOWED = [
  'Long-term relationship',
  'Short-term fun',
  'New friends',
  'Not sure yet',
  'Life partner',
];

function sanitizeInterestedIn(raw) {
  if (!Array.isArray(raw)) return [];
  return [
    ...new Set(
      raw
        .map((g) => String(g || '').trim())
        .filter((g) => INTERESTED_IN_ALLOWED.includes(g)),
    ),
  ];
}

/** @returns {string[]} unique Male/Female/Transgender from `genders=` or legacy `gender=`. Empty = not specified. */
function parseDiscoveryClientGenders(req) {
  const rawMulti = (req.query.genders || '').toString().trim();
  const rawSingle = (req.query.gender || '').toString().trim();
  let parts = [];
  if (rawMulti) {
    parts = rawMulti.split(',').map((s) => s.trim()).filter(Boolean);
  } else if (rawSingle) {
    parts = [rawSingle];
  }
  return [...new Set(parts.filter((g) => DISCOVERY_CLIENT_GENDERS.includes(g)))];
}

const PROFILE_GENDERS_ALLOWED = [
  'Male',
  'Female',
  'Transgender',
  'Non-binary',
  'Prefer not to say',
];

/** @returns {string[]|null} null = no filter; else subset of PROFILE_GENDERS_ALLOWED */
function parseNearbyGendersFilter(req) {
  const rawMulti = (req.query.genders || '').toString().trim();
  const rawSingle = (req.query.gender || '').toString().trim();
  let parts = [];
  if (rawMulti) {
    parts = rawMulti.split(',').map((s) => s.trim()).filter(Boolean);
  } else if (rawSingle) {
    parts = [rawSingle];
  }
  const g = [...new Set(parts.filter((x) => PROFILE_GENDERS_ALLOWED.includes(x)))];
  return g.length ? g : null;
}

/** Name shown in discovery: full name only when opted in; else first letter + "." */
function discoveryPublicDisplayName(data) {
  const raw = String(data.displayName || '').trim();
  if (!raw) return 'Someone';
  if (data.showFullName === true) return raw;
  try {
    const m = raw.match(/\p{L}/u);
    const ch = m ? m[0] : raw.charAt(0);
    if (!ch) return '?';
    return ch.toUpperCase() + '.';
  } catch {
    const ch = raw.charAt(0);
    if (!ch) return '?';
    return ch.toUpperCase() + '.';
  }
}

function firestoreDateToIso(v) {
  if (!v) return null;
  if (typeof v === 'string') return v;
  if (v && typeof v.toDate === 'function') {
    try {
      return v.toDate().toISOString();
    } catch {
      return null;
    }
  }
  return null;
}

/** Host snippet on meetup list/detail (same display name rules as discovery). */
function meetupOwnerPublicProfile(ownerId, userData) {
  if (!ownerId || !userData) return null;
  const photos = Array.isArray(userData.photos)
    ? userData.photos.filter((p) => typeof p === 'string' && p.length > 0)
    : [];
  const rawPrompts = Array.isArray(userData.prompts) ? userData.prompts : [];
  const prompts = rawPrompts
    .filter((p) => p && typeof p === 'object')
    .map((p) => ({
      question: String(p.question || '').trim(),
      answer: String(p.answer || '').trim(),
    }))
    .filter((p) => p.question && p.answer);
  return {
    id: ownerId,
    displayName: discoveryPublicDisplayName(userData),
    bio: userData.bio != null ? String(userData.bio) : null,
    photos,
    prompts,
    relationshipGoal: userData.relationshipGoal != null ? String(userData.relationshipGoal) : null,
    openingMove: userData.openingMove != null ? String(userData.openingMove) : null,
    gender: userData.gender != null ? String(userData.gender) : null,
    age: userData.age != null && !Number.isNaN(Number(userData.age)) ? Number(userData.age) : null,
    zodiacSign: userData.zodiacSign != null ? String(userData.zodiacSign) : null,
    dateOfBirth: firestoreDateToIso(userData.dateOfBirth),
  };
}

const GET_ALL_CHUNK = 30;

async function fetchUserDocsByIds(ids) {
  const unique = [...new Set(ids)].filter(Boolean);
  const map = new Map();
  for (let i = 0; i < unique.length; i += GET_ALL_CHUNK) {
    const chunk = unique.slice(i, i + GET_ALL_CHUNK);
    const refs = chunk.map((id) => db.collection('users').doc(id));
    const snaps = await db.getAll(...refs);
    for (const s of snaps) {
      if (s.exists) map.set(s.id, s.data());
    }
  }
  return map;
}

// Middleware: verify Firebase ID token from client
async function requireAuth(req, res, next) {
  const token = req.headers.authorization?.replace('Bearer ', '');
  if (!token) {
    return res.status(401).json({ error: 'Unauthorized' });
  }
  try {
    const decoded = await auth.verifyIdToken(token);
    req.uid = decoded.uid;
    next();
  } catch (e) {
    const msg = e?.message || String(e);
    console.error('[requireAuth] verifyIdToken failed:', msg);
    // App tokens are for one Firebase project; Admin must use that project's service account.
    if (/aud|audience|project/i.test(msg)) {
      return res.status(401).json({
        error:
          'API server is using the wrong Firebase project. On Render/hosting, set the same service account JSON as in Firebase Console → Project settings → Service accounts (must match the app’s google-services.json project).',
      });
    }
    return res.status(401).json({
      error:
        'Invalid or expired sign-in. Try again, or sign out and sign back in.',
    });
  }
}

// --- Users (profile) ---
app.get('/api/users/me', requireAuth, async (req, res) => {
  try {
    const doc = await db.collection('users').doc(req.uid).get();
    if (!doc.exists) return res.status(404).json({ error: 'Profile not found' });
    res.json({ id: doc.id, ...doc.data() });
  } catch (e) {
    res.status(500).json({ error: e.message });
  }
});

app.put('/api/users/me', requireAuth, async (req, res) => {
  try {
    const {
      displayName,
      bio,
      photos,
      prompts,
      relationshipGoal,
      openingMove,
      gender,
      interestedIn,
      showFullName,
      dateOfBirth,
      age,
      zodiacSign,
      isPremium,
      profileComplete,
      locationVisible,
      latitude,
      longitude,
    } = req.body;
    const ref = db.collection('users').doc(req.uid);
    const data = {
      updatedAt: new Date().toISOString(),
      ...(displayName != null && { displayName }),
      ...(bio != null && { bio }),
      ...(photos != null && { photos }),
      ...(prompts != null && { prompts }),
      ...(relationshipGoal != null && { relationshipGoal }),
      ...(openingMove != null && { openingMove }),
      ...(gender != null && { gender }),
      ...(interestedIn != null && { interestedIn: sanitizeInterestedIn(interestedIn) }),
      ...(typeof showFullName === 'boolean' && { showFullName }),
      ...(dateOfBirth != null && { dateOfBirth }),
      ...(age != null && { age: Number(age) }),
      ...(zodiacSign != null && { zodiacSign: String(zodiacSign) }),
      ...(isPremium != null && { isPremium }),
      ...(profileComplete != null && { profileComplete: !!profileComplete }),
      ...(typeof locationVisible === 'boolean' && { locationVisible }),
      ...(latitude != null && { latitude: Number(latitude) }),
      ...(longitude != null && { longitude: Number(longitude) }),
      ...((latitude != null || longitude != null) && { locationUpdatedAt: new Date().toISOString() }),
    };
    await ref.set(data, { merge: true });
    const doc = await ref.get();
    res.json({ id: doc.id, ...doc.data() });
  } catch (e) {
    res.status(500).json({ error: e.message });
  }
});

/**
 * Lazy-loaded Human for KYC gender detection (free, no API keys).
 * JPEG decode is pure JS (jpeg-js). On Node, @vladmandic/human resolves to human.node.js, which
 * requires @tensorflow/tfjs-node — it must be listed in package.json (not optional).
 */
let _human = null;

async function getHuman() {
  if (_human) return _human;
  const mod = await import('@vladmandic/human');
  const Human =
    mod.Human ??
    mod.default?.Human ??
    (typeof mod.default === 'function' ? mod.default : null);
  if (typeof Human !== 'function') {
    throw new Error(
      'Human class not found on @vladmandic/human export (check package version / Node ESM interop)',
    );
  }
  _human = new Human({
    backend: 'cpu',
    modelBasePath: 'https://cdn.jsdelivr.net/npm/@vladmandic/human/models/',
    face: { enabled: true },
    debug: false,
  });
  await _human.load();
  return _human;
}

/** Decode JPEG buffer to tensor [1, height, width, 3] for Human (pure JS, no canvas). */
async function bufferToTensor(buffer) {
  const jpeg = await import('jpeg-js');
  const { width, height, data } = jpeg.decode(buffer, { useTArray: true });
  if (!data || width < 10 || height < 10) throw new Error('Invalid image');
  const human = await getHuman();
  return human.tf.tidy(() => {
    const tensor = human.tf.tensor3d(data, [height, width, 3]).expandDims(0);
    return human.tf.cast(tensor, 'float32');
  });
}

/** KYC from image bytes using @vladmandic/human (free, local gender detection). No AWS. */
async function runKycFromBuffer(uid, buffer, res) {
  if (buffer.length > 5 * 1024 * 1024) {
    return res.status(400).json({ error: 'Image too large.' });
  }
  if (buffer.length < 200) {
    return res.status(400).json({ error: 'Image too small. Retake with better lighting.' });
  }

  const userSnap = await db.collection('users').doc(uid).get();
  const data = userSnap.data() || {};
  const stated = String(data.gender || '').trim();
  if (!stated) {
    return res.status(400).json({ error: 'Select your gender in onboarding first.' });
  }

  let verified = false;

  if (process.env.KYC_DEV_APPROVE === '1') {
    verified = true;
  } else {
    await kycSemaphore.acquire();
    try {
      try {
        const human = await getHuman();
        const tensor = await bufferToTensor(buffer);
        const result = await human.detect(tensor);
        tensor.dispose?.();
        const face = result?.face?.[0];
        if (!face) {
          return res.status(400).json({
            error: 'No face detected. Face the camera directly with good lighting.',
          });
        }
        // Human: gender is 'male'|'female', genderScore 0..1
        const detGender = String(face.gender || '').toLowerCase();
        const conf = Math.round((face.genderScore ?? 0) * 100);
        const isNonBinary = /non-binary|nonbinary/i.test(stated);
        const preferSkip = /prefer not/i.test(stated);

        if (isNonBinary || preferSkip) {
          verified = conf >= 75 && !!detGender;
        } else if (/^male$/i.test(stated)) {
          verified = detGender === 'male' && conf >= 82;
        } else if (/^female$/i.test(stated)) {
          verified = detGender === 'female' && conf >= 82;
        } else {
          verified = !!detGender && conf >= 78;
        }

        if (!verified) {
          return res.status(400).json({
            error:
              'We could not confirm your photo matches the gender you selected during onboarding. Please retake a clear selfie.',
          });
        }
      } catch (impErr) {
        if (
          impErr?.code === 'MODULE_NOT_FOUND' ||
          String(impErr?.message || '').includes('Cannot find module')
        ) {
          console.error('[kyc] module load:', impErr?.message || impErr);
          return res.status(503).json({
            error:
              'Photo verification is temporarily unavailable. Please try again in a few minutes.',
          });
        }
        const emsg = String(impErr?.message || '');
        if (/invalid image|decode|jpeg|png|image format/i.test(emsg)) {
          return res.status(400).json({
            error:
              'This photo could not be processed. Retake a clear, well-lit selfie (face the camera).',
          });
        }
        console.error('[kyc] human detect error:', impErr?.message || impErr);
        return res.status(500).json({
          error: 'Verification failed. Please retake a clear selfie and try again.',
        });
      }
    } finally {
      kycSemaphore.release();
    }
  }

  await db.collection('users').doc(uid).set(
    {
      kycVerified: true,
      kycVerifiedAt: new Date().toISOString(),
      updatedAt: new Date().toISOString(),
    },
    { merge: true },
  );
  res.json({ verified: true });
}

// KYC: 1) raw JPEG body (octet-stream / image/jpeg) — most reliable on Render. 2) multipart selfie. 3) JSON base64. 4) Storage legacy.
app.post('/api/kyc/verify', requireAuth, kycLimiter, async (req, res) => {
  try {
    const uid = req.uid;
    const ct = (req.headers['content-type'] || '').toLowerCase();
    const maxBytes = 4 * 1024 * 1024;

    if (
      ct.includes('application/octet-stream') ||
      ct.startsWith('image/jpeg') ||
      ct.startsWith('image/jpg')
    ) {
      const chunks = [];
      let n = 0;
      try {
        for await (const chunk of req) {
          n += chunk.length;
          if (n > maxBytes) {
            return res.status(400).json({ error: 'Photo too large.' });
          }
          chunks.push(chunk);
        }
      } catch (readErr) {
        console.error('[kyc] raw body read:', readErr);
        return res.status(400).json({ error: 'Could not read photo data. Try again.' });
      }
      const buf = Buffer.concat(chunks);
      if (buf.length >= 200) {
        console.info('[kyc] raw JPEG bytes=', buf.length);
        return await runKycFromBuffer(uid, buf, res);
      }
      return res.status(400).json({
        error: 'Photo data missing or too small. Update the app and retake your selfie.',
      });
    }

    if (ct.includes('multipart/form-data')) {
      await new Promise((resolve, reject) => {
        kycSelfieUpload.single('selfie')(req, res, (err) => (err ? reject(err) : resolve()));
      });
      if (req.file?.buffer?.length >= 200) {
        console.info('[kyc] multipart bytes=', req.file.buffer.length);
        return await runKycFromBuffer(uid, req.file.buffer, res);
      }
      return res.status(400).json({ error: 'No photo in upload. Field name must be "selfie".' });
    }

    const b64 = req.body?.imageBase64;
    if (typeof b64 === 'string' && b64.length > 200) {
      let buffer;
      try {
        const raw = b64
          .trim()
          .replace(/^data:image\/\w+;base64,/, '')
          .replace(/\s/g, '');
        buffer = Buffer.from(raw, 'base64');
      } catch {
        return res.status(400).json({ error: 'Invalid base64 image.' });
      }
      if (buffer.length >= 200) {
        console.info('[kyc] base64 bytes=', buffer.length);
        return await runKycFromBuffer(uid, buffer, res);
      }
      if (buffer.length > 0) {
        return res.status(400).json({ error: 'Image too small. Retake with better lighting.' });
      }
      return res.status(400).json({ error: 'Empty image.' });
    }

    let buffer;
    try {
      buffer = await downloadKycSelfie(uid);
    } catch (storErr) {
      console.error('[kyc] storage:', storErr);
      return res.status(503).json({
        error:
          'No photo in this request. Update the app — it must send the selfie as the request body (JPEG).',
      });
    }
    if (!buffer) {
      return res.status(400).json({ error: 'Selfie not found in Storage.' });
    }
    return await runKycFromBuffer(uid, buffer, res);
  } catch (e) {
    if (e?.code === 'LIMIT_FILE_SIZE') {
      return res.status(400).json({ error: 'Photo file is too large.' });
    }
    console.error('[kyc] verify error:', e);
    res.status(500).json({ error: e.message || String(e) });
  }
});

/** Sort key for match docs: Firestore orderBy(updatedAt) omits docs missing that field — sort in app instead. */
function matchRecencyMs(data) {
  if (!data) return 0;
  const toMs = (v) => {
    if (v == null) return 0;
    if (typeof v === 'string') {
      const ms = Date.parse(v);
      return Number.isNaN(ms) ? 0 : ms;
    }
    if (typeof v.toMillis === 'function') return v.toMillis();
    return 0;
  };
  return Math.max(toMs(data.updatedAt), toMs(data.createdAt));
}

// Haversine distance in km
function haversineKm(lat1, lon1, lat2, lon2) {
  const R = 6371;
  const dLat = (lat2 - lat1) * Math.PI / 180;
  const dLon = (lon2 - lon1) * Math.PI / 180;
  const a =
    Math.sin(dLat / 2) * Math.sin(dLat / 2) +
    Math.cos(lat1 * Math.PI / 180) * Math.cos(lat2 * Math.PI / 180) *
    Math.sin(dLon / 2) * Math.sin(dLon / 2);
  const c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
  return R * c;
}

/** User IDs to hide from discovery / nearby: self, passed, already liked, matched, blocked either way. */
async function loadExclusionUserIds(uid) {
  const cacheKey = `excl:${uid}`;
  const cached = discoveryPrepCache.get(cacheKey);
  if (cached) return new Set(cached);

  const excluded = new Set([uid]);
  const [
    passSnap,
    outLikeSnap,
    matchSnap,
    blockOutSnap,
    blockInSnap,
  ] = await Promise.all([
    db.collection('passes').where('fromId', '==', uid).select('toId').limit(500).get(),
    db.collection('likes').where('fromId', '==', uid).select('toId').limit(500).get(),
    db.collection('matches').where('participants', 'array-contains', uid).select('participants').limit(200).get(),
    db.collection('blocks').where('fromId', '==', uid).select('toId').limit(200).get(),
    db.collection('blocks').where('toId', '==', uid).select('fromId').limit(200).get(),
  ]);
  for (const d of passSnap.docs) {
    const t = d.data().toId;
    if (t) excluded.add(t);
  }
  for (const d of outLikeSnap.docs) {
    const t = d.data().toId;
    if (t) excluded.add(t);
  }
  for (const d of matchSnap.docs) {
    for (const p of d.data().participants || []) {
      if (p && p !== uid) excluded.add(p);
    }
  }
  for (const d of blockOutSnap.docs) {
    const t = d.data().toId;
    if (t) excluded.add(t);
  }
  for (const d of blockInSnap.docs) {
    const f = d.data().fromId;
    if (f) excluded.add(f);
  }
  discoveryPrepCache.set(cacheKey, [...excluded]);
  return excluded;
}

/** Map fromId -> superLike (people who liked the current user first). */
async function loadIncomingLikesMap(uid) {
  const cacheKey = `inlike:${uid}`;
  const cached = discoveryPrepCache.get(cacheKey);
  if (cached) return new Map(cached);

  const snap = await db
    .collection('likes')
    .where('toId', '==', uid)
    .select('fromId', 'superLike')
    .limit(400)
    .get();
  const map = new Map();
  for (const d of snap.docs) {
    const data = d.data();
    const from = data.fromId;
    if (from) map.set(from, !!data.superLike);
  }
  discoveryPrepCache.set(cacheKey, [...map.entries()]);
  return map;
}

function deterministicJitter(uid, candidateId, dayKey) {
  const mix = `${uid}|${candidateId}|${dayKey}`;
  let h = 0;
  for (let i = 0; i < mix.length; i++) {
    h = ((h << 5) - h + mix.charCodeAt(i)) | 0;
  }
  return Math.abs(h) % 1000 / 10000;
}

async function isBlockedPair(uid, targetId) {
  const [a, b] = await Promise.all([
    db.collection('blocks').doc(`${uid}_${targetId}`).get(),
    db.collection('blocks').doc(`${targetId}_${uid}`).get(),
  ]);
  return a.exists || b.exists;
}

// --- Nearby (map) — users who have location visible, sorted by distance ---
// Query: genders=Male,Female (or legacy gender=), radiusKm max 80, ageMin/ageMax, relationshipGoal, verifiedOnly.
app.get('/api/nearby', requireAuth, async (req, res) => {
  try {
    const lat = parseFloat(req.query.lat);
    const lng = parseFloat(req.query.lng);
    const radiusRaw = parseFloat(req.query.radiusKm || '20');
    const radiusKm = Math.min(Math.max(Number.isNaN(radiusRaw) ? 20 : radiusRaw, 1), 80);
    const limit = Math.min(parseInt(req.query.limit || '50', 10), 100);
    const gendersFilter = parseNearbyGendersFilter(req);
    const ageMinQ = parseInt(req.query.ageMin, 10);
    const ageMaxQ = parseInt(req.query.ageMax, 10);
    const hasAgeMin = !Number.isNaN(ageMinQ);
    const hasAgeMax = !Number.isNaN(ageMaxQ);
    const goalRaw = (req.query.relationshipGoal || '').toString().trim();
    const relationshipGoalFilter = RELATIONSHIP_GOAL_FILTER_ALLOWED.includes(goalRaw) ? goalRaw : null;
    const verifiedOnly = req.query.verifiedOnly === '1' || req.query.verifiedOnly === 'true';
    if (Number.isNaN(lat) || Number.isNaN(lng)) {
      return res.status(400).json({ error: 'lat and lng query params required' });
    }
    const snapshot = await db
      .collection('users')
      .where('locationVisible', '==', true)
      .limit(500)
      .get();
    const meId = req.uid;
    let excluded;
    try {
      excluded = await loadExclusionUserIds(meId);
    } catch (e) {
      excluded = new Set([meId]);
    }
    const withDistance = [];
    for (const d of snapshot.docs) {
      if (d.id === meId || excluded.has(d.id)) continue;
      const data = d.data();
      const userLat = data.latitude;
      const userLng = data.longitude;
      if (userLat == null || userLng == null) continue;
      const km = haversineKm(lat, lng, userLat, userLng);
      if (km > radiusKm) continue;
      const g = String(data.gender || '');
      if (gendersFilter && !gendersFilter.includes(g)) continue;
      if (hasAgeMin || hasAgeMax) {
        const a = data.age;
        if (a == null || typeof a !== 'number') continue;
        if (hasAgeMin && a < ageMinQ) continue;
        if (hasAgeMax && a > ageMaxQ) continue;
      }
      if (relationshipGoalFilter && String(data.relationshipGoal || '').trim() !== relationshipGoalFilter) {
        continue;
      }
      if (verifiedOnly && data.kycVerified !== true) continue;
      withDistance.push({ id: d.id, ...data, distanceKm: km });
    }
    withDistance.sort((a, b) => a.distanceKm - b.distanceKm);
    const list = withDistance.slice(0, limit).map(({ distanceKm, ...rest }) => ({ ...rest, distanceKm }));
    res.json({ nearby: list });
  } catch (e) {
    res.status(500).json({ error: e.message });
  }
});

// --- Discovery (suggestions) ---
// Query: genders=Male,Female (or legacy gender=), ageMin/ageMax, relationshipGoal, verifiedOnly.
// Ranks by: incoming like/super-like, relationship goal match, distance, KYC, daily shuffle jitter.
// Excludes: self, passed, outgoing likes, matches, blocks.
// Discovery is allowed for all authenticated users; likes require identity verification.
app.get('/api/discovery', requireAuth, discoveryLimiter, async (req, res) => {
  try {
    const uid = req.uid;
    const limit = Math.min(parseInt(req.query.limit || '20', 10), 50);
    const clientGenders = parseDiscoveryClientGenders(req);
    const ageMinQ = parseInt(req.query.ageMin, 10);
    const ageMaxQ = parseInt(req.query.ageMax, 10);
    const hasAgeMin = !Number.isNaN(ageMinQ);
    const hasAgeMax = !Number.isNaN(ageMaxQ);
    const goalRaw = (req.query.relationshipGoal || '').toString().trim();
    const relationshipGoalFilter = RELATIONSHIP_GOAL_FILTER_ALLOWED.includes(goalRaw) ? goalRaw : null;
    const verifiedOnly = req.query.verifiedOnly === '1' || req.query.verifiedOnly === 'true';

    const [meSnap, excluded, incomingLikes] = await Promise.all([
      db.collection('users').doc(uid).get(),
      loadExclusionUserIds(uid),
      loadIncomingLikesMap(uid),
    ]);
    const me = meSnap.data() || {};
    const myGoal = String(me.relationshipGoal || '').trim().toLowerCase();
    const myLat = me.latitude;
    const myLng = me.longitude;

    const interestedRaw = Array.isArray(me.interestedIn) ? me.interestedIn : [];
    const interested = sanitizeInterestedIn(interestedRaw);

    const fullGenderSet = clientGenders.length === DISCOVERY_CLIENT_GENDERS.length;
    const useClientGenders = clientGenders.length > 0 && !fullGenderSet;

    let effectiveQueryGenders = null;
    if (useClientGenders) {
      if (interested.length > 0) {
        effectiveQueryGenders = clientGenders.filter((g) => interested.includes(g));
      } else {
        effectiveQueryGenders = clientGenders;
      }
      if (effectiveQueryGenders.length === 0) {
        return res.json({ suggestions: [] });
      }
    }

    let query = db.collection('users').where('profileComplete', '==', true);
    if (effectiveQueryGenders != null) {
      if (effectiveQueryGenders.length === 1) {
        query = query.where('gender', '==', effectiveQueryGenders[0]);
      } else {
        query = query.where('gender', 'in', effectiveQueryGenders.slice(0, 10));
      }
    } else if (interested.length === 1) {
      query = query.where('gender', '==', interested[0]);
    } else if (interested.length > 1) {
      query = query.where('gender', 'in', interested.slice(0, 10));
    }
    query = query.select(...DISCOVERY_USER_FIELDS);
    const fetchCap = Math.min(Math.max(limit * 12, 100), 400);
    const snapshot = await query.limit(fetchCap).get();

    const dayKey = new Date().toISOString().slice(0, 10);
    const scored = [];
    for (const d of snapshot.docs) {
      const id = d.id;
      if (excluded.has(id)) continue;
      const data = d.data();
      const theirGender = String(data.gender || '');
      if (interested.length > 0 && !interested.includes(theirGender)) {
        continue;
      }
      if (useClientGenders && !clientGenders.includes(theirGender)) {
        continue;
      }
      if (hasAgeMin || hasAgeMax) {
        const a = data.age;
        if (a == null || typeof a !== 'number') continue;
        if (hasAgeMin && a < ageMinQ) continue;
        if (hasAgeMax && a > ageMaxQ) continue;
      }
      if (relationshipGoalFilter && String(data.relationshipGoal || '').trim() !== relationshipGoalFilter) {
        continue;
      }
      if (verifiedOnly && data.kycVerified !== true) {
        continue;
      }
      let score = 0;
      if (incomingLikes.has(id)) {
        score += 100;
        if (incomingLikes.get(id)) score += 28;
      }
      const theirGoal = String(data.relationshipGoal || '').trim().toLowerCase();
      if (myGoal && theirGoal && myGoal === theirGoal) score += 22;
      if (data.kycVerified === true) score += 10;
      const ulat = data.latitude;
      const ulng = data.longitude;
      if (
        myLat != null &&
        myLng != null &&
        ulat != null &&
        ulng != null &&
        !Number.isNaN(Number(myLat)) &&
        !Number.isNaN(Number(myLng))
      ) {
        const km = haversineKm(Number(myLat), Number(myLng), Number(ulat), Number(ulng));
        score += Math.max(0, 35 - km / 2.5);
      }
      score += deterministicJitter(uid, id, dayKey);
      scored.push({ id, data, score });
    }

    scored.sort((a, b) => b.score - a.score);
    const list = scored.slice(0, limit).map(({ id, data }) => {
      const displayName = discoveryPublicDisplayName(data);
      const { showFullName: _sf, ...rest } = data;
      return { id, ...rest, displayName };
    });
    res.json({ suggestions: list });
  } catch (e) {
    res.status(500).json({ error: e.message });
  }
});

// --- Likes / passes ---
// On mutual like (target has already liked us), create a match so both can chat.
app.post('/api/likes', requireAuth, async (req, res) => {
  try {
    const uid = req.uid;
    const me = await db.collection('users').doc(uid).get();
    if (!me.exists || !me.data().kycVerified) {
      return res.status(403).json({ error: 'Complete identity verification to like profiles.' });
    }
    const { targetId, superLike, compliment } = req.body;
    if (!targetId) return res.status(400).json({ error: 'targetId required' });
    let complimentOut =
      typeof compliment === 'string' ? compliment.trim().slice(0, 280) : '';
    if (complimentOut.length === 0) complimentOut = '';
    if (targetId === uid) {
      return res.status(400).json({ error: 'Invalid target' });
    }
    if (await isBlockedPair(uid, targetId)) {
      return res.status(403).json({ error: 'You cannot interact with this profile.' });
    }
    const likeDoc = {
      fromId: uid,
      toId: targetId,
      superLike: !!superLike,
      createdAt: new Date().toISOString(),
    };
    if (complimentOut) likeDoc.compliment = complimentOut;
    await db.collection('likes').doc(`${uid}_${targetId}`).set(likeDoc);
    bustDiscoveryPrepCacheForUsers(uid, targetId);

    // Check for mutual like: target has already liked uid
    const reverseLike = await db.collection('likes').doc(`${targetId}_${uid}`).get();
    let isNewMatch = false;
    let matchId = null;
    if (reverseLike.exists) {
      const matchParticipants = [uid, targetId].sort();
      matchId = matchParticipants.join('_');
      const matchRef = db.collection('matches').doc(matchId);
      const matchDoc = await matchRef.get();
      const now = new Date().toISOString();
      if (!matchDoc.exists) {
        await matchRef.set({
          participants: matchParticipants,
          createdAt: now,
          updatedAt: now,
          lastMessage: null,
        });
        isNewMatch = true;
      }
    }
    res.json({ ok: true, isNewMatch, matchId });
  } catch (e) {
    res.status(500).json({ error: e.message });
  }
});

app.post('/api/passes', requireAuth, async (req, res) => {
  try {
    const uid = req.uid;
    const { targetId } = req.body;
    if (!targetId) return res.status(400).json({ error: 'targetId required' });
    if (targetId === uid) {
      return res.status(400).json({ error: 'Invalid target' });
    }
    if (await isBlockedPair(uid, targetId)) {
      return res.status(403).json({ error: 'You cannot interact with this profile.' });
    }
    await db.collection('passes').doc(`${uid}_${targetId}`).set({
      fromId: uid,
      toId: targetId,
      createdAt: new Date().toISOString(),
    });
    bustDiscoveryPrepCacheForUsers(uid, targetId);
    res.json({ ok: true });
  } catch (e) {
    res.status(500).json({ error: e.message });
  }
});

/** Undo last pass: remove your pass doc so they can appear in discovery again. */
app.delete('/api/passes/:targetId', requireAuth, async (req, res) => {
  try {
    const uid = req.uid;
    const targetId = (req.params.targetId || '').trim();
    if (!targetId) return res.status(400).json({ error: 'targetId required' });
    if (targetId === uid) {
      return res.status(400).json({ error: 'Invalid target' });
    }
    const ref = db.collection('passes').doc(`${uid}_${targetId}`);
    const doc = await ref.get();
    if (!doc.exists) {
      return res.status(404).json({ error: 'Pass not found' });
    }
    await ref.delete();
    bustDiscoveryPrepCacheForUsers(uid, targetId);
    res.json({ ok: true });
  } catch (e) {
    res.status(500).json({ error: e.message });
  }
});

/** People who liked the current user (not yet matched, not blocked). */
app.get('/api/likes/incoming', requireAuth, async (req, res) => {
  try {
    const uid = req.uid;
    const [likesSnap, matchSnap, blockOutSnap, blockInSnap] = await Promise.all([
      db.collection('likes').where('toId', '==', uid).limit(200).get(),
      db.collection('matches').where('participants', 'array-contains', uid).limit(200).get(),
      db.collection('blocks').where('fromId', '==', uid).limit(200).get(),
      db.collection('blocks').where('toId', '==', uid).limit(200).get(),
    ]);
    const matchedIds = new Set();
    for (const d of matchSnap.docs) {
      for (const p of d.data().participants || []) {
        if (p && p !== uid) matchedIds.add(p);
      }
    }
    const blocked = new Set();
    for (const d of blockOutSnap.docs) {
      const t = d.data().toId;
      if (t) blocked.add(t);
    }
    for (const d of blockInSnap.docs) {
      const f = d.data().fromId;
      if (f) blocked.add(f);
    }
    const seen = new Set();
    const list = [];
    for (const d of likesSnap.docs) {
      const data = d.data();
      const fromId = data.fromId;
      if (!fromId || fromId === uid) continue;
      if (matchedIds.has(fromId) || blocked.has(fromId)) continue;
      if (seen.has(fromId)) continue;
      seen.add(fromId);
      const userDoc = await db.collection('users').doc(fromId).get();
      if (!userDoc.exists) continue;
      const u = userDoc.data();
      const c =
        typeof data.compliment === 'string' && data.compliment.trim()
          ? data.compliment.trim().slice(0, 280)
          : null;
      list.push({
        fromId,
        superLike: !!data.superLike,
        compliment: c,
        createdAt: data.createdAt || null,
        displayName: u.displayName || 'Someone',
        photos: Array.isArray(u.photos) ? u.photos : [],
      });
    }
    res.json({ incoming: list });
  } catch (e) {
    res.status(500).json({ error: e.message });
  }
});

// --- Matches ---
// Return matches with otherUser (id, displayName, photos) for the participant that isn't current user.
app.get('/api/matches', requireAuth, async (req, res) => {
  try {
    const uid = req.uid;
    const snapshot = await db
      .collection('matches')
      .where('participants', 'array-contains', uid)
      .limit(100)
      .get();
    const otherIds = snapshot.docs
      .map((d) => {
        const participants = d.data().participants || [];
        return participants.find((p) => p !== uid);
      })
      .filter(Boolean);
    const userMap = await fetchUserDocsByIds(otherIds);
    const list = snapshot.docs.map((d) => {
      const data = d.data();
      const participants = data.participants || [];
      const otherId = participants.find((p) => p !== uid);
      let otherUser = { id: otherId };
      if (otherId) {
        const u = userMap.get(otherId);
        if (u) {
          otherUser = {
            id: otherId,
            displayName: u.displayName || 'Someone',
            photos: u.photos || [],
          };
        }
      }
      return { id: d.id, ...data, otherUser };
    });
    list.sort((a, b) => matchRecencyMs(b) - matchRecencyMs(a));
    res.json({ matches: list });
  } catch (e) {
    res.status(500).json({ error: e.message });
  }
});

// Unmatch: delete match + messages for both; block pair (same effect as block for likes/discovery).
app.post('/api/matches/:matchId/unmatch', requireAuth, async (req, res) => {
  try {
    const result = await getMatchAndRequireParticipant(req, res);
    if (!result) return;
    const { matchId, matchDoc } = result;
    const participants = matchDoc.data().participants || [];
    const otherId = participants.find((p) => p !== req.uid);
    if (!otherId) {
      return res.status(400).json({ error: 'Invalid match' });
    }
    await db.collection('blocks').doc(`${req.uid}_${otherId}`).set({
      fromId: req.uid,
      toId: otherId,
      createdAt: new Date().toISOString(),
    });
    bustDiscoveryPrepCacheForUsers(req.uid, otherId);
    await deleteMatchAndMessages(matchId);
    res.json({ ok: true });
  } catch (e) {
    res.status(500).json({ error: e.message });
  }
});

// --- Chats --- (only match participants can read/send)
async function getMatchAndRequireParticipant(req, res) {
  const { matchId } = req.params;
  const matchDoc = await db.collection('matches').doc(matchId).get();
  if (!matchDoc.exists) {
    res.status(404).json({ error: 'Match not found' });
    return null;
  }
  const participants = matchDoc.data().participants || [];
  if (!participants.includes(req.uid)) {
    res.status(403).json({ error: 'You are not in this match' });
    return null;
  }
  return { matchId, matchDoc };
}

/** Remove all message docs under a match, then the match doc (chat gone for both users). */
async function deleteMatchAndMessages(matchId) {
  const matchRef = db.collection('matches').doc(matchId);
  const messagesCol = matchRef.collection('messages');
  const pageSize = 400;
  for (;;) {
    const snap = await messagesCol.limit(pageSize).get();
    if (snap.empty) break;
    const batch = db.batch();
    for (const d of snap.docs) {
      batch.delete(d.ref);
    }
    await batch.commit();
  }
  await matchRef.delete();
}

/** Max raw bytes for in-chat ephemeral payloads (Firestore only — no object storage). */
const EPHEMERAL_IMAGE_MAX_BYTES = 380000;
const EPHEMERAL_VOICE_MAX_BYTES = 260000;

/** Read `ephemeral` even if the client/proxy used different key casing. */
function readEphemeralNested(body) {
  if (!body || typeof body !== 'object' || Array.isArray(body)) return undefined;
  if (Object.prototype.hasOwnProperty.call(body, 'ephemeral')) return body.ephemeral;
  const key = Object.keys(body).find((k) => k.toLowerCase() === 'ephemeral');
  return key ? body[key] : undefined;
}

/** Normalize client body for disappearing media (handles nested object, JSON string, or flat keys). */
function normalizeEphemeralPayload(body) {
  if (!body || typeof body !== 'object' || Array.isArray(body)) return null;
  let e = readEphemeralNested(body);
  if (typeof e === 'string') {
    try {
      e = JSON.parse(e);
    } catch {
      return null;
    }
  }
  if (e && typeof e === 'object' && !Array.isArray(e)) {
    return e;
  }
  const rawK = body.ephemeralKind ?? body.kind;
  const k =
    typeof rawK === 'string'
      ? rawK.trim().toLowerCase()
      : typeof rawK === 'number'
        ? String(rawK)
        : '';
  if (k === 'voice' || k === 'image') {
    const data = body.data ?? body.ephemeralData ?? body.payload;
    const mimeType = body.mimeType ?? body.ephemeralMimeType;
    if (typeof data === 'string' && typeof mimeType === 'string') {
      return { kind: k, mimeType, data };
    }
  }
  return null;
}

async function recomputeMatchLastMessage(matchId) {
  const snap = await db
    .collection('matches')
    .doc(matchId)
    .collection('messages')
    .orderBy('createdAt', 'desc')
    .limit(1)
    .get();
  let lastMessage = '';
  if (!snap.empty) {
    lastMessage = String(snap.docs[0].data().text || '').slice(0, 100);
  }
  const now = new Date().toISOString();
  await db.collection('matches').doc(matchId).update({
    lastMessage,
    updatedAt: now,
  });
}

app.get('/api/chats/:matchId/messages', requireAuth, async (req, res) => {
  try {
    const result = await getMatchAndRequireParticipant(req, res);
    if (!result) return;
    const { matchId } = result;
    const snapshot = await db
      .collection('matches')
      .doc(matchId)
      .collection('messages')
      .orderBy('createdAt', 'desc')
      .limit(50)
      .get();
    const list = snapshot.docs.map((d) => ({ id: d.id, ...d.data() })).reverse();
    res.json({ messages: list });
  } catch (e) {
    res.status(500).json({ error: e.message });
  }
});

app.post('/api/chats/:matchId/messages', requireAuth, async (req, res) => {
  try {
    const result = await getMatchAndRequireParticipant(req, res);
    if (!result) return;
    const { matchId } = result;
    const body = req.body && typeof req.body === 'object' ? req.body : {};
    const { text } = body;
    const ephemeral = normalizeEphemeralPayload(body);

    if (ephemeral) {
      const rawKind = ephemeral.kind;
      const kindLower =
        typeof rawKind === 'string'
          ? rawKind.trim().toLowerCase()
          : rawKind != null
            ? String(rawKind).trim().toLowerCase()
            : '';
      const kind = kindLower === 'voice' ? 'voice' : kindLower === 'image' ? 'image' : null;
      const mimeType = typeof ephemeral.mimeType === 'string' ? ephemeral.mimeType.trim() : '';
      const dataRaw = ephemeral.data;
      const data = typeof dataRaw === 'string' ? dataRaw.replace(/\s/g, '') : '';
      if (!kind || !mimeType || !data) {
        return res.status(400).json({ error: 'ephemeral requires kind, mimeType, data' });
      }
      let buf;
      try {
        buf = Buffer.from(data, 'base64');
      } catch {
        return res.status(400).json({ error: 'invalid base64' });
      }
      if (!buf || buf.length === 0) {
        return res.status(400).json({ error: 'empty media payload' });
      }
      const max = kind === 'voice' ? EPHEMERAL_VOICE_MAX_BYTES : EPHEMERAL_IMAGE_MAX_BYTES;
      if (buf.length > max) {
        return res.status(400).json({ error: `ephemeral ${kind} too large (max ${max} bytes)` });
      }
      if (kind === 'image') {
        if (!/^image\/(jpeg|jpg|jpe|png|webp|pjpeg|x-png)$/i.test(mimeType)) {
          return res.status(400).json({ error: 'unsupported image mime' });
        }
      } else if (
        !/^audio\/(mpeg|mp3|mp4|aac|webm|x-m4a|m4a|3gpp|amr|ogg|opus|x-caf|caf)$/i.test(mimeType)
      ) {
        return res.status(400).json({ error: 'unsupported audio mime' });
      }

      const ref = db.collection('matches').doc(matchId).collection('messages').doc();
      const now = new Date().toISOString();
      const placeholder = kind === 'image' ? '📷 Disappearing photo' : '🎤 Disappearing voice';
      await ref.set({
        senderId: req.uid,
        text: placeholder,
        createdAt: now,
        ephemeral: true,
        ephemeralKind: kind,
        mimeType,
        ephemeralPayload: data,
      });
      await db.collection('matches').doc(matchId).update({
        updatedAt: now,
        lastMessage: placeholder,
      });
      return res.json({
        id: ref.id,
        senderId: req.uid,
        text: placeholder,
        createdAt: now,
        ephemeral: true,
        ephemeralKind: kind,
        mimeType,
        ephemeralPayload: data,
      });
    }

    if (!text?.trim()) {
      const hinted =
        body &&
        typeof body === 'object' &&
        (readEphemeralNested(body) != null ||
          ['kind', 'data', 'mimeType', 'ephemeralKind', 'ephemeralData'].some((k) =>
            Object.prototype.hasOwnProperty.call(body, k),
          ));
      if (hinted) {
        return res.status(400).json({
          error:
            'Could not read disappearing media. Update the app and ensure the API server is on the latest version.',
        });
      }
      return res.status(400).json({ error: 'text required' });
    }
    const ref = db.collection('matches').doc(matchId).collection('messages').doc();
    const now = new Date().toISOString();
    await ref.set({
      senderId: req.uid,
      text: text.trim(),
      createdAt: now,
    });
    await db.collection('matches').doc(matchId).update({
      updatedAt: now,
      lastMessage: text.trim().slice(0, 100),
    });
    res.json({ id: ref.id, senderId: req.uid, text: text.trim(), createdAt: now });
  } catch (e) {
    res.status(500).json({ error: e.message });
  }
});

app.delete('/api/chats/:matchId/messages/:messageId', requireAuth, async (req, res) => {
  try {
    const result = await getMatchAndRequireParticipant(req, res);
    if (!result) return;
    const { matchId } = result;
    const { messageId } = req.params;
    const ref = db.collection('matches').doc(matchId).collection('messages').doc(messageId);
    const doc = await ref.get();
    if (!doc.exists) return res.status(404).json({ error: 'Message not found' });
    const d = doc.data();
    if (!d.ephemeral) {
      return res.status(403).json({ error: 'Only disappearing messages can be deleted this way' });
    }
    await ref.delete();
    await recomputeMatchLastMessage(matchId);
    res.json({ ok: true });
  } catch (e) {
    res.status(500).json({ error: e.message });
  }
});

// --- Rooms (experience-based: cafe, hiking, dinner, etc.) ---
// Room creation: women or premium male only
async function canCreateRoom(uid) {
  const userDoc = await db.collection('users').doc(uid).get();
  if (!userDoc.exists) return false;
  const d = userDoc.data();
  const gender = (d.gender || '').toLowerCase();
  const isPremium = !!d.isPremium;
  return gender === 'female' || isPremium;
}

/** 0–100 “fit” score for host when reviewing a join request (goal, KYC, distance). */
function meetupRequestInterestPercent(hostData, requesterData) {
  let score = 42;
  const hostGoal = String(hostData.relationshipGoal || '').trim().toLowerCase();
  const reqGoal = String(requesterData.relationshipGoal || '').trim().toLowerCase();
  if (hostGoal && reqGoal && hostGoal === reqGoal) score += 28;
  if (requesterData.kycVerified === true) score += 15;
  const hLat = hostData.latitude;
  const hLng = hostData.longitude;
  const rLat = requesterData.latitude;
  const rLng = requesterData.longitude;
  if (
    hLat != null &&
    hLng != null &&
    rLat != null &&
    rLng != null &&
    !Number.isNaN(Number(hLat)) &&
    !Number.isNaN(Number(hLng)) &&
    !Number.isNaN(Number(rLat)) &&
    !Number.isNaN(Number(rLng))
  ) {
    const km = haversineKm(Number(hLat), Number(hLng), Number(rLat), Number(rLng));
    score += Math.max(0, 20 - km / 6);
  }
  return Math.min(100, Math.round(score));
}

async function attachMyRequestStatuses(uid, rooms) {
  if (!uid || !rooms.length) return;
  const ids = rooms.map((r) => r.id).filter(Boolean);
  const statusMap = new Map();
  for (let i = 0; i < ids.length; i += 30) {
    const chunk = ids.slice(i, i + 30);
    const snap = await db
      .collection('room_requests')
      .where('requesterId', '==', uid)
      .where('roomId', 'in', chunk)
      .get();
    for (const doc of snap.docs) {
      const d = doc.data();
      statusMap.set(d.roomId, d.status || 'pending');
    }
  }
  for (const r of rooms) {
    if (statusMap.has(r.id)) r.myRequestStatus = statusMap.get(r.id);
  }
}

function filterRoomDocsByQuery(docs, activityType, roomType) {
  let out = docs;
  if (activityType) {
    out = out.filter((doc) => (doc.data().activityType || '') === activityType);
  }
  if (roomType === 'group' || roomType === 'personal') {
    out = out.filter((doc) => (doc.data().roomType || 'personal') === roomType);
  }
  return out;
}

function sortRoomDocsByDistance(docs, lat, lng) {
  if (lat == null || lng == null || Number.isNaN(lat) || Number.isNaN(lng)) return docs;
  const scored = docs.map((doc) => {
    const d = doc.data();
    const rLat = d.latitude;
    const rLng = d.longitude;
    if (rLat == null || rLng == null || Number.isNaN(Number(rLat)) || Number.isNaN(Number(rLng))) {
      return { doc, dist: 1e9 };
    }
    return { doc, dist: haversineKm(lat, lng, Number(rLat), Number(rLng)) };
  });
  scored.sort((a, b) => a.dist - b.dist);
  return scored.map((x) => x.doc);
}

/** Same as [sortRoomDocsByDistance] for enriched room JSON objects (e.g. saved list). */
function sortRoomsJsonByDistance(rooms, lat, lng) {
  if (lat == null || lng == null || Number.isNaN(lat) || Number.isNaN(lng)) return rooms;
  const scored = rooms.map((r) => {
    const rLat = r.latitude;
    const rLng = r.longitude;
    if (rLat == null || rLng == null || Number.isNaN(Number(rLat)) || Number.isNaN(Number(rLng))) {
      return { r, dist: 1e9 };
    }
    return { r, dist: haversineKm(lat, lng, Number(rLat), Number(rLng)) };
  });
  scored.sort((a, b) => a.dist - b.dist);
  return scored.map((x) => x.r);
}

async function fetchRoomSnapsByIdsInOrder(roomIds) {
  const map = new Map();
  for (let i = 0; i < roomIds.length; i += 30) {
    const chunk = roomIds.slice(i, i + 30);
    const refs = chunk.map((id) => db.collection('rooms').doc(id));
    const snaps = await db.getAll(...refs);
    for (const s of snaps) {
      if (s.exists) map.set(s.id, s);
    }
  }
  return roomIds.map((id) => map.get(id)).filter(Boolean);
}

// List rooms: discovery feed (default) or my events (mine=1, owner only)
app.get('/api/rooms', requireAuth, async (req, res) => {
  try {
    const uid = req.uid;
    const mine = req.query.mine === '1' || req.query.mine === 'true';
    const savedOnly = req.query.saved === '1' || req.query.saved === 'true';
    const limit = Math.min(parseInt(req.query.limit || '20', 10), 50);
    const activityTypeQ = (req.query.activityType || '').toString().trim() || null;
    const roomTypeQ = (req.query.roomType || '').toString().trim();
    const roomTypeFilter = roomTypeQ === 'group' || roomTypeQ === 'personal' ? roomTypeQ : null;
    const sortDistance = (req.query.sort || '').toString().toLowerCase() === 'distance';
    let viewerLat = parseFloat(req.query.lat);
    let viewerLng = parseFloat(req.query.lng);
    if (sortDistance && (Number.isNaN(viewerLat) || Number.isNaN(viewerLng))) {
      const meSnap = await db.collection('users').doc(uid).get();
      const md = meSnap.exists ? meSnap.data() : {};
      viewerLat = md.latitude != null ? Number(md.latitude) : NaN;
      viewerLng = md.longitude != null ? Number(md.longitude) : NaN;
    }

    if (savedOnly) {
      const saveSnap = await db
        .collection('users')
        .doc(uid)
        .collection('meetupSaves')
        .orderBy('savedAt', 'desc')
        .limit(limit)
        .get();
      const roomIds = saveSnap.docs.map((d) => d.id);
      const snaps = await fetchRoomSnapsByIdsInOrder(roomIds);
      const enrichRoomDocs = async (docs) => {
        const ownerIds = [...new Set(docs.map((doc) => doc.data().ownerId).filter(Boolean))];
        const owners = await fetchUserDocsByIds(ownerIds);
        return docs.map((doc) => {
          const d = doc.data();
          const u = d.ownerId ? owners.get(d.ownerId) : null;
          const ownerName = u ? (u.displayName || 'Host') : 'Host';
          return {
            id: doc.id,
            ...d,
            ownerName,
            ownerProfile: meetupOwnerPublicProfile(d.ownerId, u),
            currentParticipants: (d.participants || []).length,
            isSaved: true,
          };
        });
      };
      let rooms = await enrichRoomDocs(snaps);
      // Saved + mine lists are never narrowed by discovery filters (activity / room type).
      if (roomTypeFilter) {
        rooms = rooms.filter((r) => (r.roomType || 'personal') === roomTypeFilter);
      }
      if (sortDistance && !Number.isNaN(viewerLat) && !Number.isNaN(viewerLng)) {
        rooms = sortRoomsJsonByDistance(rooms, viewerLat, viewerLng);
      }
      await attachMyRequestStatuses(uid, rooms);
      return res.json({ rooms });
    }

    if (mine) {
      // Only event owner sees their created rooms (any status)
      const snapshot = await db
        .collection('rooms')
        .where('ownerId', '==', uid)
        .limit(limit)
        .get();
      const sorted = snapshot.docs.sort(
        (a, b) => (b.data().createdAt || '').localeCompare(a.data().createdAt || '')
      );
      const mineOwnerIds = [...new Set(sorted.map((doc) => doc.data().ownerId).filter(Boolean))];
      const mineOwners = await fetchUserDocsByIds(mineOwnerIds);
      const rooms = sorted.map((doc) => {
        const d = doc.data();
        const u = d.ownerId ? mineOwners.get(d.ownerId) : null;
        const ownerName = u ? (u.displayName || 'Host') : 'Host';
        return {
          id: doc.id,
          ...d,
          ownerName,
          ownerProfile: meetupOwnerPublicProfile(d.ownerId, u),
          currentParticipants: (d.participants || []).length,
        };
      });
      return res.json({ rooms });
    }

    // Discovery: active (upcoming, not ended) or past (grey tab) — full rooms stay visible until host closes or time passes
    const pastDiscovery = req.query.past === '1' || req.query.past === 'true';
    const nowIso = new Date().toISOString();
    const nowMs = Date.now();

    const enrichRoomDocs = async (docs) => {
      const ownerIds = [...new Set(docs.map((doc) => doc.data().ownerId).filter(Boolean))];
      const owners = await fetchUserDocsByIds(ownerIds);
      return docs.map((doc) => {
        const d = doc.data();
        const u = d.ownerId ? owners.get(d.ownerId) : null;
        const ownerName = u ? (u.displayName || 'Host') : 'Host';
        return {
          id: doc.id,
          ...d,
          ownerName,
          ownerProfile: meetupOwnerPublicProfile(d.ownerId, u),
          currentParticipants: (d.participants || []).length,
        };
      });
    };

    if (!pastDiscovery) {
      const fetchLim = Math.min(limit * 3, 120);
      const [snapOpen, snapFull] = await Promise.all([
        db.collection('rooms').where('status', '==', 'open').orderBy('eventAt', 'asc').limit(fetchLim).get(),
        db.collection('rooms').where('status', '==', 'full').orderBy('eventAt', 'asc').limit(fetchLim).get(),
      ]);
      const byId = new Map();
      for (const doc of snapOpen.docs) byId.set(doc.id, doc);
      for (const doc of snapFull.docs) byId.set(doc.id, doc);
      let activeDocs = [...byId.values()].filter((doc) => {
        const d = doc.data();
        const st = d.status || 'open';
        if (st === 'ended' || st === 'cancelled') return false;
        const t = new Date(d.eventAt || 0).getTime();
        return t >= nowMs;
      });
      activeDocs = filterRoomDocsByQuery(activeDocs, activityTypeQ, roomTypeFilter);
      if (sortDistance && !Number.isNaN(viewerLat) && !Number.isNaN(viewerLng)) {
        activeDocs = sortRoomDocsByDistance(activeDocs, viewerLat, viewerLng);
      } else {
        activeDocs.sort((a, b) => {
          const ta = new Date(a.data().eventAt || 0).getTime();
          const tb = new Date(b.data().eventAt || 0).getTime();
          return ta - tb;
        });
      }
      const slice = activeDocs.slice(0, limit);
      const rooms = await enrichRoomDocs(slice);
      await attachMyRequestStatuses(uid, rooms);
      return res.json({ rooms });
    }

    const [snapEnded, snapCancelled, snapOpenPast, snapFullPast] = await Promise.all([
      db.collection('rooms').where('status', '==', 'ended').orderBy('eventAt', 'desc').limit(limit).get(),
      db.collection('rooms').where('status', '==', 'cancelled').orderBy('eventAt', 'desc').limit(limit).get(),
      db.collection('rooms').where('status', '==', 'open').where('eventAt', '<', nowIso).orderBy('eventAt', 'desc').limit(limit).get(),
      db.collection('rooms').where('status', '==', 'full').where('eventAt', '<', nowIso).orderBy('eventAt', 'desc').limit(limit).get(),
    ]);
    const pastById = new Map();
    for (const doc of snapEnded.docs) pastById.set(doc.id, doc);
    for (const doc of snapCancelled.docs) pastById.set(doc.id, doc);
    for (const doc of snapOpenPast.docs) pastById.set(doc.id, doc);
    for (const doc of snapFullPast.docs) pastById.set(doc.id, doc);
    let pastDocs = [...pastById.values()];
    pastDocs = filterRoomDocsByQuery(pastDocs, activityTypeQ, roomTypeFilter);
    if (sortDistance && !Number.isNaN(viewerLat) && !Number.isNaN(viewerLng)) {
      pastDocs = sortRoomDocsByDistance(pastDocs, viewerLat, viewerLng);
    } else {
      pastDocs.sort((a, b) => {
        const ta = new Date(b.data().eventAt || 0).getTime();
        const tb = new Date(a.data().eventAt || 0).getTime();
        return ta - tb;
      });
    }
    const pastSlice = pastDocs.slice(0, limit);
    const rooms = await enrichRoomDocs(pastSlice);
    await attachMyRequestStatuses(uid, rooms);
    return res.json({ rooms });
  } catch (e) {
    res.status(500).json({ error: e.message });
  }
});

// Get single room (includes myRequestStatus for non-owners: pending | approved | rejected | null)
app.get('/api/rooms/:roomId', requireAuth, async (req, res) => {
  try {
    const { roomId } = req.params;
    const uid = req.uid;
    const doc = await db.collection('rooms').doc(roomId).get();
    if (!doc.exists) return res.status(404).json({ error: 'Room not found' });
    const d = doc.data();
    const ownerDoc = await db.collection('users').doc(d.ownerId).get();
    const od = ownerDoc.exists ? ownerDoc.data() : null;
    const ownerName = od ? (od.displayName || 'Host') : 'Host';
    const payload = {
      id: doc.id,
      ...d,
      ownerName,
      ownerProfile: meetupOwnerPublicProfile(d.ownerId, od),
      currentParticipants: (d.participants || []).length,
    };
    // For non-owners, include whether current user has requested and status
    if (d.ownerId !== uid) {
      const myRequest = await db
        .collection('room_requests')
        .where('roomId', '==', roomId)
        .where('requesterId', '==', uid)
        .limit(1)
        .get();
      if (!myRequest.empty) {
        payload.myRequestStatus = myRequest.docs[0].data().status || 'pending';
      } else {
        payload.myRequestStatus = null;
      }
      const saveSnap = await db.collection('users').doc(uid).collection('meetupSaves').doc(roomId).get();
      payload.isSaved = saveSnap.exists;
    } else {
      payload.isSaved = false;
    }
    res.json(payload);
  } catch (e) {
    res.status(500).json({ error: e.message });
  }
});

// Host closes meetup — only then (or once event time passes) it moves to "past"
app.put('/api/rooms/:roomId/close', requireAuth, async (req, res) => {
  try {
    const { roomId } = req.params;
    const roomDoc = await db.collection('rooms').doc(roomId).get();
    if (!roomDoc.exists) return res.status(404).json({ error: 'Room not found' });
    const room = roomDoc.data();
    if (room.ownerId !== req.uid) {
      return res.status(403).json({ error: 'Only the host can close this meetup' });
    }
    const now = new Date().toISOString();
    await db.collection('rooms').doc(roomId).update({
      status: 'ended',
      updatedAt: now,
      closedAt: now,
      closedByOwner: true,
    });
    const doc = await db.collection('rooms').doc(roomId).get();
    const d = doc.data();
    const ownerDoc = await db.collection('users').doc(d.ownerId).get();
    const ownerName = ownerDoc.exists ? (ownerDoc.data().displayName || 'Host') : 'Host';
    res.json({
      id: doc.id,
      ...d,
      ownerName,
      currentParticipants: (d.participants || []).length,
    });
  } catch (e) {
    res.status(500).json({ error: e.message });
  }
});

// Bookmark meetup (saved list)
app.post('/api/rooms/:roomId/save', requireAuth, async (req, res) => {
  try {
    const { roomId } = req.params;
    const roomDoc = await db.collection('rooms').doc(roomId).get();
    if (!roomDoc.exists) return res.status(404).json({ error: 'Room not found' });
    await db
      .collection('users')
      .doc(req.uid)
      .collection('meetupSaves')
      .doc(roomId)
      .set({ savedAt: new Date().toISOString() });
    res.json({ ok: true });
  } catch (e) {
    res.status(500).json({ error: e.message });
  }
});

app.delete('/api/rooms/:roomId/save', requireAuth, async (req, res) => {
  try {
    const { roomId } = req.params;
    await db.collection('users').doc(req.uid).collection('meetupSaves').doc(roomId).delete();
    res.json({ ok: true });
  } catch (e) {
    res.status(500).json({ error: e.message });
  }
});

app.get('/api/me/meetup-saved-ids', requireAuth, async (req, res) => {
  try {
    const lim = Math.min(parseInt(req.query.limit || '100', 10), 200);
    const snap = await db
      .collection('users')
      .doc(req.uid)
      .collection('meetupSaves')
      .orderBy('savedAt', 'desc')
      .limit(lim)
      .get();
    res.json({ roomIds: snap.docs.map((d) => d.id) });
  } catch (e) {
    res.status(500).json({ error: e.message });
  }
});

// Create room (women or premium male only)
app.post('/api/rooms', requireAuth, async (req, res) => {
  try {
    if (!(await canCreateRoom(req.uid))) {
      return res.status(403).json({
        error: 'Only women or premium members can create rooms. Upgrade to create your own.',
      });
    }
    const {
      title,
      activityType,
      activityLabel,
      activityEmoji,
      placeName,
      placeAddress,
      roomType,
      maxParticipants,
      tags,
      eventAt,
      latitude,
      longitude,
    } = req.body;
    if (!title?.trim() || !activityType || !placeName?.trim()) {
      return res.status(400).json({ error: 'title, activityType, and placeName required' });
    }
    const ref = db.collection('rooms').doc();
    const participants = [req.uid];
    const max = roomType === 'group'
      ? Math.min(Math.max(parseInt(maxParticipants, 10) || 4, 8), 8)
      : 2;
    await ref.set({
      ownerId: req.uid,
      title: title.trim(),
      activityType: activityType || 'cafe',
      activityLabel: activityLabel || 'Cafe Date',
      activityEmoji: activityEmoji || '☕',
      placeName: (placeName || '').trim(),
      placeAddress: (placeAddress || '').trim() || null,
      roomType: roomType === 'group' ? 'group' : 'personal',
      maxParticipants: max,
      participants,
      tags: Array.isArray(tags) ? tags : [],
      eventAt: eventAt || new Date().toISOString(),
      latitude: latitude != null ? Number(latitude) : null,
      longitude: longitude != null ? Number(longitude) : null,
      status: 'open',
      createdAt: new Date().toISOString(),
      updatedAt: new Date().toISOString(),
    });
    const doc = await ref.get();
    res.status(201).json({ id: doc.id, ...doc.data() });
  } catch (e) {
    res.status(500).json({ error: e.message });
  }
});

// Request to join room
app.post('/api/rooms/:roomId/requests', requireAuth, async (req, res) => {
  try {
    const { roomId } = req.params;
    const uid = req.uid;
    const roomDoc = await db.collection('rooms').doc(roomId).get();
    if (!roomDoc.exists) return res.status(404).json({ error: 'Room not found' });
    const room = roomDoc.data();
    if (room.status === 'ended' || room.status === 'cancelled') {
      return res.status(400).json({ error: 'This meetup is closed' });
    }
    const eventMs = new Date(room.eventAt || 0).getTime();
    if (eventMs < Date.now()) {
      return res.status(400).json({ error: 'This meetup date has passed' });
    }
    if (room.participants && room.participants.includes(uid)) {
      return res.status(400).json({ error: 'Already in this room' });
    }
    if ((room.participants || []).length >= (room.maxParticipants || 2)) {
      return res.status(400).json({ error: 'Room is full' });
    }
    const existing = await db
      .collection('room_requests')
      .where('roomId', '==', roomId)
      .where('requesterId', '==', uid)
      .limit(1)
      .get();
    if (!existing.empty) {
      return res.status(400).json({ error: 'You already sent a request' });
    }
    const requesterDoc = await db.collection('users').doc(uid).get();
    const requesterName = requesterDoc.exists ? (requesterDoc.data().displayName || 'Someone') : 'Someone';
    const ref = db.collection('room_requests').doc();
    await ref.set({
      roomId,
      requesterId: uid,
      requesterName,
      status: 'pending',
      createdAt: new Date().toISOString(),
    });
    const doc = await ref.get();
    res.status(201).json({ id: doc.id, ...doc.data() });
  } catch (e) {
    res.status(500).json({ error: e.message });
  }
});

// List requests for a room (owner only)
app.get('/api/rooms/:roomId/requests', requireAuth, async (req, res) => {
  try {
    const { roomId } = req.params;
    const roomDoc = await db.collection('rooms').doc(roomId).get();
    if (!roomDoc.exists) return res.status(404).json({ error: 'Room not found' });
    if (roomDoc.data().ownerId !== req.uid) {
      return res.status(403).json({ error: 'Only the room owner can see requests' });
    }
    const snapshot = await db
      .collection('room_requests')
      .where('roomId', '==', roomId)
      .where('status', '==', 'pending')
      .get();
    const list = snapshot.docs
      .map((d) => ({ id: d.id, ...d.data() }))
      .sort((a, b) => (b.createdAt || '').localeCompare(a.createdAt || ''));
    const hostSnap = await db.collection('users').doc(roomDoc.data().ownerId).get();
    const hostData = hostSnap.exists ? hostSnap.data() : {};
    const requesterIds = [...new Set(list.map((r) => r.requesterId).filter(Boolean))];
    const requesters = await fetchUserDocsByIds(requesterIds);
    for (const item of list) {
      const rd = requesters.get(item.requesterId);
      if (rd) {
        item.interestMatchPercent = meetupRequestInterestPercent(hostData, rd);
      }
    }
    res.json({ requests: list });
  } catch (e) {
    res.status(500).json({ error: e.message });
  }
});

// Approve or reject request (owner only). On approve: create match with room tag so they can chat.
app.put('/api/rooms/:roomId/requests/:requestId', requireAuth, async (req, res) => {
  try {
    const { roomId, requestId } = req.params;
    const { action } = req.body; // 'approve' | 'reject'
    if (action !== 'approve' && action !== 'reject') {
      return res.status(400).json({ error: 'action must be approve or reject' });
    }
    const roomDoc = await db.collection('rooms').doc(roomId).get();
    if (!roomDoc.exists) return res.status(404).json({ error: 'Room not found' });
    const room = roomDoc.data();
    if (room.ownerId !== req.uid) {
      return res.status(403).json({ error: 'Only the room owner can approve or reject' });
    }
    const reqDoc = await db.collection('room_requests').doc(requestId).get();
    if (!reqDoc.exists) return res.status(404).json({ error: 'Request not found' });
    const reqData = reqDoc.data();
    if (reqData.roomId !== roomId || reqData.status !== 'pending') {
      return res.status(400).json({ error: 'Invalid request' });
    }
    if (action === 'approve') {
      if (room.status === 'ended' || room.status === 'cancelled') {
        return res.status(400).json({ error: 'This meetup is closed' });
      }
      const eventMs = new Date(room.eventAt || 0).getTime();
      if (eventMs < Date.now()) {
        return res.status(400).json({ error: 'This meetup date has passed' });
      }
    }
    const now = new Date().toISOString();
    await db.collection('room_requests').doc(requestId).update({
      status: action,
      reviewedAt: now,
    });
    if (action === 'approve') {
      const requesterId = reqData.requesterId;
      const participants = room.participants || [room.ownerId];
      if (!participants.includes(requesterId)) {
        participants.push(requesterId);
        // Stay "open" when full — meetups only leave the active feed when the host
        // closes them or the event time has passed (see GET /api/rooms filters).
        await db.collection('rooms').doc(roomId).update({
          participants,
          updatedAt: now,
        });
      }
      // Create or get match so they can chat in Matches; add room tag
      const matchParticipants = [room.ownerId, requesterId].sort();
      const matchId = matchParticipants.join('_');
      const matchRef = db.collection('matches').doc(matchId);
      const matchDoc = await matchRef.get();
      const roomTag = { roomId, roomName: room.title || 'Room' };
      if (matchDoc.exists) {
        await matchRef.update({
          updatedAt: now,
          roomId: roomId,
          roomName: room.title || 'Room',
        });
      } else {
        await matchRef.set({
          participants: matchParticipants,
          createdAt: now,
          updatedAt: now,
          roomId,
          roomName: room.title || 'Room',
        });
      }
      return res.json({
        ok: true,
        action: 'approved',
        matchId,
        roomName: room.title,
      });
    }
    res.json({ ok: true, action: 'rejected' });
  } catch (e) {
    res.status(500).json({ error: e.message });
  }
});

// --- Safety: report / block ---
app.post('/api/reports', requireAuth, async (req, res) => {
  try {
    const { targetId, reason, details } = req.body;
    if (!targetId || !reason) return res.status(400).json({ error: 'targetId and reason required' });
    await db.collection('reports').add({
      reporterId: req.uid,
      targetId,
      reason,
      details: details || null,
      createdAt: new Date().toISOString(),
    });
    res.json({ ok: true });
  } catch (e) {
    res.status(500).json({ error: e.message });
  }
});

app.post('/api/blocks', requireAuth, async (req, res) => {
  try {
    const { targetId } = req.body;
    if (!targetId) return res.status(400).json({ error: 'targetId required' });
    if (targetId === req.uid) {
      return res.status(400).json({ error: 'Invalid target' });
    }
    await db.collection('blocks').doc(`${req.uid}_${targetId}`).set({
      fromId: req.uid,
      toId: targetId,
      createdAt: new Date().toISOString(),
    });
    bustDiscoveryPrepCacheForUsers(req.uid, targetId);
    const sorted = [req.uid, targetId].sort();
    const canonicalMatchId = `${sorted[0]}_${sorted[1]}`;
    const matchSnap = await db.collection('matches').doc(canonicalMatchId).get();
    if (matchSnap.exists) {
      await deleteMatchAndMessages(canonicalMatchId);
    }
    res.json({ ok: true });
  } catch (e) {
    res.status(500).json({ error: e.message });
  }
});

// --- Health ---
app.get('/health', (_, res) => res.json({ status: 'ok' }));

const PORT = process.env.PORT || 8080;
app.listen(PORT, () => {
  console.log(`Spark API running on port ${PORT}`);
});
