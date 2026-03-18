import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';
import 'package:spark/core/models/user_profile.dart';
import 'package:spark/core/utils/image_compression.dart' show compressBytesForUpload, compressForUpload, kKycMaxBytes;
import 'package:uuid/uuid.dart';

/// Firestore `users/{uid}` + Storage `users/{uid}/photos/*`.
/// Same field names as backend `PUT /api/users/me`.
class UserProfileService {
  UserProfileService()
      : _db = FirebaseFirestore.instance,
        _storage = FirebaseStorage.instance;

  final FirebaseFirestore _db;
  final FirebaseStorage _storage;

  DocumentReference<Map<String, dynamic>> _ref(String uid) =>
      _db.collection('users').doc(uid);

  /// Live profile updates (profile tab, cross-device).
  Stream<UserProfile?> profileStream(String uid) {
    return _ref(uid).snapshots().map((doc) {
      if (!doc.exists) return null;
      return UserProfile.fromDoc(doc);
    });
  }

  Future<UserProfile?> getProfile(String uid) async {
    final doc = await _ref(uid).get();
    if (!doc.exists) return null;
    return UserProfile.fromDoc(doc);
  }

  /// Stub doc on first sign-in.
  Future<void> ensureUserDocument(User user) async {
    final ref = _ref(user.uid);
    final snap = await ref.get();
    if (snap.exists) {
      final d = snap.data();
      if (d != null &&
          d['profileComplete'] == true &&
          !d.containsKey('onboardingDone')) {
        await ref.set({
          'onboardingDone': true,
          'kycVerified': true,
        }, SetOptions(merge: true));
      }
      return;
    }
    final name = user.displayName?.trim().isNotEmpty == true
        ? user.displayName!.trim()
        : (user.email?.split('@').first ?? 'Member');
    await ref.set({
      'displayName': name,
      'photos': <String>[],
      'prompts': <Map<String, dynamic>>[],
      'profileComplete': false,
      'onboardingDone': false,
      'kycVerified': false,
      'isPremium': false,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: false));
  }

  Future<String> uploadProfilePhoto(String uid, XFile file) async {
    final compressed = await compressForUpload(file);
    if (compressed.isEmpty) {
      throw Exception('Image compression failed');
    }
    final id = const Uuid().v4();
    final ref = _storage.ref().child('users/$uid/photos/$id.jpg');
    await ref.putData(
      compressed,
      SettableMetadata(
        contentType: 'image/jpeg',
        cacheControl: 'public,max-age=31536000',
      ),
    );
    return ref.getDownloadURL();
  }

  /// KYC selfie: camera-only image, compressed, stored at users/{uid}/kyc/face.jpg
  Future<String> uploadKycImage(String uid, XFile file) async {
    final bytes = await file.readAsBytes();
    final compressed = await compressBytesForUpload(
      bytes,
      maxBytes: kKycMaxBytes,
      maxWidth: 640,
      maxHeight: 640,
      minQuality: 20,
    );
    if (compressed.isEmpty) {
      throw Exception('KYC image compression failed');
    }
    final ref = _storage.ref().child('users/$uid/kyc/face.jpg');
    await ref.putData(
      compressed,
      SettableMetadata(contentType: 'image/jpeg'),
    );
    return ref.getDownloadURL();
  }

  /// Merge partial profile (autosave during setup).
  Future<void> mergeProfileFields({
    required String uid,
    String? displayName,
    List<String>? photos,
    List<ProfilePrompt>? prompts,
    String? relationshipGoal,
    String? openingMove,
    String? gender,
    bool? profileComplete,
    bool? onboardingDone,
    bool? kycVerified,
  }) async {
    final data = <String, dynamic>{
      'updatedAt': FieldValue.serverTimestamp(),
    };
    if (displayName != null) data['displayName'] = displayName.trim();
    if (photos != null) data['photos'] = photos;
    if (prompts != null) {
      data['prompts'] =
          prompts.map((p) => {'question': p.question, 'answer': p.answer}).toList();
    }
    if (relationshipGoal != null) data['relationshipGoal'] = relationshipGoal;
    if (openingMove != null) data['openingMove'] = openingMove;
    if (gender != null) data['gender'] = gender;
    if (profileComplete != null) data['profileComplete'] = profileComplete;
    if (onboardingDone != null) data['onboardingDone'] = onboardingDone;
    if (kycVerified != null) data['kycVerified'] = kycVerified;
    await _ref(uid).set(data, SetOptions(merge: true));
  }

  static Future<void> navigateAfterSignIn(void Function(String location) go) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      go('/auth');
      return;
    }
    final svc = UserProfileService();
    await svc.ensureUserDocument(user);
    final p = await svc.getProfile(user.uid);
    if (p == null || !p.onboardingDone) {
      go('/onboarding');
      return;
    }
    if (!p.profileComplete) {
      go('/profile-setup');
      return;
    }
    if (!p.kycVerified) {
      go('/kyc');
      return;
    }
    go('/home');
  }
}
