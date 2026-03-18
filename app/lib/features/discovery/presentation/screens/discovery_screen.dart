import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:spark/shared/widgets/kyc_feature_gate.dart';
import 'package:flutter_animate/flutter_animate.dart';

/// One prompt + answer pair on a profile.
class DiscoveryPrompt {
  const DiscoveryPrompt({required this.prompt, required this.answer});
  final String prompt;
  final String answer;
}

/// Full profile for a discovery card: photos + interests + prompts.
class DiscoveryProfile {
  const DiscoveryProfile({
    required this.name,
    required this.age,
    required this.photos,
    this.interests = const [],
    required this.prompts,
  });
  final String name;
  final String age;
  final List<String> photos;
  final List<String> interests;
  final List<DiscoveryPrompt> prompts;
}

class DiscoveryScreen extends StatefulWidget {
  const DiscoveryScreen({super.key});

  @override
  State<DiscoveryScreen> createState() => _DiscoveryScreenState();
}

class _DiscoveryScreenState extends State<DiscoveryScreen> {
  final PageController _cardController = PageController(viewportFraction: 0.88);
  int _currentIndex = 0;

  static final List<DiscoveryProfile> _demoProfiles = [
    DiscoveryProfile(
      name: 'Alex',
      age: '26',
      photos: [
        'https://images.unsplash.com/photo-1507003211169-0a1dd7228f2d?w=800',
        'https://images.unsplash.com/photo-1500648767791-00dcc994a43e?w=800',
        'https://images.unsplash.com/photo-1519345182560-3f2917c472ef?w=800',
      ],
      interests: const ['Coffee', 'Hiking', 'Food', 'Travel'],
      prompts: const [
        DiscoveryPrompt(prompt: 'Together we could...', answer: 'Try every coffee shop in the city'),
        DiscoveryPrompt(prompt: 'I\'m looking for...', answer: 'Someone who loves hiking and good food'),
        DiscoveryPrompt(prompt: 'My simple pleasures', answer: 'Morning coffee and sunset walks'),
      ],
    ),
    DiscoveryProfile(
      name: 'Jordan',
      age: '24',
      photos: [
        'https://images.unsplash.com/photo-1494790108377-be9c29b29330?w=800',
        'https://images.unsplash.com/photo-1438761681033-6461ffad8d80?w=800',
        'https://images.unsplash.com/photo-1534528741775-53994a69daeb?w=800',
      ],
      interests: const ['Concerts', 'Road trips', 'Adventure'],
      prompts: const [
        DiscoveryPrompt(prompt: 'I\'m looking for...', answer: 'Someone who laughs at my jokes'),
        DiscoveryPrompt(prompt: 'The way to win me over', answer: 'Surprise me with a concert or a road trip'),
        DiscoveryPrompt(prompt: 'A life goal of mine', answer: 'Visit every continent'),
      ],
    ),
    DiscoveryProfile(
      name: 'Sam',
      age: '28',
      photos: [
        'https://images.unsplash.com/photo-1506794778202-cad84cf45f1d?w=800',
        'https://images.unsplash.com/photo-1507081323647-4d250478b919?w=800',
      ],
      interests: const ['Books', 'Rain', 'Reading nook'],
      prompts: const [
        DiscoveryPrompt(prompt: 'My simple pleasures', answer: 'Rainy days and good books'),
        DiscoveryPrompt(prompt: 'I\'ll fall for you if...', answer: 'You can keep up with my random facts'),
        DiscoveryPrompt(prompt: 'Together we could...', answer: 'Build a reading nook and never leave'),
      ],
    ),
  ];

  @override
  void dispose() {
    _cardController.dispose();
    super.dispose();
  }

  void _onDislike() {
    if (_currentIndex < _demoProfiles.length - 1) {
      _cardController.nextPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
      setState(() => _currentIndex++);
    }
  }

