import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:spark/core/services/user_profile_service.dart';

/// Blocks main app features until [UserProfile.kycVerified] is true.
/// Profile tab stays usable for settings / re-verify.
class KycFeatureGate extends StatelessWidget {
  const KycFeatureGate({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return child;

    return StreamBuilder(
      stream: UserProfileService().profileStream(uid),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting && !snapshot.hasData) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        final p = snapshot.data;
        if (p?.kycVerified == true) {
          return child;
        }
        return Stack(
          fit: StackFit.expand,
          children: [
            IgnorePointer(
              ignoring: true,
              child: Opacity(opacity: 0.25, child: child),
            ),
            ColoredBox(
              color: Colors.black.withValues(alpha: 0.45),
              child: SafeArea(
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Material(
                      elevation: 8,
                      borderRadius: BorderRadius.circular(20),
                      child: Padding(
                        padding: const EdgeInsets.all(28),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.verified_user_outlined,
                              size: 56,
                              color: Theme.of(context).colorScheme.primary,
                            ),
                            const SizedBox(height: 16),
                            Text(
                              'Verify to unlock',
                              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                                    fontWeight: FontWeight.bold,
                                  ),
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 12),
                            Text(
                              'Complete a quick camera selfie so we can match it to your profile. '
                              'Discovery, chats, nearby, and rooms stay locked until then.',
                              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                                  ),
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 24),
                            FilledButton.icon(
                              onPressed: () => context.push('/kyc'),
                              icon: const Icon(Icons.camera_alt_rounded),
                              label: const Text('Verify identity'),
                              style: FilledButton.styleFrom(
                                minimumSize: const Size(double.infinity, 48),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}
