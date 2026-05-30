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

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import 'core/supabase_client.dart';
import 'app/app.dart';
import 'app/theme.dart';
import 'core/error_mapper.dart';
import 'services/notification_service.dart';
import 'services/push_notification_service.dart';
import 'shared/widgets/app_snackbar.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize Spanish locale data for DateFormat('...', 'es') calls throughout the app.
  await initializeDateFormatting('es', null);

  await SentryFlutter.init(
    (options) {
      options.dsn = const String.fromEnvironment('SENTRY_DSN');
      options.tracesSampleRate = 0.5;
      options.profilesSampleRate = 0.5;
      options.attachScreenshot = false;
      options.attachViewHierarchy = true;
    },
    appRunner: () async {
      try {
        SupabaseConfig.ensureConfigured();
        await SupabaseConfig.initialize();
        await NotificationService.instance.initialize();
        await PushNotificationService.instance.initialize();
      } catch (_) {
        runApp(const _ConfigurationErrorApp());
        return;
      }

      runApp(const ProviderScope(child: Turno()));
    },
  );
}

class _ConfigurationErrorApp extends StatelessWidget {
  const _ConfigurationErrorApp();

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        body: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 520),
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.all(18),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const Icon(
                          Icons.settings_input_component_outlined,
                          size: 42,
                          color: Color(0xFF8A2F43),
                        ),
                        const SizedBox(height: 10),
                        const Text(
                          'Configuracion incompleta',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          AppErrorMapper.toMessage(
                            'supabase_not_configured',
                            fallback:
                                'Faltan SUPABASE_URL y SUPABASE_ANON_KEY en --dart-define.',
                          ),
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: AppTheme.subtle),
                        ),
                        const SizedBox(height: 14),
                        SelectableText(
                          'flutter run -d edge --dart-define=SUPABASE_URL=https://TU_PROYECTO.supabase.co --dart-define=SUPABASE_ANON_KEY=TU_ANON_KEY',
                          style: const TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 12,
                          ),
                        ),
                        const SizedBox(height: 10),
                        TextButton(
                          onPressed: () {
                            AppSnackbar.show(
                              context,
                              'Define los --dart-define y reinicia la app.',
                              isError: true,
                            );
                          },
                          child: const Text('Entendido'),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
