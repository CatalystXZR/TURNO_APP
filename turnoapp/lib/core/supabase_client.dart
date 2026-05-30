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

/// Single access point for the Supabase client.
/// Call [SupabaseConfig.initialize] once in main() before runApp().
class SupabaseConfig {
  SupabaseConfig._();

  // Defaults for local development.
  // Can be overridden with --dart-define=SUPABASE_URL / SUPABASE_ANON_KEY.
  static const String _defaultUrl = 'https://zawaevytpkvejhekyokw.supabase.co';
  static const String _defaultAnonKey =
      'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Inphd2Fldnl0cGt2ZWpoZWt5b2t3Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzMzNzAwMjEsImV4cCI6MjA4ODk0NjAyMX0.W08CHoJ_jKSHzBvQnw-HUfjTBSdNVGBs6N89h_QPaOM';

  static String get url => const String.fromEnvironment(
        'SUPABASE_URL',
        defaultValue: _defaultUrl,
      );

  static String get anonKey => const String.fromEnvironment(
        'SUPABASE_ANON_KEY',
        defaultValue: _defaultAnonKey,
      );

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
