import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:spark/features/auth/presentation/widgets/phone_google_auth_panel.dart';

/// Sign in: mobile OTP or Google only (Firebase). Same flow as [RegisterScreen].
class LoginScreen extends StatelessWidget {
  const LoginScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: PhoneGoogleAuthPanel(
                headline: 'Sign in to Crossed',
                subhead: 'Use your mobile number or Google — new accounts are created automatically.',
                showBackendStatus: true,
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    'New here? ',
                    style: TextStyle(fontSize: 14, color: Colors.grey.shade700),
                  ),
                  TextButton(
                    onPressed: () => context.push('/register'),
                    child: const Text('Create account'),
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
