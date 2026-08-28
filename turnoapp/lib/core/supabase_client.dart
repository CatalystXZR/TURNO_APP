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

import 'package:supabase_flutter/supabase_flutter.dart';

/// Single access point for the Supabase client.
/// Call [SupabaseConfig.initialize] once in main() before runApp().
///
/// SUPABASE_URL and SUPABASE_ANON_KEY must be injected at compile time via
/// --dart-define=SUPABASE_URL=<url> --dart-define=SUPABASE_ANON_KEY=<key>
/// (e.g. from Codemagic environment variables or local run arguments).
class SupabaseConfig {
  SupabaseConfig._();

  static String get url => const String.fromEnvironment('SUPABASE_URL');

  static String get anonKey => const String.fromEnvironment('SUPABASE_ANON_KEY');

  static bool get isConfigured {
    return url.isNotEmpty &&
        anonKey.isNotEmpty &&
        !url.contains('YOUR_PROJECT') &&
        !anonKey.contains('YOUR_ANON_KEY');
  }

  static void ensureConfigured() {
    if (!isConfigured) {
      throw StateError(
        'supabase_not_configured: define SUPABASE_URL and SUPABASE_ANON_KEY with --dart-define',
      );
    }
  }

  static Future<void> initialize() async {
    ensureConfigured();
    await Supabase.initialize(
      url: url,
      anonKey: anonKey,
    );
  }

  static SupabaseClient? _testClient;

  static SupabaseClient get client {
    if (_testClient != null) return _testClient!;
    return Supabase.instance.client;
  }

  static void setClientForTest(SupabaseClient client) {
    _testClient = client;
  }

  static void clearTestClient() {
    _testClient = null;
  }
}
