import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:spark/core/router/go_router_refresh.dart';
import 'package:spark/features/auth/presentation/screens/login_screen.dart';
import 'package:spark/features/auth/presentation/screens/register_screen.dart';
import 'package:spark/features/chat/presentation/screens/chat_screen.dart';
import 'package:spark/features/chat/presentation/screens/chatting_screen.dart';
import 'package:spark/features/discovery/presentation/screens/discovery_screen.dart';
import 'package:spark/features/discovery/presentation/screens/nearby_screen.dart';
import 'package:spark/features/home/presentation/screens/home_shell_screen.dart';
import 'package:spark/features/onboarding/presentation/screens/onboarding_screen.dart';
import 'package:spark/features/kyc/presentation/screens/kyc_screen.dart';
import 'package:spark/features/profile/presentation/screens/profile_setup_screen.dart';
import 'package:spark/features/profile/presentation/screens/profile_view_screen.dart';
import 'package:spark/features/rooms/presentation/screens/create_room_screen.dart';
import 'package:spark/features/rooms/presentation/screens/room_detail_screen.dart';
import 'package:spark/features/rooms/presentation/screens/rooms_screen.dart';
import 'package:spark/features/splash/splash_screen.dart';

class AppRouter {
  static final _rootNavigatorKey = GlobalKey<NavigatorState>();

  static GoRouter createRouter() {
    final authRefresh = GoRouterRefreshStream(FirebaseAuth.instance.authStateChanges());
    return GoRouter(
      navigatorKey: _rootNavigatorKey,
      initialLocation: '/',
      debugLogDiagnostics: true,
      refreshListenable: authRefresh,
      redirect: (context, state) {
        final path = state.uri.path;
        if (path == '/' || path == '/onboarding' || path == '/auth' || path == '/register') {
          return null;
        }
        final user = FirebaseAuth.instance.currentUser;
        final needsAuth = path.startsWith('/home') ||
            path.startsWith('/chats') ||
            path.startsWith('/nearby') ||
            path.startsWith('/profile') ||
            path.startsWith('/profile-setup') ||
            path.startsWith('/kyc') ||
            path.startsWith('/chat/') ||
            path.startsWith('/rooms');
        if (needsAuth && user == null) return '/auth';
        return null;
      },
      routes: [
        GoRoute(
          path: '/',
          builder: (context, state) => const SplashScreen(),
        ),
        GoRoute(
          path: '/onboarding',
          builder: (context, state) => const OnboardingScreen(),
        ),
        GoRoute(
          path: '/auth',
          builder: (context, state) => const LoginScreen(),
        ),
        GoRoute(
          path: '/register',
          builder: (context, state) => const RegisterScreen(),
        ),
        GoRoute(
          path: '/profile-setup',
          builder: (context, state) => const ProfileSetupScreen(),
        ),
        GoRoute(
          path: '/kyc',
          builder: (context, state) => const KycScreen(),
        ),
        StatefulShellRoute.indexedStack(
          builder: (context, state, navigationShell) => HomeShellScreen(navigationShell: navigationShell),
          branches: [
            StatefulShellBranch(
              routes: [
                GoRoute(
                  path: '/home',
                  builder: (context, state) => const DiscoveryScreen(),
                ),
              ],
            ),
            StatefulShellBranch(
              routes: [
                GoRoute(
                  path: '/chats',
                  builder: (context, state) => const ChattingScreen(),
                ),
              ],
            ),
            StatefulShellBranch(
              routes: [
                GoRoute(
                  path: '/nearby',
                  builder: (context, state) => const NearbyScreen(),
                ),
              ],
            ),
            StatefulShellBranch(
              routes: [
                GoRoute(
                  path: '/rooms',
                  builder: (context, state) => const RoomsScreen(),
                  routes: [
                    GoRoute(
                      path: 'create',
                      builder: (context, state) => const CreateRoomScreen(),
                    ),
                    GoRoute(
                      path: ':roomId',
                      builder: (context, state) {
                        final roomId = state.pathParameters['roomId']!;
                        return RoomDetailScreen(roomId: roomId);
                      },
                    ),
                  ],
                ),
              ],
            ),
            StatefulShellBranch(
              routes: [
                GoRoute(
                  path: '/profile',
                  builder: (context, state) => const ProfileViewScreen(),
                ),
              ],
            ),
          ],
        ),
        GoRoute(
          path: '/chat/:matchId',
          builder: (context, state) {
            final matchId = state.pathParameters['matchId']!;
            final extra = state.extra is Map<String, dynamic> ? state.extra as Map<String, dynamic> : null;
            return ChatScreen(
              matchId: matchId,
              roomName: extra?['roomName'] as String?,
              eventAt: extra?['eventAt'] != null
                  ? DateTime.tryParse(extra!['eventAt'].toString())
                  : null,
              returnPath: extra?['returnPath'] as String?,
            );
          },
        ),
      ],
    );
  }
}
