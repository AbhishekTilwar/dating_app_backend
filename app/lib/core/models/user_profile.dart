import 'package:cloud_firestore/cloud_firestore.dart';

/// Mirrors Firestore `users/{uid}` for profile, discovery, and backend API.
class UserProfile {
  const UserProfile({
    required this.id,
    this.displayName,
    this.bio,
    this.photos = const [],
    this.prompts = const [],
    this.relationshipGoal,
    this.openingMove,
    this.gender,
    this.isPremium = false,
    this.profileComplete = false,
    this.onboardingDone = false,
    this.kycVerified = false,
    this.updatedAt,
    this.locationVisible = false,
    this.latitude,
    this.longitude,
  });

  final String id;
  final String? displayName;
  final String? bio;
  final List<String> photos;
  final List<ProfilePrompt> prompts;
  final String? relationshipGoal;
  final String? openingMove;
  final String? gender;
  final bool isPremium;
  final bool profileComplete;
  /// True after user completes onboarding (e.g. gender selection) post-signup.
  final bool onboardingDone;
  /// True after KYC selfie matches onboarding gender; gates discovery/chat etc.
  final bool kycVerified;
  final DateTime? updatedAt;
  /// When true, user appears on the nearby map and in nearby list.
  final bool locationVisible;
  final double? latitude;
  final double? longitude;

  String get primaryPhotoUrl =>
      photos.isNotEmpty ? photos.first : '';

  static UserProfile fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? {};
    final rawPrompts = d['prompts'];
    final prompts = <ProfilePrompt>[];
    if (rawPrompts is List) {
      for (final e in rawPrompts) {
        if (e is Map) {
          final q = e['question']?.toString() ?? '';
          final a = e['answer']?.toString() ?? '';
          if (q.isNotEmpty && a.isNotEmpty) {
            prompts.add(ProfilePrompt(question: q, answer: a));
          }
        }
      }
    }
    final photos = <String>[];
    final rawPhotos = d['photos'];
    if (rawPhotos is List) {
      for (final e in rawPhotos) {
        if (e is String && e.isNotEmpty) photos.add(e);
      }
    }
    DateTime? updated;
    final u = d['updatedAt'];
    if (u is Timestamp) updated = u.toDate();
    if (u is String) updated = DateTime.tryParse(u);

    final locVisible = d['locationVisible'];
    double? lat;
    double? lng;
    final la = d['latitude'];
    final lo = d['longitude'];
    if (la != null) lat = (la is num) ? la.toDouble() : double.tryParse(la.toString());
    if (lo != null) lng = (lo is num) ? lo.toDouble() : double.tryParse(lo.toString());

    return UserProfile(
      id: doc.id,
      displayName: d['displayName'] as String?,
      bio: d['bio'] as String?,
      photos: photos,
      prompts: prompts,
      relationshipGoal: d['relationshipGoal'] as String?,
      openingMove: d['openingMove'] as String?,
      gender: d['gender'] as String?,
      isPremium: d['isPremium'] == true,
      profileComplete: d['profileComplete'] == true,
      onboardingDone: d['onboardingDone'] == true,
      kycVerified: d['kycVerified'] == true,
      updatedAt: updated,
      locationVisible: locVisible == true,
      latitude: lat,
      longitude: lng,
    );
  }
}

/// Nearby user from API (map + list).
class NearbyUser {
  const NearbyUser({
    required this.id,
    this.displayName,
    this.photos = const [],
    this.distanceKm = 0,
    this.latitude,
    this.longitude,
  });

  final String id;
  final String? displayName;
  final List<String> photos;
  final double distanceKm;
  final double? latitude;
  final double? longitude;

  String get primaryPhotoUrl => photos.isNotEmpty ? photos.first : '';

  static NearbyUser fromJson(Map<String, dynamic> json) {
    final rawPhotos = json['photos'];
    final photos = <String>[];
    if (rawPhotos is List) {
      for (final e in rawPhotos) {
        if (e is String && e.isNotEmpty) photos.add(e);
      }
    }
    double? lat;
    double? lng;
    final la = json['latitude'];
    final lo = json['longitude'];
    if (la != null) lat = (la is num) ? la.toDouble() : double.tryParse(la.toString());
    if (lo != null) lng = (lo is num) ? lo.toDouble() : double.tryParse(lo.toString());
    final dist = json['distanceKm'];
    final distanceKm = dist is num ? dist.toDouble() : double.tryParse(dist?.toString() ?? '0') ?? 0;

    return NearbyUser(
      id: json['id'] as String? ?? '',
      displayName: json['displayName'] as String?,
      photos: photos,
      distanceKm: distanceKm,
      latitude: lat,
      longitude: lng,
    );
  }
}

class ProfilePrompt {
  const ProfilePrompt({required this.question, required this.answer});
  final String question;
  final String answer;
}
