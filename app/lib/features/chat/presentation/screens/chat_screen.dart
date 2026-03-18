import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:spark/core/constants/app_constants.dart';

class ChatScreen extends StatelessWidget {
  const ChatScreen({
    super.key,
    required this.matchId,
    this.roomName,
    this.eventAt,
    this.returnPath,
  });

  final String matchId;
  /// When set, this chat is from a room — show room context banner.
  final String? roomName;
  final DateTime? eventAt;
  /// When set, back button goes to this path (e.g. /matches) so the shell shows the correct tab instead of defaulting to Nearby.
  final String? returnPath;

  void _onBack(BuildContext context) {
    if (returnPath != null && returnPath!.isNotEmpty) {
      context.go(returnPath!);
    } else {
      context.pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final showRoomBanner = roomName != null && roomName!.isNotEmpty;
    final useReturnPath = returnPath != null && returnPath!.isNotEmpty;

    return PopScope(
      canPop: !useReturnPath,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop && useReturnPath) _onBack(context);
      },
      child: Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => _onBack(context),
        ),
        title: Row(
          children: [
            CircleAvatar(
              radius: 16,
              backgroundColor: theme.colorScheme.primaryContainer,
              child: Text(
                'A',
                style: theme.textTheme.titleSmall?.copyWith(
                  color: theme.colorScheme.primary,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            const SizedBox(width: 10),
            const Text('Alex'),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.videocam_outlined),
            onPressed: () {},
          ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert_rounded),
            onSelected: (value) {
              if (value == 'report') _showReportSheet(context);
              if (value == 'block') _showBlockDialog(context);
            },
            itemBuilder: (context) => [
              const PopupMenuItem(value: 'report', child: Text('Report')),
              const PopupMenuItem(value: 'block', child: Text('Block')),
              const PopupMenuItem(value: 'unmatch', child: Text('Unmatch')),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          if (showRoomBanner) _RoomContextBanner(roomName: roomName!, eventAt: eventAt),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              children: [
                _ChatBubble(
                  text: 'Hey! Your opening move got me—coffee shop tour sounds perfect.',
                  isMe: false,
                  time: '10:30',
                ).animate().fadeIn().slideX(begin: -0.05, end: 0, curve: Curves.easeOut),
                const SizedBox(height: 8),
                _ChatBubble(
                  text: 'Right? When are you free this week?',
                  isMe: true,
                  time: '10:32',
                ).animate().fadeIn(delay: const Duration(milliseconds: 100)).slideX(begin: 0.05, end: 0, curve: Curves.easeOut),
                const SizedBox(height: 8),
                _ChatBubble(
                  text: 'Thursday evening works! There\'s a place downtown I\'ve been wanting to try.',
                  isMe: false,
                  time: '10:35',
                ).animate().fadeIn(delay: const Duration(milliseconds: 200)).slideX(begin: -0.05, end: 0, curve: Curves.easeOut),
              ],
            ),
          ),
          _ChatInput(
            onSend: (text) {},
            onReport: () => _showReportSheet(context),
          ),
        ],
      ),
    ),
    );
  }

  void _showReportSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
        builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Report',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
              ),
              const SizedBox(height: 6),
              Text(
                'Select a reason. We take safety seriously and review all reports.',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
              ),
              const SizedBox(height: 16),
              ...AppConstants.reportReasons.map((reason) => ListTile(
                    title: Text(reason),
                    onTap: () {
                      Navigator.pop(context);
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Thank you. We\'ll review this report.'),
                          behavior: SnackBarBehavior.floating,
                        ),
                      );
                    },
                  )),
            ],
          ),
        ),
      ),
    );
  }

  void _showBlockDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Block this person?'),
        content: const Text(
          'They won\'t be able to see your profile or message you. You can unblock later in Settings.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(context);
              context.pop();
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Blocked. Stay safe.'),
                  behavior: SnackBarBehavior.floating,
                ),
              );
            },
            child: const Text('Block'),
          ),
        ],
      ),
    );
  }
}

/// Banner showing room/event context when chat is from a room approval.
class _RoomContextBanner extends StatelessWidget {
  const _RoomContextBanner({required this.roomName, this.eventAt});

  final String roomName;
  final DateTime? eventAt;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final timeStr = eventAt != null
        ? DateFormat('EEEE · h:mm a').format(eventAt!)
        : null;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      color: theme.colorScheme.primaryContainer.withValues(alpha: 0.5),
      child: Row(
        children: [
          Icon(
            Icons.event_rounded,
            size: 18,
            color: theme.colorScheme.primary,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  roomName,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: theme.colorScheme.onSurface,
                  ),
                ),
                if (timeStr != null)
                  Text(
                    timeStr,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ChatBubble extends StatelessWidget {
  const _ChatBubble({
    required this.text,
    required this.isMe,
    required this.time,
  });

  final String text;
  final bool isMe;
  final String time;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * 0.78),
        child: Column(
          crossAxisAlignment: isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: isMe
                    ? theme.colorScheme.primaryContainer
                    : theme.colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(14),
                  topRight: const Radius.circular(14),
                  bottomLeft: Radius.circular(isMe ? 14 : 4),
                  bottomRight: Radius.circular(isMe ? 4 : 14),
                ),
              ),
              child: Text(
                text,
                style: theme.textTheme.bodyLarge?.copyWith(
                  color: isMe ? theme.colorScheme.onPrimaryContainer : theme.colorScheme.onSurface,
                ),
              ),
            ),
            const SizedBox(height: 3),
            Text(
              time,
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ChatInput extends StatelessWidget {
  const _ChatInput({required this.onSend, required this.onReport});

  final void Function(String text) onSend;
  final VoidCallback onReport;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: EdgeInsets.only(
        left: 12,
        right: 12,
        top: 8,
        bottom: 8 + MediaQuery.paddingOf(context).bottom,
      ),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        boxShadow: [
          BoxShadow(
            color: theme.colorScheme.shadow.withValues(alpha: 0.06),
            blurRadius: 8,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.add_circle_outline_rounded),
            onPressed: () {},
          ),
          Expanded(
            child: TextField(
              decoration: InputDecoration(
                hintText: 'Say something...',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(20),
                  borderSide: BorderSide.none,
                ),
                filled: true,
                fillColor: theme.colorScheme.surfaceContainerHighest,
                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              ),
              textInputAction: TextInputAction.send,
              onSubmitted: (v) {
                if (v.trim().isNotEmpty) onSend(v.trim());
              },
            ),
          ),
          const SizedBox(width: 8),
          IconButton(
            icon: Icon(Icons.favorite_border_rounded, color: theme.colorScheme.secondary),
            onPressed: () {},
          ),
          FilledButton(
            onPressed: () {},
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.all(10),
              minimumSize: const Size(40, 40),
              shape: const CircleBorder(),
            ),
            child: const Icon(Icons.send_rounded, size: 20),
          ),
        ],
      ),
    );
  }
}