  void _onLike() {
    if (_currentIndex < _demoProfiles.length - 1) {
      _cardController.nextPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
      setState(() => _currentIndex++);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('You\'ve seen everyone for now. Check back later!'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  void _onSuperLike() {
    _onLike();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return KycFeatureGate(
      child: Scaffold(
      backgroundColor: cs.surface,
      appBar: AppBar(
        title: const Text('Discover'),
        actions: [
          IconButton(
            icon: const Icon(Icons.tune_rounded),
            onPressed: () {},
          ),
          IconButton(
            icon: const Icon(Icons.safety_check_outlined),
            onPressed: () {},
            tooltip: 'Safety',
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Today\'s suggestions',
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                Text(
                  '${_demoProfiles.length - _currentIndex} left',
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: theme.colorScheme.primary,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Expanded(
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                PageView.builder(
                  controller: _cardController,
                  onPageChanged: (i) => setState(() => _currentIndex = i),
                  itemCount: _demoProfiles.length,
                  itemBuilder: (context, index) {
                    final profile = _demoProfiles[index];
                    final isTop = index == _currentIndex;
                    return Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
                      child: _DiscoveryCard(
                        profile: profile,
                        isTop: isTop,
                      ),
                    );
                  },
                ),
                // Floating action buttons over the card
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: _FloatingActionBar(
                    onDislike: _onDislike,
                    onSuperLike: _onSuperLike,
                    onLike: _onLike,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    ),
    );
  }
}

class _DiscoveryCard extends StatelessWidget {
  const _DiscoveryCard({
    required this.profile,
    required this.isTop,
  });

  final DiscoveryProfile profile;
  final bool isTop;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final photos = profile.photos;
    final hasPhotos = photos.isNotEmpty;
    final otherPhotos = photos.length > 1 ? photos.sublist(1) : <String>[];

    return AnimatedScale(
      scale: isTop ? 1.0 : 0.92,
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOut,
      child: AnimatedOpacity(
        opacity: isTop ? 1.0 : 0.7,
        duration: const Duration(milliseconds: 250),
        child: Card(
          clipBehavior: Clip.antiAlias,
          elevation: 0,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  cs.surface,
                  cs.surfaceContainerLow.withValues(alpha: 0.6),
                ],
              ),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // 1. Main image
                    if (hasPhotos)
                      AspectRatio(
                        aspectRatio: 3 / 4,
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            CachedNetworkImage(
                              imageUrl: photos.first,
                              fit: BoxFit.cover,
                              placeholder: (_, __) => Container(
                                color: cs.surfaceContainerHigh,
                                child: Center(
                                  child: CircularProgressIndicator(color: cs.primary),
                                ),
                              ),
                              errorWidget: (_, __, ___) => _placeholderImage(context),
                            ),
                            if (isTop)
                              Positioned(
                                top: 12,
                                right: 12,
                                child: Icon(
                                  Icons.verified_rounded,
                                  color: cs.primary,
                                  size: 22,
                                ),
                              ),
                          ],
                        ),
                      )
                    else
                      AspectRatio(
                        aspectRatio: 3 / 4,
                        child: _placeholderImage(context),
                      ),
                    // 2. Info (name, age)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(14),
                          gradient: LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [
                              cs.surfaceContainerHighest.withValues(alpha: 0.9),
                              cs.surfaceContainerHigh.withValues(alpha: 0.9),
                            ],
                          ),
                        ),
                        child: Text(
                          '${profile.name}, ${profile.age}',
                          style: theme.textTheme.headlineSmall?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: cs.onSurface,
                          ),
                        ),
                      ).animate().fadeIn(duration: const Duration(milliseconds: 400)).slideY(begin: 0.1, end: 0, curve: Curves.easeOut),
                    ),
                    // 3. Interests
                    if (profile.interests.isNotEmpty) ...[
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                        child: Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: profile.interests.map((interest) {
                            return Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(20),
                                gradient: LinearGradient(
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                  colors: [
                                    cs.primaryContainer.withValues(alpha: 0.9),
                                    cs.tertiaryContainer.withValues(alpha: 0.6),
                                  ],
                                ),
                              ),
                              child: Text(
                                interest,
                                style: theme.textTheme.labelLarge?.copyWith(
                                  color: cs.onPrimaryContainer,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            );
                          }).toList(),
                        ),
                      ),
                      const SizedBox(height: 8),
                    ],
                    // 4. Other images (gallery)
                    if (otherPhotos.isNotEmpty) ...[
                      SizedBox(
                        height: 120,
                        child: ListView.separated(
                          scrollDirection: Axis.horizontal,
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          itemCount: otherPhotos.length,
                          separatorBuilder: (_, __) => const SizedBox(width: 10),
                          itemBuilder: (context, i) {
                            return ClipRRect(
                              borderRadius: BorderRadius.circular(12),
                              child: SizedBox(
                                width: 100,
                                child: CachedNetworkImage(
                                  imageUrl: otherPhotos[i],
                                  fit: BoxFit.cover,
                                  placeholder: (_, __) => Container(color: cs.surfaceContainerHigh),
                                  errorWidget: (_, __, ___) => Container(
                                    color: cs.surfaceContainerHigh,
                                    child: Icon(Icons.image_not_supported_rounded, color: cs.outline),
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                      const SizedBox(height: 12),
                    ],
                    // 5. Prompts (extra bottom padding so content clears floating bar)
                    if (profile.prompts.isNotEmpty) ...[
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 4, 16, 100),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            ...profile.prompts.map((p) => Padding(
                              padding: const EdgeInsets.only(bottom: 10),
                              child: _PromptChip(
                                prompt: p.prompt,
                                answer: p.answer,
                              ),
                            )),
                          ],
                        ),
                      ),
                    ] else
                      const SizedBox(height: 100),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _placeholderImage(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      color: cs.surfaceContainerHigh,
      child: Center(
        child: Icon(
          Icons.person_rounded,
          size: 72,
          color: cs.onSurfaceVariant.withValues(alpha: 0.4),
        ),
      ),
    );
  }
}

class _PromptChip extends StatelessWidget {
  const _PromptChip({required this.prompt, required this.answer});

  final String prompt;
  final String answer;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            cs.surfaceContainerHighest.withValues(alpha: 0.95),
            cs.surfaceContainerHigh.withValues(alpha: 0.9),
          ],
        ),
        border: Border.all(
          color: cs.outlineVariant.withValues(alpha: 0.4),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            prompt,
            style: theme.textTheme.labelMedium?.copyWith(
              color: cs.primary,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            answer,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: cs.onSurface,
            ),
          ),
        ],
      ),
    );
  }
}

