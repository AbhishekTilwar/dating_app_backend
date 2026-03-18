import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/services.dart';
import 'package:google_sign_in/google_sign_in.dart';

/// Web client ID from Firebase → `google-services.json` → `oauth_client` where `client_type` is **3**.
/// Required on Android so Google returns an **idToken** for Firebase Auth.
/// If you change Firebase project, update this to match the new Web client ID.
const String _kGoogleWebClientId =
    '370994482685-68sik6lhdiqbt1k0ipu4km7nttjl5ld1.apps.googleusercontent.com';

/// Handles Firebase Auth: sign in, sign up, sign out, auth state.
/// Supports email/password, Google Sign-In, and phone number (OTP).
class AuthService {
  AuthService()
      : _auth = FirebaseAuth.instance,
        _googleSignIn = GoogleSignIn(
          scopes: const ['email', 'profile'],
          serverClientId: _kGoogleWebClientId,
        );

  final FirebaseAuth _auth;
  final GoogleSignIn _googleSignIn;

  Stream<User?> get authStateChanges => _auth.authStateChanges();
  User? get currentUser => _auth.currentUser;
  String? get uid => currentUser?.uid;

  // ——— Google Sign-In ———
  Future<UserCredential> signInWithGoogle() async {
    GoogleSignInAccount? googleUser;
    try {
      googleUser = await _googleSignIn.signIn();
    } on PlatformException catch (e) {
      final code = e.code.toLowerCase();
      if (code.contains('canceled') ||
          code.contains('cancelled') ||
          code == 'sign_in_canceled' ||
          code == 'error_canceled') {
        throw FirebaseAuthException(
          code: 'google_sign_in_aborted',
          message: 'Google sign in was cancelled',
        );
      }
      final msg = '${e.message ?? ''} ${e.details ?? ''}'.toLowerCase();
      if (msg.contains('apiexception: 7') ||
          msg.contains('statuscode: 7') ||
          msg.contains(' 7,')) {
        throw FirebaseAuthException(
          code: 'google_network_error',
          message:
              'Google Sign-In network error (code 7). Try: stable Wi‑Fi/data, disable VPN, '
              'update Google Play Services & Play Store, correct device date/time. '
              'Also add your PC\'s debug SHA‑1 in Firebase → Project settings → Your Android app.',
        );
      }
      if (msg.contains('apiexception: 10') || msg.contains('developer_error')) {
        throw FirebaseAuthException(
          code: 'google_config_error',
          message:
              'Google Sign-In setup error. In Firebase Console add your debug SHA‑1 fingerprint '
              '(run: cd android && ./gradlew signingReport) and download a fresh google-services.json.',
        );
      }
      throw FirebaseAuthException(
        code: 'google_sign_in_failed',
        message: e.message ?? e.code,
      );
    }
    if (googleUser == null) {
      throw FirebaseAuthException(
        code: 'google_sign_in_aborted',
        message: 'Google sign in was cancelled',
      );
    }
    final googleAuth = await googleUser.authentication;
    if (googleAuth.idToken == null || googleAuth.idToken!.isEmpty) {
      throw FirebaseAuthException(
        code: 'google_no_id_token',
        message:
            'Google did not return an ID token. Ensure serverClientId matches the Web client in Firebase '
            'and your SHA‑1 is registered for package com.spark.spark.',
      );
    }
    final credential = GoogleAuthProvider.credential(
      accessToken: googleAuth.accessToken,
      idToken: googleAuth.idToken,
    );
    return _auth.signInWithCredential(credential);
  }

  // ——— Phone (OTP) ———
  /// Starts phone verification. When SMS is sent, [onCodeSent] is called with
  /// [verificationId]. Use [signInWithPhoneCredential] with that id and the user-entered code.
  void verifyPhoneNumber({
    required String phoneNumber,
    int? forceResendingToken,
    required void Function(String verificationId, int? resendToken) onCodeSent,
    void Function(FirebaseAuthException e)? onVerificationFailed,
    void Function(PhoneAuthCredential credential)? onVerificationCompleted,
    void Function(String verificationId)? onCodeAutoRetrievalTimeout,
    Duration timeout = const Duration(seconds: 120),
  }) {
    _auth.verifyPhoneNumber(
      phoneNumber: phoneNumber,
      forceResendingToken: forceResendingToken,
      verificationCompleted: (PhoneAuthCredential credential) {
        onVerificationCompleted?.call(credential);
      },
      verificationFailed: (FirebaseAuthException e) {
        onVerificationFailed?.call(e);
      },
      codeSent: (String verificationId, int? resendToken) {
        onCodeSent(verificationId, resendToken);
      },
      codeAutoRetrievalTimeout: (String verificationId) {
        onCodeAutoRetrievalTimeout?.call(verificationId);
      },
      timeout: timeout,
    );
  }

  /// Signs in with the OTP code after [verifyPhoneNumber]'s [onCodeSent] was called.
  Future<UserCredential> signInWithPhoneCredential({
    required String verificationId,
    required String smsCode,
  }) async {
    final credential = PhoneAuthProvider.credential(
      verificationId: verificationId,
      smsCode: smsCode,
    );
    return _auth.signInWithCredential(credential);
  }

  /// Android instant verification / auto-retrieval — Firebase supplies a full credential.
  Future<UserCredential> signInWithPhoneAuthCredential(
    PhoneAuthCredential credential,
  ) =>
      _auth.signInWithCredential(credential);

  // ——— Email / password ———
  Future<UserCredential?> signInWithEmailPassword({
    required String email,
    required String password,
  }) async {
    return _auth.signInWithEmailAndPassword(email: email, password: password);
  }

  Future<UserCredential?> signUpWithEmailPassword({
    required String email,
    required String password,
    String? displayName,
  }) async {
    final cred = await _auth.createUserWithEmailAndPassword(
      email: email,
      password: password,
    );
    if (displayName != null && cred.user != null) {
      await cred.user!.updateDisplayName(displayName);
    }
    return cred;
  }

  Future<void> signOut() async {
    await _googleSignIn.signOut();
    await _auth.signOut();
  }

  Future<void> sendPasswordResetEmail(String email) =>
      _auth.sendPasswordResetEmail(email: email);
}
