/**
 *
 * Project: Turno
 *
 * Original Concept: Agustín Puelma, Cristobal Cordova, Carlos Ibarra
 *
 * Software Architecture & Code: Matías Toledo (catalystxzr)
 *
 * Description: Production-grade implementation for UDD carpooling system.
 *
 * Copyright (c) 2026. All rights reserved.
 *
 */

import 'package:supabase_flutter/supabase_flutter.dart';
import '../core/supabase_client.dart';
import 'booking_notification_service.dart';

class AuthService {
  final _client = SupabaseConfig.client;

  Session? get currentSession => _client.auth.currentSession;
  User? get currentUser => _client.auth.currentUser;
  String? get currentUserId => currentUser?.id;
  bool get isLoggedIn => currentSession != null;

  Stream<AuthState> get authStateChanges => _client.auth.onAuthStateChange;

  /// Sign up with email + password. Creates auth.users entry;
  /// a DB trigger should insert into users_profile automatically.
  Future<AuthResponse> signUp({
    required String email,
    required String password,
    required String fullName,
    required bool acceptedTerms,
    required String termsVersion,
    bool hasValidLicense = false,
    String roleMode = 'passenger',
    String? vehicleBrand,
    String? vehicleModel,
    String? vehicleVersion,
    int? vehicleDoors,
    String? vehiclePlate,
  }) async {
    return _client.auth.signUp(
      email: email,
      password: password,
      data: {
        'full_name': fullName,
        'accepted_terms': acceptedTerms,
        'terms_version': termsVersion,
        'has_valid_license': hasValidLicense,
        'role_mode': roleMode,
        if (vehicleBrand != null) 'vehicle_brand': vehicleBrand,
        if (vehicleModel != null) 'vehicle_model': vehicleModel,
        if (vehicleVersion != null) 'vehicle_version': vehicleVersion,
        if (vehicleDoors != null) 'vehicle_doors': vehicleDoors,
        if (vehiclePlate != null)
          'vehicle_plate': vehiclePlate.toUpperCase().replaceAll(' ', ''),
      },
    );
  }

  Future<AuthResponse> signIn({
    required String email,
    required String password,
  }) async {
    return _client.auth.signInWithPassword(
      email: email,
      password: password,
    );
  }

  Future<void> signOut() async {
    BookingNotificationService.instance.clearSnapshots();
    await _client.auth.signOut();
  }

  Future<void> deleteMyAccount({String? reason}) async {
    final response = await _client.functions.invoke(
      'delete-account',
      body: {
        if (reason != null && reason.trim().isNotEmpty) 'reason': reason.trim(),
      },
    );

    final data = response.data;
    if (data is Map<String, dynamic> && data['success'] == true) {
      await _client.auth.signOut();
      return;
    }

    throw Exception('No pudimos eliminar tu cuenta en este momento.');
  }
}