/// Floating action bar over the card — cross, super like, like float on screen.
class _FloatingActionBar extends StatelessWidget {
  const _FloatingActionBar({
    required this.onDislike,
    required this.onSuperLike,
    required this.onLike,
  });

  final VoidCallback onDislike;
  final VoidCallback onSuperLike;
  final VoidCallback onLike;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(40),
          boxShadow: [
            BoxShadow(
              color: cs.shadow.withValues(alpha: 0.12),
              blurRadius: 20,
              offset: const Offset(0, 6),
            ),
            BoxShadow(
              color: cs.surface.withValues(alpha: 0.95),
              blurRadius: 1,
            ),
          ],
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              cs.surfaceContainerHigh.withValues(alpha: 0.98),
              cs.surface.withValues(alpha: 0.98),
            ],
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _CircleButton(
              icon: Icons.close_rounded,
              color: cs.errorContainer,
              iconColor: cs.onErrorContainer,
              onPressed: onDislike,
              useGradient: true,
              gradientColors: [
                cs.errorContainer,
                cs.errorContainer.withValues(alpha: 0.85),
              ],
            ),
            const SizedBox(width: 16),
            _CircleButton(
              icon: Icons.star_rounded,
              color: cs.tertiaryContainer,
              iconColor: cs.onTertiaryContainer,
              onPressed: onSuperLike,
              glowColor: cs.tertiary,
              useGradient: true,
              gradientColors: [
                cs.tertiaryContainer,
                cs.tertiary.withValues(alpha: 0.3),
              ],
            ),
            const SizedBox(width: 16),
            _CircleButton(
              icon: Icons.favorite_rounded,
              color: cs.secondaryContainer,
              iconColor: cs.secondary,
              onPressed: onLike,
              size: 52,
              iconSize: 26,
              glowColor: cs.primary,
              useGradient: true,
              gradientColors: [
                cs.secondaryContainer,
                cs.primary.withValues(alpha: 0.25),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _CircleButton extends StatelessWidget {
  const _CircleButton({
    required this.icon,
    required this.color,
    required this.iconColor,
    required this.onPressed,
    this.size = 46,
    this.iconSize = 24,
    this.glowColor,
    this.useGradient = false,
    this.gradientColors,
  });

  final IconData icon;
  final Color color;
  final Color iconColor;
  final VoidCallback onPressed;
  final double size;
  final double iconSize;
  final Color? glowColor;
  final bool useGradient;
  final List<Color>? gradientColors;

  @override
  Widget build(BuildContext context) {
    final shadowColor = glowColor ?? color;
    final decoration = BoxDecoration(
      shape: BoxShape.circle,
      gradient: useGradient && gradientColors != null && gradientColors!.length >= 2
          ? LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: gradientColors!,
            )
          : null,
      color: useGradient ? null : color,
      boxShadow: [
        BoxShadow(
          color: shadowColor.withValues(alpha: 0.35),
          blurRadius: size * 0.4,
          offset: const Offset(0, 4),
        ),
        BoxShadow(
          color: shadowColor.withValues(alpha: 0.15),
          blurRadius: size * 0.6,
          offset: const Offset(0, 8),
        ),
      ],
    );
    return Container(
      decoration: decoration,
      child: Material(
        color: useGradient ? Colors.transparent : color,
        shape: const CircleBorder(),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onPressed,
          customBorder: const CircleBorder(),
          child: SizedBox(
            width: size,
            height: size,
            child: Icon(icon, color: iconColor, size: iconSize),
          ),
        ),
      ),
    );
  }
}
