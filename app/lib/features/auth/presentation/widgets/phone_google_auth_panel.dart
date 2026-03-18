import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import 'package:spark/core/constants/app_constants.dart';
import 'package:spark/core/services/auth_service.dart';
import 'package:spark/core/services/backend_health_service.dart';
import 'package:spark/core/services/user_profile_service.dart';

const Color _kAccentPink = Color(0xFFE91E63);
const Color _kTextBlack = Color(0xFF212121);
const Color _kTextGray = Color(0xFF757575);
const Color _kBorderGray = Color(0xFFE0E0E0);

const String _kDefaultCountryCode = '+91';

/// Shared sign-in / sign-up: mobile OTP + Google only (Firebase).
/// Backend APIs use the same Firebase ID token after auth.
class PhoneGoogleAuthPanel extends StatefulWidget {
  const PhoneGoogleAuthPanel({
    super.key,
    required this.headline,
    this.subhead,
    this.showBackendStatus = true,
  });

  final String headline;
  final String? subhead;
  final bool showBackendStatus;

  @override
  State<PhoneGoogleAuthPanel> createState() => _PhoneGoogleAuthPanelState();
}

class _PhoneGoogleAuthPanelState extends State<PhoneGoogleAuthPanel> {
  final _phoneController = TextEditingController();
  final _auth = AuthService();

