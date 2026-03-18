/// Room (experience) model — cafe date, hiking, dinner, etc.
class Room {
  const Room({
    required this.id,
    required this.ownerId,
    required this.ownerName,
    required this.activityType,
    required this.activityLabel,
    required this.activityEmoji,
    required this.title,
    required this.placeName,
    required this.placeAddress,
    required this.roomType,
    required this.maxParticipants,
    required this.currentParticipants,
    required this.tags,
    required this.eventAt,
    required this.createdAt,
    required this.status,
    this.latitude,
    this.longitude,
    this.imageUrl,
    this.myRequestStatus,
  });

  final String id;
  final String ownerId;
  final String ownerName;
  /// Set when fetching single room as non-owner: 'pending' | 'approved' | 'rejected' | null
  final String? myRequestStatus;
  final String activityType;
  final String activityLabel;
  final String activityEmoji;
  final String title;
  final String placeName;
  final String placeAddress;
  final RoomType roomType;
  final int maxParticipants;
  final int currentParticipants;
  final List<String> tags;
  final DateTime eventAt;
  final DateTime createdAt;
  final RoomStatus status;
  final double? latitude;
  final double? longitude;
  final String? imageUrl;

  bool get isFull => currentParticipants >= maxParticipants;
  int get seatsLeft => (maxParticipants - currentParticipants).clamp(0, maxParticipants);

  factory Room.fromJson(Map<String, dynamic> json) {
    return Room(
      id: json['id'] as String? ?? '',
      ownerId: json['ownerId'] as String? ?? '',
      ownerName: json['ownerName'] as String? ?? 'Host',
      activityType: json['activityType'] as String? ?? 'cafe',
      activityLabel: json['activityLabel'] as String? ?? 'Cafe Date',
      activityEmoji: json['activityEmoji'] as String? ?? '☕',
      title: json['title'] as String? ?? '',
      placeName: json['placeName'] as String? ?? '',
      placeAddress: json['placeAddress'] as String? ?? '',
      roomType: RoomType.fromString(json['roomType'] as String?),
      maxParticipants: (json['maxParticipants'] as num?)?.toInt() ?? 2,
      currentParticipants: (json['currentParticipants'] as num?)?.toInt() ?? 0,
      tags: (json['tags'] as List<dynamic>?)?.map((e) => e.toString()).toList() ?? [],
      eventAt: json['eventAt'] != null ? DateTime.tryParse(json['eventAt'].toString()) ?? DateTime.now() : DateTime.now(),
      createdAt: json['createdAt'] != null ? DateTime.tryParse(json['createdAt'].toString()) ?? DateTime.now() : DateTime.now(),
      status: RoomStatus.fromString(json['status'] as String?),
      latitude: (json['latitude'] as num?)?.toDouble(),
      longitude: (json['longitude'] as num?)?.toDouble(),
      imageUrl: json['imageUrl'] as String?,
      myRequestStatus: json['myRequestStatus'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'ownerId': ownerId,
      'ownerName': ownerName,
      'activityType': activityType,
      'activityLabel': activityLabel,
      'activityEmoji': activityEmoji,
      'title': title,
      'placeName': placeName,
      'placeAddress': placeAddress,
      'roomType': roomType.value,
      'maxParticipants': maxParticipants,
      'currentParticipants': currentParticipants,
      'tags': tags,
      'eventAt': eventAt.toIso8601String(),
      'createdAt': createdAt.toIso8601String(),
      'status': status.value,
      if (latitude != null) 'latitude': latitude,
      if (longitude != null) 'longitude': longitude,
      if (imageUrl != null) 'imageUrl': imageUrl,
    };
  }
}

enum RoomType {
  personal('personal'),
  group('group');

  const RoomType(this.value);
  final String value;

  static RoomType fromString(String? v) {
    if (v == 'group') return RoomType.group;
    return RoomType.personal;
  }
}

enum RoomStatus {
  open('open'),
  full('full'),
  cancelled('cancelled'),
  ended('ended');

  const RoomStatus(this.value);
  final String value;

  static RoomStatus fromString(String? v) {
    switch (v) {
      case 'full': return RoomStatus.full;
      case 'cancelled': return RoomStatus.cancelled;
      case 'ended': return RoomStatus.ended;
      default: return RoomStatus.open;
    }
  }
}

/// Request to join a room — pending/approved/rejected by owner
class RoomRequest {
  const RoomRequest({
    required this.id,
    required this.roomId,
    required this.requesterId,
    required this.requesterName,
    required this.status,
    required this.createdAt,
    this.reviewedAt,
    this.matchId,
    this.interestMatchPercent,
  });

  final String id;
  final String roomId;
  final String requesterId;
  final String requesterName;
  final RoomRequestStatus status;
  final DateTime createdAt;
  final DateTime? reviewedAt;
  final String? matchId;
  final int? interestMatchPercent;

  factory RoomRequest.fromJson(Map<String, dynamic> json) {
    return RoomRequest(
      id: json['id'] as String? ?? '',
      roomId: json['roomId'] as String? ?? '',
      requesterId: json['requesterId'] as String? ?? '',
      requesterName: json['requesterName'] as String? ?? 'Someone',
      status: RoomRequestStatus.fromString(json['status'] as String?),
      createdAt: json['createdAt'] != null ? DateTime.tryParse(json['createdAt'].toString()) ?? DateTime.now() : DateTime.now(),
      reviewedAt: json['reviewedAt'] != null ? DateTime.tryParse(json['reviewedAt'].toString()) : null,
      matchId: json['matchId'] as String?,
      interestMatchPercent: (json['interestMatchPercent'] as num?)?.toInt(),
    );
  }
}

enum RoomRequestStatus {
  pending('pending'),
  approved('approved'),
  rejected('rejected');

  const RoomRequestStatus(this.value);
  final String value;

  static RoomRequestStatus fromString(String? v) {
    if (v == 'approved') return RoomRequestStatus.approved;
    if (v == 'rejected') return RoomRequestStatus.rejected;
    return RoomRequestStatus.pending;
  }
}
