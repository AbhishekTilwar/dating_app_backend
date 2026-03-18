import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:spark/core/constants/app_constants.dart';
import 'package:spark/core/services/auth_service.dart';
import 'package:spark/features/rooms/data/room_models.dart';

/// Calls backend rooms API with Firebase ID token. Only event owners see "my" events and requests.
class RoomsApiService {
  RoomsApiService({AuthService? authService})
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

  /// List rooms: discovery (open) or mine (owner's created events).
  Future<List<Room>> getRooms({bool mine = false}) async {
    final uri = Uri.parse('$_baseUrl/api/rooms').replace(
      queryParameters: {'mine': mine ? '1' : '0', 'limit': '50'},
    );
    final res = await http.get(uri, headers: await _headers());
    if (res.statusCode != 200) {
      throw RoomsApiException(_bodyError(res), res.statusCode);
    }
    final data = jsonDecode(res.body) as Map<String, dynamic>;
    final list = data['rooms'] as List<dynamic>? ?? [];
    return list.map((e) => Room.fromJson(e as Map<String, dynamic>)).toList();
  }

  /// Get single room; includes myRequestStatus for non-owners.
  Future<Room> getRoom(String roomId) async {
    final uri = Uri.parse('$_baseUrl/api/rooms/$roomId');
    final res = await http.get(uri, headers: await _headers());
    if (res.statusCode == 404) throw RoomsApiException('Room not found', 404);
    if (res.statusCode != 200) {
      throw RoomsApiException(_bodyError(res), res.statusCode);
    }
    final data = jsonDecode(res.body) as Map<String, dynamic>;
    return Room.fromJson(data);
  }

  /// Create room (women or premium only on backend).
  Future<Room> createRoom({
    required String title,
    required String activityType,
    String? activityLabel,
    String? activityEmoji,
    required String placeName,
    String? placeAddress,
    required String roomType,
    int? maxParticipants,
    List<String>? tags,
    String? eventAt,
    double? latitude,
    double? longitude,
  }) async {
    final uri = Uri.parse('$_baseUrl/api/rooms');
    final body = {
      'title': title,
      'activityType': activityType,
      if (activityLabel != null) 'activityLabel': activityLabel,
      if (activityEmoji != null) 'activityEmoji': activityEmoji,
      'placeName': placeName,
      if (placeAddress != null && placeAddress.isNotEmpty) 'placeAddress': placeAddress,
      'roomType': roomType,
      if (maxParticipants != null) 'maxParticipants': maxParticipants,
      if (tags != null && tags.isNotEmpty) 'tags': tags,
      if (eventAt != null) 'eventAt': eventAt,
      if (latitude != null) 'latitude': latitude,
      if (longitude != null) 'longitude': longitude,
    };
    final res = await http.post(
      uri,
      headers: await _headers(),
      body: jsonEncode(body),
    );
    if (res.statusCode == 403) {
      throw RoomsApiException(
        _bodyError(res).isNotEmpty ? _bodyError(res) : 'Only women or premium members can create rooms.',
        403,
      );
    }
    if (res.statusCode != 201) {
      throw RoomsApiException(_bodyError(res), res.statusCode);
    }
    final data = jsonDecode(res.body) as Map<String, dynamic>;
    return Room.fromJson(data);
  }

  /// Request to join a room (audience).
  Future<void> requestToJoin(String roomId) async {
    final uri = Uri.parse('$_baseUrl/api/rooms/$roomId/requests');
    final res = await http.post(uri, headers: await _headers());
    if (res.statusCode == 400) throw RoomsApiException(_bodyError(res), 400);
    if (res.statusCode == 404) throw RoomsApiException('Room not found', 404);
    if (res.statusCode != 201) {
      throw RoomsApiException(_bodyError(res), res.statusCode);
    }
  }

  /// List pending requests for a room (owner only).
  Future<List<RoomRequest>> getRoomRequests(String roomId) async {
    final uri = Uri.parse('$_baseUrl/api/rooms/$roomId/requests');
    final res = await http.get(uri, headers: await _headers());
    if (res.statusCode == 403) {
      throw RoomsApiException('Only the room owner can see requests', 403);
    }
    if (res.statusCode == 404) throw RoomsApiException('Room not found', 404);
    if (res.statusCode != 200) {
      throw RoomsApiException(_bodyError(res), res.statusCode);
    }
    final data = jsonDecode(res.body) as Map<String, dynamic>;
    final list = data['requests'] as List<dynamic>? ?? [];
    return list.map((e) => RoomRequest.fromJson(e as Map<String, dynamic>)).toList();
  }

  /// Approve or reject a join request (owner only).
  Future<void> reviewRequest(String roomId, String requestId, {required bool approve}) async {
    final uri = Uri.parse('$_baseUrl/api/rooms/$roomId/requests/$requestId');
    final res = await http.put(
      uri,
      headers: await _headers(),
      body: jsonEncode({'action': approve ? 'approve' : 'reject'}),
    );
    if (res.statusCode == 403) {
      throw RoomsApiException('Only the room owner can approve or reject', 403);
    }
    if (res.statusCode != 200) {
      throw RoomsApiException(_bodyError(res), res.statusCode);
    }
  }

  static String _bodyError(http.Response res) {
    try {
      final m = jsonDecode(res.body);
      if (m is Map && m['error'] != null) return m['error'] as String;
    } catch (_) {}
    return res.body.isNotEmpty ? res.body : 'Request failed';
  }
}

class RoomsApiException implements Exception {
  RoomsApiException(this.message, [this.statusCode]);

  final String message;
  final int? statusCode;

  @override
  String toString() => message;
}
