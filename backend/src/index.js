import express from 'express';
import cors from 'cors';
import dotenv from 'dotenv';
import { initializeApp, getApps, cert } from 'firebase-admin/app';
import { getFirestore } from 'firebase-admin/firestore';
import { getAuth } from 'firebase-admin/auth';
import { getStorage } from 'firebase-admin/storage';
import { readFileSync, existsSync } from 'fs';
import { join, dirname } from 'path';
import { fileURLToPath } from 'url';

dotenv.config();

const __dirname = dirname(fileURLToPath(import.meta.url));

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
app.use(express.json());

if (!getApps().length) {
  const sa = loadServiceAccountJson();
  const projectId =
    process.env.GCLOUD_PROJECT?.trim() ||
    sa?.project_id ||
    'dapp-79473';
  delete process.env.GOOGLE_APPLICATION_CREDENTIALS;

  const options = { projectId };
  if (sa) {
    options.credential = cert(sa);
  }
  const storageBucket = process.env.FIREBASE_STORAGE_BUCKET;
  if (storageBucket) options.storageBucket = storageBucket;
  initializeApp(options);
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

// --- KYC: selfie in Storage users/{uid}/kyc/face.jpg + AWS Rekognition gender vs onboarding ---
app.post('/api/kyc/verify', requireAuth, async (req, res) => {
  try {
    const uid = req.uid;
    const bucketName = process.env.FIREBASE_STORAGE_BUCKET;
    if (!bucketName) {
      return res.status(503).json({ error: 'FIREBASE_STORAGE_BUCKET not set on server' });
    }
    const bucket = getStorage().bucket(bucketName);
    const filePath = `users/${uid}/kyc/face.jpg`;
    const file = bucket.file(filePath);
    const [exists] = await file.exists();
    if (!exists) {
      return res.status(400).json({ error: 'Selfie not found. Capture and upload from the app first.' });
    }
    const [buffer] = await file.download();
    if (!buffer || buffer.length < 500) {
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
  } catch (e) {
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
app.get('/api/discovery', requireAuth, async (req, res) => {
  try {
    const uid = req.uid;
    const me = await db.collection('users').doc(uid).get();
    if (!me.exists || !me.data().kycVerified) {
      return res.status(403).json({ error: 'Complete identity verification to use discovery.' });
    }
    const limit = Math.min(parseInt(req.query.limit || '20', 10), 50);
    // Only completed profiles; fetch extra then filter self (avoids != query + composite index issues).
    const snapshot = await db
      .collection('users')
      .where('profileComplete', '==', true)
      .limit(Math.min(limit + 15, 60))
      .get();
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
