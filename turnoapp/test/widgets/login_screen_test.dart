import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:turnoapp/features/auth/login_screen.dart';
import 'package:turnoapp/core/supabase_client.dart';
import 'package:turnoapp/app/theme.dart';

import '../test_helpers/mock_supabase.dart';

void main() {
  late MockSupabaseClient client;
  late MockGoTrueClient auth;

  setUp(() {
    client = createMockSupabaseClient();
    auth = client.auth as MockGoTrueClient;
    registerFallbacks();
    stubAuthUser(auth, uid: 'u1');
    SupabaseConfig.setClientForTest(client);
  });

  tearDown(() {
    SupabaseConfig.clearTestClient();
  });

  Widget wrapWithProviders(Widget child) {
    return ProviderScope(
      child: MaterialApp(
        theme: AppTheme.light,
        home: child,
      ),
    );
  }

  group('LoginScreen', () {
    testWidgets('shows login form with email and password fields',
        (WidgetTester tester) async {
      await tester.pumpWidget(wrapWithProviders(const LoginScreen()));
      await tester.pumpAndSettle();

      expect(find.text('Turno'), findsOneWidget);
      expect(find.text('Inicia sesion'), findsOneWidget);
      expect(find.text('Correo'), findsOneWidget);
      expect(find.text('Contrasena'), findsOneWidget);
      expect(find.text('Ingresar'), findsOneWidget);
    });

    testWidgets('shows validation error for invalid email',
        (WidgetTester tester) async {
      await tester.pumpWidget(wrapWithProviders(const LoginScreen()));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextFormField).at(0), 'not-an-email');
      await tester.enterText(find.byType(TextFormField).at(1), '123456');
      await tester.tap(find.text('Ingresar'));
      await tester.pumpAndSettle();

      expect(find.text('Correo invalido'), findsOneWidget);
    });

    testWidgets('shows validation error for short password',
        (WidgetTester tester) async {
      await tester.pumpWidget(wrapWithProviders(const LoginScreen()));
      await tester.pumpAndSettle();

      await tester.enterText(
          find.byType(TextFormField).at(0), 'test@test.com');
      await tester.enterText(find.byType(TextFormField).at(1), '123');
      await tester.tap(find.text('Ingresar'));
      await tester.pumpAndSettle();

      expect(find.text('Minimo 6 caracteres'), findsOneWidget);
    });

    testWidgets('has navigation links', (WidgetTester tester) async {
      await tester.pumpWidget(wrapWithProviders(const LoginScreen()));
      await tester.pumpAndSettle();

      expect(find.text('Terminos y condiciones'), findsOneWidget);
      expect(find.text('Privacidad'), findsOneWidget);
      expect(find.text('Soporte'), findsOneWidget);
      expect(find.text('No tienes cuenta? Registrate'), findsOneWidget);
    });

    testWidgets('toggle password visibility', (WidgetTester tester) async {
      await tester.pumpWidget(wrapWithProviders(const LoginScreen()));
      await tester.pumpAndSettle();

      final visibilityButton = find.byIcon(Icons.visibility_outlined);
      expect(visibilityButton, findsOneWidget);

      await tester.tap(visibilityButton);
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.visibility_off_outlined), findsOneWidget);
    });
  });
}