  String? _verificationId;
  int? _resendToken;
  bool _otpDialogOpen = false;
  bool _isSendingOtp = false;
  bool _isSigningInWithGoogle = false;
  String? _errorMessage;
  bool? _backendOk;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (FirebaseAuth.instance.currentUser == null) {
        if (widget.showBackendStatus) {
          final ok = await BackendHealthService.ping();
          if (mounted) setState(() => _backendOk = ok);
        }
        return;
      }
      if (!mounted) return;
      await UserProfileService.navigateAfterSignIn((loc) {
        if (mounted) context.go(loc);
      });
    });
  }

  @override
  void dispose() {
    _phoneController.dispose();
    super.dispose();
  }

  void _clearError() {
    if (_errorMessage != null) setState(() => _errorMessage = null);
  }

  Future<void> _continueWithPhone(BuildContext context, {int? forceResendToken}) async {
    _clearError();
    final digits = _phoneController.text.trim().replaceAll(RegExp(r'\D'), '');
    if (digits.length < 10) {
      setState(() => _errorMessage = 'Enter a valid 10-digit mobile number');
      return;
    }
    final phoneNumber = '$_kDefaultCountryCode$digits';
    setState(() => _isSendingOtp = true);

    void fail(String message) {
      if (!mounted) return;
      setState(() {
        _isSendingOtp = false;
        _errorMessage = message;
      });
    }

    _auth.verifyPhoneNumber(
      phoneNumber: phoneNumber,
      forceResendingToken: forceResendToken,
      onVerificationCompleted: (PhoneAuthCredential credential) async {
        // Android instant verification / auto SMS — must sign in explicitly.
        if (!mounted) return;
        setState(() => _isSendingOtp = false);
        try {
          await _auth.signInWithPhoneAuthCredential(credential);
          if (!context.mounted) return;
          if (_otpDialogOpen) {
            Navigator.of(context, rootNavigator: true).pop();
            _otpDialogOpen = false;
          }
          await UserProfileService.navigateAfterSignIn((loc) {
            if (context.mounted) context.go(loc);
          });
        } on FirebaseAuthException catch (e) {
          fail(e.message ?? 'Phone sign-in failed');
        } catch (e) {
          fail(e.toString());
        }
      },
      onCodeSent: (verificationId, resendToken) async {
        if (!mounted) return;
        setState(() {
          _verificationId = verificationId;
          _resendToken = resendToken;
          _isSendingOtp = false;
        });
        if (FirebaseAuth.instance.currentUser != null) {
          await UserProfileService.navigateAfterSignIn((loc) {
            if (context.mounted) context.go(loc);
          });
          return;
        }
        if (!context.mounted) return;
        _showOtpDialog(context, phoneNumber);
      },
      onVerificationFailed: (e) {
        if (!mounted) return;
        setState(() {
          _isSendingOtp = false;
          _errorMessage = e.message ?? e.code;
        });
      },
      onCodeAutoRetrievalTimeout: (verificationId) {
        if (!mounted) return;
        setState(() {
          _verificationId = verificationId;
          _isSendingOtp = false;
        });
        if (FirebaseAuth.instance.currentUser != null) return;
        if (!_otpDialogOpen) {
          _showOtpDialog(context, phoneNumber);
        }
      },
    );
  }

  void _showOtpDialog(BuildContext context, String phoneNumber) {
    final verificationId = _verificationId;
    if (verificationId == null) return;
    if (_otpDialogOpen) return;
    _otpDialogOpen = true;
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => _OtpDialog(
        phoneNumber: phoneNumber,
        verificationId: verificationId,
        auth: _auth,
        onResendOtp: _resendToken != null
            ? () {
                Navigator.of(dialogContext).pop();
                _otpDialogOpen = false;
                if (mounted) {
                  _continueWithPhone(context, forceResendToken: _resendToken);
                }
              }
            : null,
        onSuccess: () async {
          Navigator.of(dialogContext).pop();
          _otpDialogOpen = false;
          if (!context.mounted) return;
          await UserProfileService.navigateAfterSignIn((loc) {
            if (context.mounted) context.go(loc);
          });
        },
        onError: (message) {
          if (mounted) setState(() => _errorMessage = message);
        },
      ),
    ).then((_) {
      if (mounted) _otpDialogOpen = false;
    });
  }

  Future<void> _signInWithGoogle(BuildContext context) async {
    _clearError();
    setState(() => _isSigningInWithGoogle = true);
    try {
      await _auth.signInWithGoogle();
      if (!mounted) return;
      await UserProfileService.navigateAfterSignIn((loc) => context.go(loc));
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = e.message ?? 'Google sign in failed';
        if (e.code == 'google_sign_in_aborted') _errorMessage = null;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _errorMessage = 'Google sign in failed. Check Play Services & Firebase SHA-1.');
    } finally {
      if (mounted) setState(() => _isSigningInWithGoogle = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 16),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.favorite_rounded, size: 40, color: _kAccentPink)
                      .animate()
                      .fadeIn()
                      .scale(begin: const Offset(0.8, 0.8), curve: Curves.easeOut),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: 220,
                    child: Text(
                      widget.headline,
                      style: const TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.bold,
                        color: _kTextBlack,
                        height: 1.2,
                      ),
                    ),
                  )
                      .animate()
                      .fadeIn(delay: 80.ms)
                      .slideX(begin: -0.05, end: 0, curve: Curves.easeOut),
                  if (widget.subhead != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      widget.subhead!,
                      style: const TextStyle(fontSize: 14, color: _kTextGray, height: 1.35),
                    ),
                  ],
                ],
              ),
              const Spacer(),
              _CoupleIllustration()
                  .animate()
                  .fadeIn(delay: 150.ms)
                  .slideX(begin: 0.05, end: 0, curve: Curves.easeOut),
            ],
          ),
          const SizedBox(height: 36),
          const Text(
            'Mobile number',
            style: TextStyle(fontSize: 14, color: _kTextGray, fontWeight: FontWeight.w500),
          ),
          const SizedBox(height: 10),
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: _kBorderGray),
            ),
            child: Row(
              children: [
                const Padding(
                  padding: EdgeInsets.only(left: 16),
                  child: Text(
                    '+91',
                    style: TextStyle(fontSize: 16, color: _kTextBlack, fontWeight: FontWeight.w500),
                  ),
                ),
                Expanded(
                  child: TextField(
                    controller: _phoneController,
                    keyboardType: TextInputType.phone,
                    decoration: const InputDecoration(
                      hintText: '10-digit number',
                      border: InputBorder.none,
                      contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 16),
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (_errorMessage != null) ...[
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(_errorMessage!, style: const TextStyle(color: Colors.red, fontSize: 13)),
            ),
          ],
          const SizedBox(height: 12),
          SizedBox(
            height: 52,
            child: FilledButton(
              onPressed: _isSendingOtp ? null : () => _continueWithPhone(context),
              style: FilledButton.styleFrom(
                backgroundColor: _kAccentPink,
                foregroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: _isSendingOtp
                  ? const SizedBox(
                      height: 24,
                      width: 24,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : const Text('Continue with mobile'),
            ),
          ),
          const SizedBox(height: 28),
          Row(
            children: [
              Expanded(child: Divider(color: _kBorderGray)),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 16),
                child: Text('Or', style: TextStyle(fontSize: 14, color: _kTextGray, fontWeight: FontWeight.w500)),
              ),
              Expanded(child: Divider(color: _kBorderGray)),
            ],
          ),
          const SizedBox(height: 20),
          SizedBox(
            height: 52,
            child: OutlinedButton.icon(
              onPressed: _isSigningInWithGoogle ? null : () => _signInWithGoogle(context),
              icon: _isSigningInWithGoogle
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.g_mobiledata_rounded, size: 28),
              label: Text(_isSigningInWithGoogle ? 'Signing in…' : 'Continue with Google'),
              style: OutlinedButton.styleFrom(
                foregroundColor: _kTextBlack,
                side: const BorderSide(color: _kBorderGray),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ),
          if (widget.showBackendStatus && _backendOk != null) ...[
            const SizedBox(height: 20),
            _BackendStatusChip(ok: _backendOk!),
          ],
          const SizedBox(height: 24),
          Text(
            'Auth is handled by Firebase. Your backend (${AppConstants.apiBaseUrl}) accepts the same account for discovery, chat, and meetups.',
            style: const TextStyle(fontSize: 11, color: _kTextGray, height: 1.35),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          const Text(
            'By continuing, you accept our Terms & Privacy policy.',
            style: TextStyle(fontSize: 12, color: _kTextGray, height: 1.4),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

class _BackendStatusChip extends StatelessWidget {
  const _BackendStatusChip({required this.ok});

  final bool ok;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(ok ? Icons.cloud_done_outlined : Icons.cloud_off_outlined, size: 18, color: ok ? Colors.green : Colors.orange),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            ok
                ? 'API server reachable'
                : 'Can\'t reach API yet — if URL is correct, wait ~1 min (host may be waking) or check ${AppConstants.apiBaseUrl}',
            style: TextStyle(fontSize: 12, color: ok ? Colors.green.shade800 : Colors.orange.shade900),
            textAlign: TextAlign.center,
          ),
        ),
      ],
    );
  }
}

class _OtpDialog extends StatefulWidget {
  const _OtpDialog({
    required this.phoneNumber,
    required this.verificationId,
    required this.auth,
    required this.onSuccess,
    required this.onError,
    this.onResendOtp,
  });

  final String phoneNumber;
  final String verificationId;
  final AuthService auth;
  final VoidCallback onSuccess;
  final void Function(String message) onError;
  final VoidCallback? onResendOtp;

  @override
  State<_OtpDialog> createState() => _OtpDialogState();
}

class _OtpDialogState extends State<_OtpDialog> {
  final _otpController = TextEditingController();
  bool _isVerifying = false;
  String? _dialogError;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (FirebaseAuth.instance.currentUser != null) {
        widget.onSuccess();
      }
    });
  }

  @override
  void dispose() {
    _otpController.dispose();
    super.dispose();
  }

  Future<void> _verify() async {
    final code = _otpController.text.trim();
    if (code.length != 6) {
      setState(() => _dialogError = 'Enter 6-digit code');
      return;
    }
    setState(() {
      _dialogError = null;
      _isVerifying = true;
    });
    try {
      await widget.auth.signInWithPhoneCredential(
        verificationId: widget.verificationId,
        smsCode: code,
      );
      if (!mounted) return;
      widget.onSuccess();
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;
      setState(() => _dialogError = e.message ?? e.code);
      widget.onError(_dialogError!);
    } catch (e) {
      if (!mounted) return;
      setState(() => _dialogError = 'Something went wrong. Try again.');
      widget.onError(_dialogError!);
    } finally {
      if (mounted) setState(() => _isVerifying = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Enter OTP'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Code sent to ${widget.phoneNumber}',
            style: const TextStyle(fontSize: 14, color: _kTextGray),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _otpController,
            keyboardType: TextInputType.number,
            maxLength: 6,
            decoration: InputDecoration(
              hintText: '000000',
              counterText: '',
              border: const OutlineInputBorder(),
              errorText: _dialogError,
            ),
          ),
        ],
      ),
      actions: [
        if (widget.onResendOtp != null)
          TextButton(
            onPressed: _isVerifying ? null : widget.onResendOtp,
            child: const Text('Resend code'),
          ),
        TextButton(
          onPressed: _isVerifying ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _isVerifying ? null : _verify,
          style: FilledButton.styleFrom(backgroundColor: _kAccentPink),
          child: _isVerifying
              ? const SizedBox(
                  height: 20,
                  width: 20,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                )
              : const Text('Verify'),
        ),
      ],
    );
  }
}

class _CoupleIllustration extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 100,
      height: 100,
      child: Stack(
        alignment: Alignment.center,
        children: [
          ...List.generate(3, (i) {
            final size = 24.0 + i * 12.0;
            final offset = Offset((i - 1) * 8.0, (i - 1) * 6.0);
            return Positioned(
              left: 50 + offset.dx - size / 2,
              top: 50 + offset.dy - size / 2,
              child: Icon(Icons.favorite_border_rounded, size: size, color: _kAccentPink.withValues(alpha: 0.2)),
            );
          }),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _PersonShape(color: const Color(0xFFE67E22)),
              const SizedBox(width: 4),
              _PersonShape(color: const Color(0xFF5D4037)),
            ],
          ),
        ],
      ),
    );
  }
}

class _PersonShape extends StatelessWidget {
  const _PersonShape({required this.color});
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 22,
          height: 22,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(height: 2),
        Container(
          width: 28,
          height: 36,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.9),
            borderRadius: const BorderRadius.vertical(bottom: Radius.circular(4)),
          ),
        ),
      ],
    );
  }
}
