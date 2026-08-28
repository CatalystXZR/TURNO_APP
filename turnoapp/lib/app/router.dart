/**
 * Project: Turno
 * 
 * Project Owners: Cristobal Cordova, Carlos Ibarra, Agustin Puelma
 * Software Architecture & Code: Matias Toledo (@catalystxzr)
 * 
 * Description: Production-grade implementation for UDD carpooling system.
 * 
 * Copyright (c) 2026 Turno. All rights reserved.
 * This software is proprietary and confidential.
 */

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../core/supabase_client.dart';
import '../features/auth/login_screen.dart';
import '../features/auth/register_screen.dart';
import '../features/profile_switch/home_screen.dart';
import '../features/rides_publish/publish_ride_screen.dart';
import '../features/rides_search/search_rides_screen.dart';
import '../features/booking/booking_screen.dart';
import '../features/wallet/wallet_screen.dart';
import '../features/my_rides/my_rides_screen.dart';
import '../features/my_rides/driver_rides_screen.dart';
import '../features/my_rides/active_trip_screen.dart';
import '../features/my_rides/arrival_screen.dart';
import '../features/my_rides/driver_active_ride_screen.dart';
import '../features/legal/terms_screen.dart';
import '../features/legal/privacy_policy_screen.dart';
import '../features/legal/support_screen.dart';
import '../features/favorites/favorites_screen.dart';
import '../features/notifications/notifications_screen.dart';
import '../features/profile/edit_profile_screen.dart';

final GoRouter appRouter = GoRouter(
  initialLocation: '/home',
  redirect: (BuildContext context, GoRouterState state) {
    final session = SupabaseConfig.client.auth.currentSession;
    final isAuth = session != null;
    const publicRoutes = {
      '/login',
      '/register',
      '/terms',
      '/privacy',
      '/support',
    };
    final isPublicRoute = publicRoutes.contains(state.matchedLocation);
    final isOnAuth = state.matchedLocation == '/login' ||
        state.matchedLocation == '/register';

    if (!isAuth && !isPublicRoute) return '/login';
    if (isAuth && isOnAuth) return '/home';
    return null;
  },
  refreshListenable: GoRouterRefreshStream(
    SupabaseConfig.client.auth.onAuthStateChange,
  ),
  routes: [
    GoRoute(path: '/login', builder: (_, __) => const LoginScreen()),
    GoRoute(path: '/register', builder: (_, __) => const RegisterScreen()),
    GoRoute(path: '/home', builder: (_, __) => const HomeScreen()),
    GoRoute(
      path: '/publish',
      builder: (_, __) => const PublishRideScreen(),
    ),
    GoRoute(
      path: '/search',
      builder: (_, __) => const SearchRidesScreen(),
    ),
    GoRoute(
      path: '/booking/:rideId',
      builder: (_, state) =>
          BookingScreen(rideId: state.pathParameters['rideId']!),
    ),
    GoRoute(path: '/wallet', builder: (_, __) => const WalletScreen()),
    GoRoute(path: '/my-rides', builder: (_, __) => const MyRidesScreen()),
    GoRoute(
        path: '/arrival',
        builder: (_, state) =>
            ArrivalScreen(bookingId: state.uri.queryParameters['bookingId']),
    ),
    GoRoute(
      path: '/active-trip/:bookingId',
      builder: (_, state) =>
          ActiveTripScreen(bookingId: state.pathParameters['bookingId']!),
    ),
    GoRoute(
      path: '/driver-ride/:rideId',
      builder: (_, state) =>
          DriverActiveRideScreen(rideId: state.pathParameters['rideId']!),
    ),
    GoRoute(
        path: '/driver-rides', builder: (_, __) => const DriverRidesScreen()),
    GoRoute(path: '/terms', builder: (_, __) => const TermsScreen()),
    GoRoute(path: '/privacy', builder: (_, __) => const PrivacyPolicyScreen()),
    GoRoute(path: '/support', builder: (_, __) => const SupportScreen()),
    GoRoute(path: '/favorites', builder: (_, __) => const FavoritesScreen()),
    GoRoute(
        path: '/profile/edit', builder: (_, __) => const EditProfileScreen()),
    GoRoute(
        path: '/notifications',
        builder: (_, __) => const NotificationsScreen()),
  ],
);

/// Converts a Supabase auth stream to a [Listenable] for GoRouter.
/// Properly cancels the subscription on dispose to prevent memory leaks.
class GoRouterRefreshStream extends ChangeNotifier {
  GoRouterRefreshStream(Stream<AuthState> stream) {
    _sub = stream.listen((_) => notifyListeners());
  }

  late final StreamSubscription<AuthState> _sub;

  @override
  void dispose() {
    _sub.cancel();
    super.dispose();
  }
}
