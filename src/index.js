import express from 'express';
import cors from 'cors';
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
app.use(cors({ origin: true }));
app.use(express.json({ limit: '5mb' }));

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

/** KYC from image bytes (Rekognition). No Cloud Storage read — works without GCS IAM on the server. */
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
    try {
      const { RekognitionClient, DetectFacesCommand } = await import('@aws-sdk/client-rekognition');
      const client = new RekognitionClient({
        region: process.env.AWS_REGION || 'us-east-1',
      });
      const out = await client.send(
        new DetectFacesCommand({
          Image: { Bytes: buffer },
          Attributes: ['ALL'],
        }),
      );
      const face = out.FaceDetails?.[0];
      if (!face) {
        return res.status(400).json({
          error: 'No face detected. Face the camera directly with good lighting.',
        });
      }
      const detGender = String(face.Gender?.Value || '').toLowerCase();
      const conf = face.Gender?.Confidence || 0;
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
        return res.status(503).json({
          error:
            'KYC unavailable. Run npm install in backend, set AWS credentials for Rekognition, or KYC_DEV_APPROVE=1 for local dev.',
        });
      }
      if (
        impErr?.name === 'CredentialsProviderError' ||
        impErr?.$metadata?.httpStatusCode === 403
      ) {
        return res.status(503).json({
          error:
            'AWS Rekognition not configured. Set AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY, AWS_REGION, or KYC_DEV_APPROVE=1.',
        });
      }
      const ename = String(impErr?.name || '');
      const emsg = String(impErr?.message || '');
      if (
        ename.includes('InvalidImage') ||
        ename.includes('InvalidParameter') ||
        /invalid image|image bytes|Request has invalid|malformed/i.test(emsg)
      ) {
        return res.status(400).json({
          error:
            'This photo could not be processed. Retake a clear, well-lit selfie (face the camera).',
        });
      }
      throw impErr;
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
app.post('/api/kyc/verify', requireAuth, async (req, res) => {
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

// --- Nearby (map) — users who have location visible, sorted by distance ---
app.get('/api/nearby', requireAuth, async (req, res) => {
  try {
    const lat = parseFloat(req.query.lat);
    const lng = parseFloat(req.query.lng);
    const radiusKm = Math.min(parseFloat(req.query.radiusKm || '100') || 100, 500);
    const limit = Math.min(parseInt(req.query.limit || '50', 10), 100);
    if (Number.isNaN(lat) || Number.isNaN(lng)) {
      return res.status(400).json({ error: 'lat and lng query params required' });
    }
    const snapshot = await db
      .collection('users')
      .where('locationVisible', '==', true)
      .limit(500)
      .get();
    const meId = req.uid;
    const withDistance = [];
    for (const d of snapshot.docs) {
      if (d.id === meId) continue;
      const data = d.data();
      const userLat = data.latitude;
      const userLng = data.longitude;
      if (userLat == null || userLng == null) continue;
      const km = haversineKm(lat, lng, userLat, userLng);
      if (km > radiusKm) continue;
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
// Optional query: gender = 'Male' | 'Female' | 'Transgender' to filter by profile gender.
app.get('/api/discovery', requireAuth, async (req, res) => {
  try {
    const uid = req.uid;
    const me = await db.collection('users').doc(uid).get();
    if (!me.exists || !me.data().kycVerified) {
      return res.status(403).json({ error: 'Complete identity verification to use discovery.' });
    }
    const limit = Math.min(parseInt(req.query.limit || '20', 10), 50);
    const genderFilter = (req.query.gender || '').toString().trim();
    const allowedGenders = ['Male', 'Female', 'Transgender', 'Non-binary', 'Prefer not to say'];
    const gender = allowedGenders.includes(genderFilter) ? genderFilter : null;

    let query = db.collection('users').where('profileComplete', '==', true);
    if (gender) {
      query = query.where('gender', '==', gender);
    }
    const snapshot = await query.limit(Math.min(limit + 15, 60)).get();

    const list = snapshot.docs
      .filter((d) => d.id !== uid)
      .slice(0, limit)
      .map((d) => ({ id: d.id, ...d.data() }));
    res.json({ suggestions: list });
  } catch (e) {
    res.status(500).json({ error: e.message });
  }
});

// --- Likes / passes ---
app.post('/api/likes', requireAuth, async (req, res) => {
  try {
    const { targetId, superLike } = req.body;
    if (!targetId) return res.status(400).json({ error: 'targetId required' });
    await db.collection('likes').doc(`${req.uid}_${targetId}`).set({
      fromId: req.uid,
      toId: targetId,
      superLike: !!superLike,
      createdAt: new Date().toISOString(),
    });
    res.json({ ok: true });
  } catch (e) {
    res.status(500).json({ error: e.message });
  }
});

app.post('/api/passes', requireAuth, async (req, res) => {
  try {
    const { targetId } = req.body;
    if (!targetId) return res.status(400).json({ error: 'targetId required' });
    await db.collection('passes').doc(`${req.uid}_${targetId}`).set({
      fromId: req.uid,
      toId: targetId,
      createdAt: new Date().toISOString(),
    });
    res.json({ ok: true });
  } catch (e) {
    res.status(500).json({ error: e.message });
  }
});

// --- Matches ---
app.get('/api/matches', requireAuth, async (req, res) => {
  try {
    const snapshot = await db
      .collection('matches')
      .where('participants', 'array-contains', req.uid)
      .orderBy('updatedAt', 'desc')
      .limit(100)
      .get();
    const list = snapshot.docs.map((d) => ({ id: d.id, ...d.data() }));
    res.json({ matches: list });
  } catch (e) {
    res.status(500).json({ error: e.message });
  }
});

// --- Chats ---
app.get('/api/chats/:matchId/messages', requireAuth, async (req, res) => {
  try {
    const { matchId } = req.params;
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
    const { matchId } = req.params;
    const { text } = req.body;
    if (!text?.trim()) return res.status(400).json({ error: 'text required' });
    const ref = db.collection('matches').doc(matchId).collection('messages').doc();
    await ref.set({
      senderId: req.uid,
      text: text.trim(),
      createdAt: new Date().toISOString(),
    });
    await db.collection('matches').doc(matchId).update({
      updatedAt: new Date().toISOString(),
      lastMessage: text.trim().slice(0, 100),
    });
    res.json({ id: ref.id, senderId: req.uid, text: text.trim() });
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

// List rooms: discovery feed (default) or my events (mine=1, owner only)
app.get('/api/rooms', requireAuth, async (req, res) => {
  try {
    const uid = req.uid;
    const mine = req.query.mine === '1' || req.query.mine === 'true';
    const limit = Math.min(parseInt(req.query.limit || '20', 10), 50);

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
      const rooms = await Promise.all(
        sorted.map(async (doc) => {
          const d = doc.data();
          const ownerDoc = await db.collection('users').doc(d.ownerId).get();
          const ownerName = ownerDoc.exists ? (ownerDoc.data().displayName || 'Host') : 'Host';
          return {
            id: doc.id,
            ...d,
            ownerName,
            currentParticipants: (d.participants || []).length,
          };
        })
      );
      return res.json({ rooms });
    }

    // Discovery: open rooms (exclude current user's own for cleaner feed, or include — including is fine)
    const snapshot = await db
      .collection('rooms')
      .where('status', '==', 'open')
      .orderBy('eventAt', 'asc')
      .limit(limit)
      .get();
    const rooms = await Promise.all(
      snapshot.docs.map(async (doc) => {
        const d = doc.data();
        const ownerDoc = await db.collection('users').doc(d.ownerId).get();
        const ownerName = ownerDoc.exists ? (ownerDoc.data().displayName || 'Host') : 'Host';
        return {
          id: doc.id,
          ...d,
          ownerName,
          currentParticipants: (d.participants || []).length,
        };
      })
    );
    res.json({ rooms });
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
    const ownerName = ownerDoc.exists ? (ownerDoc.data().displayName || 'Host') : 'Host';
    const payload = {
      id: doc.id,
      ...d,
      ownerName,
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
    }
    res.json(payload);
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
        await db.collection('rooms').doc(roomId).update({
          participants,
          updatedAt: now,
          ...(participants.length >= (room.maxParticipants || 2) && { status: 'full' }),
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
    await db.collection('blocks').doc(`${req.uid}_${targetId}`).set({
      fromId: req.uid,
      toId: targetId,
      createdAt: new Date().toISOString(),
    });
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
