import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:spark/core/constants/app_constants.dart';
import 'package:spark/core/models/user_profile.dart';
import 'package:spark/core/services/auth_service.dart';

/// Backend API for current user profile and nearby users (map).
class UserApiService {
  UserApiService({AuthService? authService})
      : _auth = authService ?? AuthService();

  final AuthService _auth;
  final String _baseUrl = AppConstants.apiBaseUrl;

  Future<String?> _getIdToken() async {
    return _auth.currentUser?.getIdToken();
  }

  Future<Map<String, String>> _headers() async {
    final token = await _getIdToken();
    return {
      'Content-Type': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    };
  }

  static String _bodyError(http.Response res) {
    try {
      final m = jsonDecode(res.body);
      if (m is Map && m['error'] != null) return m['error'] as String;
    } catch (_) {}
    return res.body.isNotEmpty ? res.body : 'Request failed';
  }

  /// Get current user profile (includes locationVisible, latitude, longitude).
  Future<Map<String, dynamic>> getMe() async {
    final uri = Uri.parse('$_baseUrl/api/users/me');
    final res = await http.get(uri, headers: await _headers());
    if (res.statusCode == 404) throw UserApiException('Profile not found', 404);
    if (res.statusCode != 200) {
      throw UserApiException(_bodyError(res), res.statusCode);
    }
    final data = jsonDecode(res.body) as Map<String, dynamic>;
    return data;
  }

  /// Update profile; pass only fields to update (e.g. locationVisible, latitude, longitude).
  Future<Map<String, dynamic>> updateMe({
    bool? locationVisible,
    double? latitude,
    double? longitude,
  }) async {
    final uri = Uri.parse('$_baseUrl/api/users/me');
    final body = <String, dynamic>{};
    if (locationVisible != null) body['locationVisible'] = locationVisible;
    if (latitude != null) body['latitude'] = latitude;
    if (longitude != null) body['longitude'] = longitude;
    final res = await http.put(
      uri,
      headers: await _headers(),
      body: jsonEncode(body),
    );
    if (res.statusCode != 200) {
      throw UserApiException(_bodyError(res), res.statusCode);
    }
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  /// After selfie is uploaded to Storage at users/{uid}/kyc/face.jpg, server verifies via Rekognition.
  Future<void> verifyKyc() async {
    final uri = Uri.parse('$_baseUrl/api/kyc/verify');
    // Fresh token after camera flow (avoids stale token; backend must match app Firebase project).
    final token = await _auth.currentUser?.getIdToken(true);
    if (token == null || token.isEmpty) {
      throw UserApiException('Not signed in. Sign in again and retry.', 401);
    }
    final res = await http.post(
      uri,
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      },
      body: '{}',
    );
    if (res.statusCode != 200) {
      throw UserApiException(_bodyError(res), res.statusCode);
    }
  }

  /// Fetch nearby users who have location visible (for map and list).
  Future<List<NearbyUser>> getNearby({
    required double latitude,
    required double longitude,
    double radiusKm = 100,
    int limit = 50,
  }) async {
    final uri = Uri.parse('$_baseUrl/api/nearby').replace(
      queryParameters: {
        'lat': latitude.toString(),
        'lng': longitude.toString(),
        'radiusKm': radiusKm.toString(),
        'limit': limit.toString(),
      },
    );
    final res = await http.get(uri, headers: await _headers());
    if (res.statusCode != 200) {
      throw UserApiException(_bodyError(res), res.statusCode);
    }
    final data = jsonDecode(res.body) as Map<String, dynamic>;
    final list = data['nearby'] as List<dynamic>? ?? [];
    return list
        .map((e) => NearbyUser.fromJson(e as Map<String, dynamic>))
        .toList();
  }
}

class UserApiException implements Exception {
  UserApiException(this.message, [this.statusCode]);

  final String message;
  final int? statusCode;

  @override
  String toString() => message;
}
