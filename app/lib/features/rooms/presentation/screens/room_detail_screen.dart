import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:spark/core/services/auth_service.dart';
import 'package:spark/features/rooms/data/room_models.dart';
import 'package:spark/features/rooms/data/rooms_api_service.dart';

/// Room detail: owner sees event + pending requests (approve/reject); others request to join.
class RoomDetailScreen extends StatefulWidget {
  const RoomDetailScreen({super.key, required this.roomId});

  final String roomId;

  @override
  State<RoomDetailScreen> createState() => _RoomDetailScreenState();
}

class _RoomDetailScreenState extends State<RoomDetailScreen> {
  final AuthService _auth = AuthService();
  final RoomsApiService _api = RoomsApiService();

  Room? _room;
  List<RoomRequest> _pendingRequests = [];
  bool _loading = true;
  String? _error;
  bool _actionLoading = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final room = await _api.getRoom(widget.roomId);
      if (!mounted) return;
      List<RoomRequest> requests = [];
      if (room.ownerId == _auth.uid) {
        requests = await _api.getRoomRequests(widget.roomId);
      }
      if (!mounted) return;
      setState(() {
        _room = room;
        _pendingRequests = requests;
        _loading = false;
      });
    } on RoomsApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.message;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  bool get _isOwner => _room != null && _auth.uid != null && _room!.ownerId == _auth.uid;
  bool get _hasRequested =>
      _room?.myRequestStatus != null &&
      (_room!.myRequestStatus == 'pending' || _room!.myRequestStatus == 'approved');

  Future<void> _requestToJoin() async {
    if (_room == null || _actionLoading) return;
    setState(() => _actionLoading = true);
    try {
      await _api.requestToJoin(widget.roomId);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Request sent! The host will review it.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      await _load();
    } on RoomsApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.message),
          behavior: SnackBarBehavior.floating,
          backgroundColor: Theme.of(context).colorScheme.errorContainer,
        ),
      );
    } finally {
      if (mounted) setState(() => _actionLoading = false);
    }
  }

  Future<void> _reviewRequest(String requestId, {required bool approve}) async {
    if (_actionLoading) return;
    setState(() => _actionLoading = true);
    try {
      await _api.reviewRequest(widget.roomId, requestId, approve: approve);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(approve ? 'Request approved' : 'Request rejected'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      await _load();
    } on RoomsApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.message),
          behavior: SnackBarBehavior.floating,
          backgroundColor: Theme.of(context).colorScheme.errorContainer,
        ),
      );
    } finally {
      if (mounted) setState(() => _actionLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (_loading) {
      return Scaffold(
        appBar: AppBar(
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_rounded),
            onPressed: () => context.pop(),
          ),
          title: const Text('Meetup'),
        ),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (_error != null || _room == null) {
      return Scaffold(
        appBar: AppBar(
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_rounded),
            onPressed: () => context.pop(),
          ),
          title: const Text('Meetup'),
        ),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.error_outline_rounded, size: 48, color: theme.colorScheme.error),
                const SizedBox(height: 16),
                Text(_error ?? 'Room not found', textAlign: TextAlign.center),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: () => context.pop(),
                  child: const Text('Go back'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final room = _room!;
    final dateFormat = DateFormat('EEEE, MMM d · h:mm a');
    final isOwner = _isOwner;

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => context.pop(),
        ),
        title: const Text('Meetup'),
        actions: [
          IconButton(
            icon: const Icon(Icons.share_rounded),
            onPressed: () {},
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Header card
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: theme.colorScheme.primaryContainer.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(room.activityEmoji, style: const TextStyle(fontSize: 40)),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              room.title,
                              style: theme.textTheme.titleLarge?.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            Text(
                              '${room.placeName} · ${room.placeAddress}',
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Text(
                    dateFormat.format(room.eventAt),
                    style: theme.textTheme.bodyLarge?.copyWith(
                      color: theme.colorScheme.primary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Icon(Icons.people_outline_rounded,
                          size: 20, color: theme.colorScheme.onSurfaceVariant),
                      const SizedBox(width: 6),
                      Text(
                        '${room.currentParticipants} / ${room.maxParticipants} ${room.roomType.value == 'personal' ? 'person' : 'people'}',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                  if (room.tags.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: room.tags
                          .map((t) => Chip(
                                label: Text('#$t', style: theme.textTheme.labelSmall),
                                visualDensity: VisualDensity.compact,
                              ))
                          .toList(),
                    ),
                  ],
                ],
              ),
            )
                .animate()
                .fadeIn()
                .slideY(begin: 0.02, end: 0, curve: Curves.easeOut),

            const SizedBox(height: 24),

            // Host
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: CircleAvatar(
                backgroundColor: theme.colorScheme.primaryContainer,
                child: Text(
                  room.ownerName.isNotEmpty ? room.ownerName[0].toUpperCase() : '?',
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: theme.colorScheme.primary,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              title: Text('Hosted by ${room.ownerName}'),
            ),

            // Requests for this event (owner only)
            if (isOwner) ...[
              const SizedBox(height: 24),
              Text(
                'Join requests',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Review and approve or reject requests. Only you can see this section.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 12),
              if (_pendingRequests.isEmpty)
                Container(
                  padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerLow,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.inbox_rounded,
                        size: 40,
                        color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Text(
                          'No join requests yet',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                    ],
                  ),
                )
              else
                ..._pendingRequests.map((req) => _RequestTile(
                      request: req,
                      onApprove: () => _reviewRequest(req.id, approve: true),
                      onReject: () => _reviewRequest(req.id, approve: false),
                      loading: _actionLoading,
                    )),
            ],

            const SizedBox(height: 32),

            // Action button (non-owner only)
            if (!isOwner) ...[
              if (room.isFull)
                OutlinedButton(
                  onPressed: null,
                  child: const Text('Meetup is full'),
                )
              else if (_hasRequested)
                OutlinedButton(
                  onPressed: null,
                  child: Text(
                    room.myRequestStatus == 'approved'
                        ? 'You\'re in! Check Matches to chat'
                        : 'Request sent – waiting for approval',
                  ),
                )
              else
                FilledButton(
                  onPressed: _actionLoading ? null : _requestToJoin,
                  child: _actionLoading
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Request to join'),
                ),
            ],
          ],
        ),
      ),
    );
  }
}

class _RequestTile extends StatelessWidget {
  const _RequestTile({
    required this.request,
    required this.onApprove,
    required this.onReject,
    this.loading = false,
  });

  final RoomRequest request;
  final VoidCallback onApprove;
  final VoidCallback onReject;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: theme.colorScheme.primaryContainer,
          child: Text(
            request.requesterName.isNotEmpty
                ? request.requesterName[0].toUpperCase()
                : '?',
            style: theme.textTheme.titleMedium?.copyWith(
              color: theme.colorScheme.primary,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        title: Text(request.requesterName),
        subtitle: request.interestMatchPercent != null
            ? Text('Interest match: ${request.interestMatchPercent}%')
            : null,
        trailing: loading
            ? const SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: Icon(Icons.check_circle_rounded, color: theme.colorScheme.primary),
                    onPressed: onApprove,
                    tooltip: 'Approve',
                  ),
                  IconButton(
                    icon: Icon(Icons.cancel_rounded, color: theme.colorScheme.error),
                    onPressed: onReject,
                    tooltip: 'Reject',
                  ),
                ],
              ),
      ),
    );
  }
}
