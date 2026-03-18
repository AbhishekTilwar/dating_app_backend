import 'dart:ui';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import 'package:spark/core/constants/app_constants.dart';
import 'package:spark/core/services/user_profile_service.dart';

/// When not logged in: welcome + Get Started → auth.
/// When logged in (after signup): gender selection → save onboardingDone + gender → profile-setup.
class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  static const Color _accentPink = Color(0xFFE91E63);
  static const Color _accentPinkLight = Color(0xFFF8BBD9);
  static const Color _bgPink = Color(0xFFFFF5F7);
  static const Color _textGray = Color(0xFF757575);
  static const Color _textBlack = Color(0xFF212121);

  static const String _centerImage =
      'https://images.unsplash.com/photo-1507003211169-0a1dd7228f2d?w=400';
  static const List<String> _aroundImages = [
    'https://images.unsplash.com/photo-1494790108377-be9c29b29330?w=400',
    'https://images.unsplash.com/photo-1500648767791-00dcc994a43e?w=400',
    'https://images.unsplash.com/photo-1438761681033-6461ffad8d80?w=400',
  ];

  String? _selectedGender;
  bool _saving = false;

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      return _buildPostSignupOnboarding(context);
    }
    return _buildWelcome(context);
  }

  /// Logged-in: collect gender and continue to profile-setup
  Widget _buildPostSignupOnboarding(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: _bgPink,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 16),
              Text(
                'Tell us about you',
                style: theme.textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: _textBlack,
                ),
              )
                  .animate()
                  .fadeIn()
                  .slideY(begin: 0.05, end: 0),
              const SizedBox(height: 8),
              Text(
                'We use this to verify your profile later. You can\'t change it without re-verifying.',
                style: theme.textTheme.bodyMedium?.copyWith(color: _textGray),
              )
                  .animate()
                  .fadeIn(delay: 80.ms)
                  .slideY(begin: 0.05, end: 0),
              const SizedBox(height: 32),
              ...AppConstants.onboardingGenders.map((gender) {
                final selected = _selectedGender == gender;
                return Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: ListTile(
                    title: Text(gender),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    tileColor: selected
                        ? _accentPinkLight.withValues(alpha: 0.6)
                        : theme.colorScheme.surfaceContainerHighest,
                    selected: selected,
                    onTap: () => setState(() => _selectedGender = gender),
                    leading: Icon(
                      selected ? Icons.check_circle : Icons.person_outline_rounded,
                      color: selected ? _accentPink : _textGray,
                    ),
                  )
                      .animate()
                      .fadeIn()
                      .slideX(begin: 0.02, end: 0),
                );
              }),
              const SizedBox(height: 40),
              FilledButton(
                onPressed: _saving || _selectedGender == null
                    ? null
                    : () => _completeOnboarding(context),
                style: FilledButton.styleFrom(
                  backgroundColor: _accentPink,
                  foregroundColor: Colors.white,
                  minimumSize: const Size(double.infinity, 52),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                child: _saving
                    ? const SizedBox(
                        height: 24,
                        width: 24,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : const Text('Continue'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _completeOnboarding(BuildContext context) async {
    final user = FirebaseAuth.instance.currentUser;
    final gender = _selectedGender;
    if (user == null || gender == null) return;
    setState(() => _saving = true);
    try {
      await UserProfileService().mergeProfileFields(
        uid: user.uid,
        gender: gender,
        onboardingDone: true,
      );
      if (!context.mounted) return;
      context.go('/profile-setup');
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not save: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Widget _buildWelcome(BuildContext context) {
    return Scaffold(
      backgroundColor: _bgPink,
      body: Stack(
        children: [
          ...List.generate(6, (i) {
            final left = 20.0 + (i * 55) % 280.0;
            final top = 80.0 + (i * 73) % 320.0;
            final size = 40.0 + (i % 3) * 20.0;
            return Positioned(
              left: left,
              top: top,
              child: IgnorePointer(
                child: _BlurredHeart(size: size, color: _accentPink),
              ),
            );
          }),
          SafeArea(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(
                        onPressed: () => GoRouter.of(context).go('/auth'),
                        child: Text(
                          'Skip',
                          style: TextStyle(
                            color: _textGray,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const SizedBox(height: 20),
                        SizedBox(
                          height: 220,
                          child: Stack(
                            alignment: Alignment.center,
                            children: [
                              CustomPaint(
                                size: const Size(220, 220),
                                painter: _ProfileConnectorPainter(
                                  color: _accentPinkLight.withValues(alpha: 0.6),
                                ),
                              ),
                              ..._dotPositions().map((offset) => Positioned(
                                    left: 110 + offset.dx - 4,
                                    top: 110 + offset.dy - 4,
                                    child: Container(
                                      width: 8,
                                      height: 8,
                                      decoration: const BoxDecoration(
                                        color: _accentPinkLight,
                                        shape: BoxShape.circle,
                                      ),
                                    ),
                                  )),
                              ..._aroundPositions().asMap().entries.map((e) {
                                final i = e.key;
                                final offset = e.value;
                                return Positioned(
                                  left: 110 + offset.dx - 32,
                                  top: 110 + offset.dy - 32,
                                  child: _ProfileCircle(
                                    imageUrl: _aroundImages[i],
                                    size: 64,
                                  ),
                                );
                              }),
                              const Positioned(
                                left: 110 - 56,
                                top: 110 - 56,
                                child: _ProfileCircle(
                                  imageUrl: _centerImage,
                                  size: 112,
                                ),
                              ),
                            ],
                          ),
                        )
                            .animate()
                            .fadeIn(duration: 400.ms)
                            .scale(begin: const Offset(0.9, 0.9), curve: Curves.easeOut),
                        const SizedBox(height: 40),
                        Text(
                          "Let's get closer 👋",
                          style: TextStyle(
                            fontSize: 15,
                            color: _textGray,
                            fontWeight: FontWeight.w500,
                          ),
                        )
                            .animate()
                            .fadeIn(delay: 100.ms, duration: 400.ms)
                            .slideY(begin: 0.1, end: 0, curve: Curves.easeOut),
                        const SizedBox(height: 8),
                        Text(
                          'The best place to meet your future partner.',
                          style: TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                            color: _textBlack,
                            height: 1.25,
                          ),
                          textAlign: TextAlign.center,
                        )
                            .animate()
                            .fadeIn(delay: 200.ms, duration: 400.ms)
                            .slideY(begin: 0.1, end: 0, curve: Curves.easeOut),
                      ],
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 0, 24, 32),
                  child: SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: FilledButton(
                      onPressed: () => GoRouter.of(context).go('/auth'),
                      style: FilledButton.styleFrom(
                        backgroundColor: _accentPink,
                        foregroundColor: Colors.white,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      child: const Text('Get Started'),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static List<Offset> _aroundPositions() {
    const r = 75.0;
    return [
      const Offset(0, -r),
      Offset(r * 0.866, r * 0.5),
      Offset(-r * 0.866, r * 0.5),
    ];
  }

  static List<Offset> _dotPositions() {
    const r = 95.0;
    return [
      const Offset(-0.5 * r, -0.6 * r),
      Offset(0.65 * r, -0.35 * r),
      Offset(0.5 * r, 0.7 * r),
      Offset(-0.7 * r, 0.4 * r),
      Offset(-0.4 * r, 0.5 * r),
    ];
  }
}

class _BlurredHeart extends StatelessWidget {
  const _BlurredHeart({required this.size, required this.color});

  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return ClipRect(
      child: ImageFiltered(
        imageFilter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
        child: Icon(
          Icons.favorite_rounded,
          size: size,
          color: color.withValues(alpha: 0.35),
        ),
      ),
    );
  }
}

class _ProfileConnectorPainter extends CustomPainter {
  _ProfileConnectorPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    canvas.drawCircle(center, 95, paint);
    canvas.drawCircle(center, 72, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _ProfileCircle extends StatelessWidget {
  const _ProfileCircle({required this.imageUrl, required this.size});

  final String imageUrl;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ClipOval(
        child: CachedNetworkImage(
          imageUrl: imageUrl,
          fit: BoxFit.cover,
          placeholder: (_, __) => Container(
            color: Colors.grey.shade200,
            child: const Icon(Icons.person, color: Colors.grey),
          ),
          errorWidget: (_, __, ___) => Container(
            color: Colors.grey.shade200,
            child: const Icon(Icons.person, color: Colors.grey),
          ),
        ),
      ),
    );
  }
}
