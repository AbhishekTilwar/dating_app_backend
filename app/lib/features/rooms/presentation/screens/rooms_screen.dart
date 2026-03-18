import 'package:flutter/material.dart';
import 'package:spark/shared/widgets/kyc_feature_gate.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import 'package:spark/core/constants/app_constants.dart';
import 'package:spark/core/services/auth_service.dart';
import 'package:spark/features/rooms/data/room_models.dart';
import 'package:spark/features/rooms/data/rooms_api_service.dart';
import 'package:spark/features/rooms/presentation/widgets/room_card.dart';

/// Meetup: event owners see "My events" + requests; others discover and request to join.
class RoomsScreen extends StatefulWidget {
  const RoomsScreen({super.key});

  @override
  State<RoomsScreen> createState() => _RoomsScreenState();
}

class _RoomsScreenState extends State<RoomsScreen> {
  final AuthService _auth = AuthService();
  final RoomsApiService _api = RoomsApiService();

  List<Room> _myRooms = [];
  List<Room> _discoverRooms = [];
  bool _loading = true;
  String? _error;

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
      final results = await Future.wait([
        _api.getRooms(mine: true),
        _api.getRooms(mine: false),
      ]);
      if (!mounted) return;
      setState(() {
        _myRooms = results[0];
        _discoverRooms = results[1];
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isLoggedIn = _auth.uid != null;

    return KycFeatureGate(
      child: Scaffold(
      appBar: AppBar(
        title: const Text('Meetup'),
        actions: [
          IconButton(
            icon: const Icon(Icons.map_outlined),
            onPressed: () {},
            tooltip: 'Map view',
          ),
          IconButton(
            icon: const Icon(Icons.add_circle_outline_rounded),
            onPressed: () => context.push(AppConstants.routeCreateRoom),
            tooltip: 'Create meetup',
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
                ? _buildError(theme)
                : CustomScrollView(
                    slivers: [
                      // My events (only for owners who have created events)
                      if (_myRooms.isNotEmpty) ...[
                        SliverToBoxAdapter(
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Icon(
                                      Icons.event_rounded,
                                      size: 22,
                                      color: theme.colorScheme.primary,
                                    ),
                                    const SizedBox(width: 8),
                                    Text(
                                      'My events',
                                      style: theme.textTheme.titleMedium?.copyWith(
                                        fontWeight: FontWeight.bold,
                                        color: theme.colorScheme.onSurface,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'Manage your events and review join requests',
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: theme.colorScheme.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        SliverPadding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          sliver: SliverList(
                            delegate: SliverChildBuilderDelegate(
                              (context, index) {
                                final room = _myRooms[index];
                                return Padding(
                                  padding: const EdgeInsets.only(bottom: 12),
                                  child: _OwnerRoomCard(
                                    room: room,
                                    onTap: () => context.push(
                                        AppConstants.routeRoomDetailWithId(room.id)),
                                  ),
                                )
                                    .animate()
                                    .fadeIn(delay: Duration(milliseconds: 40 * index))
                                    .slideY(begin: 0.03, end: 0, curve: Curves.easeOut);
                              },
                              childCount: _myRooms.length,
                            ),
                          ),
                        ),
                        const SliverToBoxAdapter(child: SizedBox(height: 8)),
                      ],
                      // Discover / Happening
                      SliverToBoxAdapter(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '🔥 Happening',
                                style: theme.textTheme.titleLarge?.copyWith(
                                  fontWeight: FontWeight.bold,
                                  color: theme.colorScheme.onSurface,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                isLoggedIn
                                    ? 'Join an experience or create your own'
                                    : 'Sign in to join or create meetups',
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      if (_discoverRooms.isEmpty && _myRooms.isEmpty)
                        SliverFillRemaining(
                          child: _buildEmpty(theme),
                        )
                      else if (_discoverRooms.isEmpty)
                        const SliverToBoxAdapter(
                          child: Padding(
                            padding: EdgeInsets.all(24),
                            child: Center(
                              child: Text('No other meetups right now. Create one!'),
                            ),
                          ),
                        )
                      else
                        SliverPadding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          sliver: SliverList(
                            delegate: SliverChildBuilderDelegate(
                              (context, index) {
                                final room = _discoverRooms[index];
                                return Padding(
                                  padding: const EdgeInsets.only(bottom: 16),
                                  child: RoomCard(
                                    room: room,
                                    onTap: () => context.push(
                                        AppConstants.routeRoomDetailWithId(room.id)),
                                  ),
                                )
                                    .animate()
                                    .fadeIn(
                                        delay: Duration(
                                            milliseconds: 50 * (_myRooms.length + index)))
                                    .slideY(begin: 0.05, end: 0, curve: Curves.easeOut);
                              },
                              childCount: _discoverRooms.length,
                            ),
                          ),
                        ),
                      const SliverToBoxAdapter(child: SizedBox(height: 24)),
                    ],
                  ),
      ),
      floatingActionButton: isLoggedIn
          ? FloatingActionButton.extended(
              onPressed: () => context.push(AppConstants.routeCreateRoom),
              icon: const Icon(Icons.add_rounded),
              label: const Text('Create meetup'),
            )
          : null,
    ),
    );
  }

  Widget _buildError(ThemeData theme) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.error_outline_rounded,
              size: 48,
              color: theme.colorScheme.error,
            ),
            const SizedBox(height: 16),
            Text(
              _error ?? 'Something went wrong',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _load,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmpty(ThemeData theme) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.event_available_rounded,
            size: 64,
            color: theme.colorScheme.outline,
          ),
          const SizedBox(height: 16),
          Text(
            'No meetups yet',
            style: theme.textTheme.titleMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 8),
          FilledButton.icon(
            onPressed: () => context.push(AppConstants.routeCreateRoom),
            icon: const Icon(Icons.add_rounded),
            label: const Text('Create a meetup'),
          ),
        ],
      ),
    );
  }
}

/// Compact card for owner's event with "View requests" cue.
class _OwnerRoomCard extends StatelessWidget {
  const _OwnerRoomCard({required this.room, required this.onTap});

  final Room room;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerLow,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: theme.colorScheme.primaryContainer.withValues(alpha: 0.6),
              width: 1,
            ),
            boxShadow: [
              BoxShadow(
                color: theme.colorScheme.shadow.withValues(alpha: 0.06),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: theme.colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Center(
                  child: Text(
                    room.activityEmoji,
                    style: const TextStyle(fontSize: 24),
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      room.title,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: theme.colorScheme.onSurface,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${room.placeName} · ${room.currentParticipants}/${room.maxParticipants}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.arrow_forward_ios_rounded,
                size: 14,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
