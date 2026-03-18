import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:spark/features/auth/presentation/widgets/phone_google_auth_panel.dart';
import 'package:spark/shared/widgets/crossed_logo.dart';

/// Sign up: same as sign in — mobile OTP or Google only. Firebase creates the user on first use.
class RegisterScreen extends StatelessWidget {
  const RegisterScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => context.pop(),
        ),
        title: const CrossedLogo(size: 32),
        centerTitle: true,
      ),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: PhoneGoogleAuthPanel(
                headline: 'Create your account',
                subhead: 'No password needed. Sign up with mobile or Google — same as signing in.',
                showBackendStatus: false,
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    'Already have an account? ',
                    style: TextStyle(fontSize: 14, color: Colors.grey.shade700),
                  ),
                  TextButton(
                    onPressed: () {
                      if (context.canPop()) {
                        context.pop();
                      } else {
                        context.go('/auth');
                      }
                    },
                    child: const Text('Sign in'),
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
