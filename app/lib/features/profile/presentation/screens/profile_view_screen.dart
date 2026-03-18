import 'package:cached_network_image/cached_network_image.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import 'package:spark/core/models/user_profile.dart';
import 'package:spark/core/services/auth_service.dart';
import 'package:spark/core/services/user_profile_service.dart';
import 'package:spark/shared/widgets/parallax_section.dart';

/// Own profile from Firestore — updates live when data or photos change.
class ProfileViewScreen extends StatefulWidget {
  const ProfileViewScreen({super.key});

  @override
  State<ProfileViewScreen> createState() => _ProfileViewScreenState();
}

class _ProfileViewScreenState extends State<ProfileViewScreen> {
  final ScrollController _scrollController = ScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final uid = FirebaseAuth.instance.currentUser?.uid;

    if (uid == null) {
      return const Scaffold(body: Center(child: Text('Sign in to view profile')));
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Profile'),
        actions: [
          IconButton(
            icon: const Icon(Icons.edit_outlined),
            onPressed: () => context.push('/profile-setup'),
            tooltip: 'Edit profile',
          ),
        ],
      ),
      body: StreamBuilder<UserProfile?>(
        stream: UserProfileService().profileStream(uid),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting && !snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final profile = snapshot.data;
          if (profile == null) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('No profile yet'),
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed: () => context.go('/profile-setup'),
                    child: const Text('Create profile'),
                  ),
                ],
              ),
            );
          }

          final name = profile.displayName?.trim().isNotEmpty == true
              ? profile.displayName!
              : 'Your profile';
          final photos = profile.photos;

          return CustomScrollView(
            controller: _scrollController,
            slivers: [
              SliverToBoxAdapter(
                child: ParallaxSection(
                  scrollController: _scrollController,
                  parallaxOffset: 0.2,
                  fadeStart: 0.2,
                  fadeEnd: 0.6,
                  child: Column(
                    children: [
                      const SizedBox(height: 16),
                      if (photos.isNotEmpty)
                        SizedBox(
                          height: 200,
                          child: PageView.builder(
                            itemCount: photos.length,
                            itemBuilder: (_, i) => Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 24),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(20),
                                child: CachedNetworkImage(
                                  imageUrl: photos[i],
                                  width: double.infinity,
                                  fit: BoxFit.cover,
                                  placeholder: (_, __) => Container(
                                    color: theme.colorScheme.surfaceContainerHighest,
                                    child: const Center(child: CircularProgressIndicator()),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        )
                      else
                        CircleAvatar(
                          radius: 56,
                          backgroundColor: theme.colorScheme.primaryContainer,
                          child: Text(
                            name.isNotEmpty ? name[0].toUpperCase() : '?',
                            style: theme.textTheme.headlineLarge?.copyWith(
                              color: theme.colorScheme.primary,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      if (photos.length > 1)
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Text(
                            '${photos.length} photos · swipe',
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                      const SizedBox(height: 16),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            name,
                            style: theme.textTheme.headlineSmall?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          if (profile.profileComplete) ...[
                            const SizedBox(width: 8),
                            Icon(Icons.verified_rounded, color: theme.colorScheme.primary, size: 26),
                          ],
                        ],
                      )
                          .animate()
                          .fadeIn()
                          .scale(begin: const Offset(0.95, 0.95)),
                      if (profile.relationshipGoal != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(
                            profile.relationshipGoal!,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: theme.colorScheme.primary,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      if (profile.openingMove != null) ...[
                        const SizedBox(height: 12),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 24),
                          child: Material(
                            color: theme.colorScheme.surfaceContainerHighest,
                            borderRadius: BorderRadius.circular(16),
                            child: Padding(
                              padding: const EdgeInsets.all(14),
                              child: Row(
                                children: [
                                  Icon(Icons.chat_bubble_outline_rounded,
                                      color: theme.colorScheme.primary, size: 22),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Text(
                                      profile.openingMove!,
                                      style: theme.textTheme.bodyMedium,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                      if (profile.bio != null && profile.bio!.trim().isNotEmpty) ...[
                        const SizedBox(height: 12),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 24),
                          child: Text(
                            profile.bio!.trim(),
                            textAlign: TextAlign.center,
                            style: theme.textTheme.bodyLarge,
                          ),
                        ),
                      ],
                      if (!profile.profileComplete)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
                          child: Card(
                            color: theme.colorScheme.primaryContainer.withValues(alpha: 0.35),
                            child: ListTile(
                              leading: Icon(Icons.info_outline_rounded,
                                  color: theme.colorScheme.primary),
                              title: const Text('Finish setup so others can discover you.'),
                              trailing: FilledButton.tonal(
                                onPressed: () => context.go('/profile-setup'),
                                child: const Text('Continue'),
                              ),
                            ),
                          ),
                        ),
                      const SizedBox(height: 16),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 24),
                        child: OutlinedButton.icon(
                          onPressed: () => context.push('/profile-setup'),
                          icon: const Icon(Icons.edit_outlined, size: 20),
                          label: const Text('Edit profile'),
                          style: OutlinedButton.styleFrom(
                            minimumSize: const Size(double.infinity, 48),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                          ),
                        ),
                      ),
                      if (profile.updatedAt != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Text(
                            'Updated live · ${_fmt(profile.updatedAt!)}',
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: theme.colorScheme.outline,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(24, 24, 24, 12),
                  child: Text(
                    'Your prompts',
                    style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                  ),
                ),
              ),
              if (profile.prompts.isEmpty)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: OutlinedButton(
                      onPressed: () => context.push('/profile-setup'),
                      child: const Text('Add prompts'),
                    ),
                  ),
                )
              else
                SliverPadding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  sliver: SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (context, i) {
                        final p = profile.prompts[i];
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: _PromptChip(prompt: p.question, answer: p.answer)
                              .animate()
                              .fadeIn(delay: Duration(milliseconds: 50 * i)),
                        );
                      },
                      childCount: profile.prompts.length,
                    ),
                  ),
                ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(24, 28, 24, 12),
                  child: Text(
                    'Safety & support',
                    style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                  ),
                ),
              ),
              SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                sliver: SliverList(
                  delegate: SliverChildListDelegate([
                    ListTile(
                      leading: Icon(Icons.safety_check_outlined, color: theme.colorScheme.primary),
                      title: const Text('Safety tips'),
                      trailing: const Icon(Icons.chevron_right_rounded),
                      onTap: () {},
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    ),
                    ListTile(
                      leading: Icon(Icons.block_rounded, color: theme.colorScheme.error),
                      title: const Text('Blocked accounts'),
                      trailing: const Icon(Icons.chevron_right_rounded),
                      onTap: () {},
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    ),
                    ListTile(
                      leading: Icon(Icons.logout_rounded, color: theme.colorScheme.error),
                      title: Text('Log out',
                          style: TextStyle(color: theme.colorScheme.error, fontWeight: FontWeight.w600)),
                      trailing: const Icon(Icons.chevron_right_rounded),
                      onTap: () async {
                        await AuthService().signOut();
                        if (context.mounted) context.go('/auth');
                      },
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    ),
                  ]),
                ),
              ),
              const SliverToBoxAdapter(child: SizedBox(height: 32)),
            ],
          );
        },
      ),
    );
  }

  static String _fmt(DateTime d) {
    final now = DateTime.now();
    if (now.difference(d).inMinutes < 1) return 'just now';
    if (now.difference(d).inHours < 24) {
      return '${now.difference(d).inHours}h ago';
    }
    return '${d.day}/${d.month}/${d.year}';
  }
}

class _PromptChip extends StatelessWidget {
  const _PromptChip({required this.prompt, required this.answer});

  final String prompt;
  final String answer;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            prompt,
            style: theme.textTheme.labelMedium?.copyWith(
              color: theme.colorScheme.primary,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 6),
          Text(answer, style: theme.textTheme.bodyLarge),
        ],
      ),
    );
  }
}
