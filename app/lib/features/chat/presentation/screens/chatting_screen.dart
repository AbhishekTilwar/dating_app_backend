import 'package:flutter/material.dart';
import 'package:spark/shared/widgets/kyc_feature_gate.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';

/// Chatting tab: Matches (conversations not yet started) + Chat list.
class ChattingScreen extends StatelessWidget {
  const ChattingScreen({super.key});

  /// Matches with no conversation started yet — tap to open chat and say hi.
  static const _matchesNoConversation = [
    (id: 'm1', name: 'Bryan', avatarUrl: 'https://ui-avatars.com/api/?name=Bryan&size=128&background=6366f1&color=fff'),
    (id: 'm2', name: 'Cassie', avatarUrl: 'https://ui-avatars.com/api/?name=Cassie&size=128&background=ec4899&color=fff'),
    (id: 'm3', name: 'Lucas', avatarUrl: 'https://ui-avatars.com/api/?name=Lucas&size=128&background=14b8a6&color=fff'),
  ];

  // roomName/eventAt: when set, chat is from a Meetup — show tag and pass to ChatScreen
  static final _chats = [
    (id: '1', name: 'Sophia Williams', lastMessage: 'That sounds perfect!', time: '11:43 am', unread: 1, avatarUrl: 'https://ui-avatars.com/api/?name=Sophia+Williams&size=128&background=E11D48&color=fff', roomName: 'Coffee at Bandra', eventAt: DateTime.now().add(const Duration(days: 1))),
    (id: '2', name: 'Mia Kennedy', lastMessage: 'See you then 😊', time: '09:21 am', unread: 0, avatarUrl: 'https://ui-avatars.com/api/?name=Mia+Kennedy&size=128&background=0D8ABC&color=fff', roomName: null, eventAt: null),
    (id: '3', name: 'Olivia Thompson', lastMessage: 'Thanks for the recommendation!', time: 'Yesterday', unread: 1, avatarUrl: 'https://ui-avatars.com/api/?name=Olivia+Thompson&size=128&background=1abc9c&color=fff', roomName: 'Lonavala Sunrise Hike', eventAt: null),
    (id: '4', name: 'Emma Robinson', lastMessage: 'Hey, how are you?', time: '2 Days Ago', unread: 3, avatarUrl: 'https://ui-avatars.com/api/?name=Emma+Robinson&size=128&background=e74c3c&color=fff', roomName: null, eventAt: null),
    (id: '5', name: 'Sophia Bennett', lastMessage: 'Sure, let\'s do it', time: '2 Days Ago', unread: 0, avatarUrl: 'https://ui-avatars.com/api/?name=Sophia+Bennett&size=128&background=7C3AED&color=fff', roomName: 'Dinner Meetup – Colaba', eventAt: null),
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return KycFeatureGate(
      child: Scaffold(
      backgroundColor: theme.colorScheme.surface,
      appBar: AppBar(
        backgroundColor: theme.colorScheme.surface,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: true,
        title: const Text('Chatting'),
        actions: [
          IconButton(
            icon: Icon(Icons.search_rounded, color: theme.colorScheme.onSurface),
            onPressed: () {},
          ),
          IconButton(
            icon: Icon(Icons.more_vert_rounded, color: theme.colorScheme.onSurface),
            onPressed: () {},
          ),
        ],
      ),
      body: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
              child: Text(
                'Matches',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: theme.colorScheme.onSurface,
                ),
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 4),
              child: Text(
                'Conversations not yet started',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: SizedBox(
              height: 100,
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                scrollDirection: Axis.horizontal,
                children: [
                  ..._matchesNoConversation.map((m) => Padding(
                    padding: const EdgeInsets.only(right: 16),
                    child: _MatchCircle(
                      matchId: m.id,
                      name: m.name,
                      avatarUrl: m.avatarUrl,
                      theme: theme,
                      onTap: () => context.push(
                        '/chat/${m.id}',
                        extra: {'returnPath': '/chats'},
                      ),
                    ),
                  )),
                ],
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 24, 20, 12),
              child: Text(
                'Chat',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: theme.colorScheme.onSurface,
                ),
              ),
            ),
          ),
          SliverList(
            delegate: SliverChildBuilderDelegate(
              (context, index) {
                final c = _chats[index];
                return _ChatTile(
                  name: c.name,
                  lastMessage: c.lastMessage,
                  time: c.time,
                  unreadCount: c.unread,
                  avatarUrl: c.avatarUrl,
                  roomName: c.roomName,
                  eventAt: c.eventAt,
                  onTap: () => context.push(
                    '/chat/${c.id}',
                    extra: {
                      if (c.roomName != null) 'roomName': c.roomName,
                      if (c.eventAt != null) 'eventAt': c.eventAt?.toIso8601String(),
                      'returnPath': '/chats',
                    },
                  ),
                ).animate().fadeIn(delay: Duration(milliseconds: 50 * index)).slideX(begin: 0.02, end: 0, curve: Curves.easeOut);
              },
              childCount: _chats.length,
            ),
          ),
        ],
      ),
    ),
    );
  }
}

class _MatchCircle extends StatelessWidget {
  const _MatchCircle({
    required this.matchId,
    required this.name,
    required this.avatarUrl,
    required this.theme,
    required this.onTap,
  });

  final String matchId;
  final String name;
  final String avatarUrl;
  final ThemeData theme;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(40),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          CircleAvatar(
            radius: 32,
            backgroundColor: theme.colorScheme.outlineVariant,
            backgroundImage: NetworkImage(avatarUrl),
            child: null,
          ),
          const SizedBox(height: 6),
          Text(
            name,
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurface,
              fontWeight: FontWeight.w500,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}

class _ChatTile extends StatelessWidget {
  const _ChatTile({
    required this.name,
    required this.lastMessage,
    required this.time,
    required this.unreadCount,
    required this.avatarUrl,
    this.roomName,
    this.eventAt,
    required this.onTap,
  });

  final String name;
  final String lastMessage;
  final String time;
  final int unreadCount;
  final String avatarUrl;
  final String? roomName;
  final DateTime? eventAt;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasRoomTag = roomName != null && roomName!.isNotEmpty;

    return ListTile(
      onTap: onTap,
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      leading: CircleAvatar(
        radius: 28,
        backgroundColor: theme.colorScheme.primaryContainer,
        backgroundImage: NetworkImage(avatarUrl),
        child: null,
      ),
      title: Row(
        children: [
          Expanded(
            child: Text(
              name,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: unreadCount > 0 ? FontWeight.bold : FontWeight.w600,
                color: theme.colorScheme.onSurface,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (hasRoomTag) ...[
            const SizedBox(width: 8),
            Flexible(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: theme.colorScheme.tertiaryContainer.withValues(alpha: 0.9),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: theme.colorScheme.tertiary.withValues(alpha: 0.5),
                    width: 1,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.event_rounded,
                      size: 14,
                      color: theme.colorScheme.onTertiaryContainer,
                    ),
                    const SizedBox(width: 4),
                    Flexible(
                      child: Text(
                        roomName!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: theme.colorScheme.onTertiaryContainer,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
      subtitle: Text(
        lastMessage,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: theme.textTheme.bodyMedium?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
          fontWeight: unreadCount > 0 ? FontWeight.w600 : FontWeight.normal,
        ),
      ),
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(
            time,
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          if (unreadCount > 0) ...[
            const SizedBox(height: 4),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: theme.colorScheme.primary,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                '$unreadCount',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onPrimary,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
