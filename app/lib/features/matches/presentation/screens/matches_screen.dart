import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import 'package:spark/core/constants/app_constants.dart';

class MatchesScreen extends StatelessWidget {
  const MatchesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // Mock matches — replace with API. roomName shown as tag when present.
    // ui-avatars.com returns image directly (no redirect) for reliable loading
    const matches = [
      (id: '1', name: 'Alex', lastMessage: 'That coffee place was great!', time: '2m', unread: true, roomName: 'Coffee at Bandra', avatarUrl: 'https://ui-avatars.com/api/?name=Alex&size=128&background=0D8ABC&color=fff'),
      (id: '2', name: 'Jordan', lastMessage: 'Sure, tomorrow works', time: '1h', unread: false, roomName: null, avatarUrl: 'https://ui-avatars.com/api/?name=Jordan&size=128&background=1abc9c&color=fff'),
      (id: '3', name: 'Sam', lastMessage: 'I\'m convinced that...', time: 'Yesterday', unread: false, roomName: 'Lonavala Hike', avatarUrl: 'https://ui-avatars.com/api/?name=Sam&size=128&background=e74c3c&color=fff'),
    ];

    return Scaffold(
      appBar: AppBar(
        title: const Text('Matches'),
        actions: [
          IconButton(
            icon: const Icon(Icons.search_rounded),
            onPressed: () {},
          ),
        ],
      ),
      body: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
              child: Text(
                'Your conversations',
                style: theme.textTheme.titleMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ),
          SliverList(
            delegate: SliverChildBuilderDelegate(
              (context, index) {
                final m = matches[index];
                return _MatchTile(
                  name: m.name,
                  lastMessage: m.lastMessage,
                  time: m.time,
                  unread: m.unread,
                  roomName: m.roomName,
                  avatarUrl: m.avatarUrl,
                  onTap: () => context.push(
                  '/chat/${m.id}',
                  extra: <String, dynamic>{
                    if (m.roomName != null) 'roomName': m.roomName,
                    if (m.roomName != null) 'eventAt': null,
                    'returnPath': AppConstants.routeMatches,
                  },
                ),
                )
                    .animate()
                    .fadeIn(delay: Duration(milliseconds: 80 * index))
                    .slideX(begin: 0.03, end: 0, curve: Curves.easeOut);
              },
              childCount: matches.length,
            ),
          ),
        ],
      ),
    );
  }
}

class _MatchTile extends StatelessWidget {
  const _MatchTile({
    required this.name,
    required this.lastMessage,
    required this.time,
    required this.unread,
    this.roomName,
    this.avatarUrl,
    required this.onTap,
  });

  final String name;
  final String lastMessage;
  final String time;
  final bool unread;
  final String? roomName;
  final String? avatarUrl;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListTile(
      onTap: onTap,
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      leading: CircleAvatar(
        radius: 28,
        backgroundColor: theme.colorScheme.primaryContainer,
        backgroundImage: avatarUrl != null && avatarUrl!.isNotEmpty
            ? NetworkImage(avatarUrl!)
            : null,
        child: avatarUrl == null || avatarUrl!.isEmpty
            ? Text(
                name.isNotEmpty ? name[0].toUpperCase() : '?',
                style: theme.textTheme.titleLarge?.copyWith(
                  color: theme.colorScheme.primary,
                  fontWeight: FontWeight.bold,
                ),
              )
            : null,
      ),
      title: Row(
        children: [
          Expanded(
            child: Text(
              name,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: unread ? FontWeight.bold : FontWeight.w600,
              ),
            ),
          ),
          if (roomName != null && roomName!.isNotEmpty) ...[
            const SizedBox(width: 8),
            Flexible(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: theme.colorScheme.tertiaryContainer.withValues(alpha: 0.8),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  roomName!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onTertiaryContainer,
                    fontWeight: FontWeight.w500,
                  ),
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
          fontWeight: unread ? FontWeight.w600 : FontWeight.normal,
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
          if (unread)
            const SizedBox(height: 4),
          if (unread)
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: theme.colorScheme.primary,
                shape: BoxShape.circle,
              ),
            ),
        ],
      ),
    );
  }
}
