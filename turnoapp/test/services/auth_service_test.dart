import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:turnoapp/services/auth_service.dart';
import 'package:turnoapp/core/supabase_client.dart';

import '../test_helpers/mock_supabase.dart';

void main() {
  late MockSupabaseClient client;
  late MockGoTrueClient auth;

  setUp(() {
    client = createMockSupabaseClient();
    auth = client.auth as MockGoTrueClient;
    registerFallbacks();
    SupabaseConfig.setClientForTest(client);
  });

  tearDown(() {
    SupabaseConfig.clearTestClient();
  });

  group('AuthService', () {
    test('isLoggedIn returns false when no session', () {
      when(() => auth.currentSession).thenReturn(null);
      expect(AuthService().isLoggedIn, false);
    });

    test('isLoggedIn returns true when session exists', () {
      when(() => auth.currentSession).thenReturn(MockAuthSession());
      expect(AuthService().isLoggedIn, true);
    });

    test('currentUserId returns null when no user', () {
      when(() => auth.currentUser).thenReturn(null);
      expect(AuthService().currentUserId, isNull);
    });

    test('currentUserId returns uid when user exists', () {
      final user = MockUser();
      when(() => user.id).thenReturn('u1');
      when(() => auth.currentUser).thenReturn(user);
      expect(AuthService().currentUserId, 'u1');
    });
  });
}
