import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/supabase_client.dart';

class PushNotificationService {
  PushNotificationService._();

  static final PushNotificationService instance = PushNotificationService._();

  static const _channel = MethodChannel('cl.turnoapp/push');

  void Function(Map<String, dynamic>)? onPushTapped;

  bool _initialized = false;
  String? _pendingToken;
  StreamSubscription<AuthState>? _authSub;

  Future<void> initialize() async {
    if (_initialized) return;
    if (kIsWeb) return;
    if (defaultTargetPlatform != TargetPlatform.iOS) {
      _initialized = true;
      return;
    }

    _channel.setMethodCallHandler(_handleMethodCall);

    _authSub =
        SupabaseConfig.client.auth.onAuthStateChange.listen(_onAuthState);

    _initialized = true;
  }

  void dispose() {
    _authSub?.cancel();
  }

  void _onAuthState(AuthState state) {
    final userId = state.session?.user.id;
    final token = _pendingToken;

    if (userId != null && token != null) {
      _registerToken(token);
    } else if (userId == null) {
      _pendingToken = null;
    }
  }

  Future<void> _handleMethodCall(MethodCall call) async {
    switch (call.method) {
      case 'onDeviceToken':
        final token = call.arguments as String?;
        if (token != null) {
          _pendingToken = token;
          final uid = SupabaseConfig.client.auth.currentUser?.id;
          if (uid != null) {
            await _registerToken(token);
          }
        }
        break;
      case 'onPushTapped':
        final args = call.arguments as Map?;
        if (args != null) {
          final data = Map<String, dynamic>.from(args);
          onPushTapped?.call(data);
        }
        break;
    }
  }

  Future<void> _registerToken(String token) async {
    try {
      final uid = SupabaseConfig.client.auth.currentUser?.id;
      if (uid == null) return;

      await SupabaseConfig.client.from('device_tokens').upsert({
        'user_id': uid,
        'platform': 'ios',
        'token': token,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
        'created_at': DateTime.now().toUtc().toIso8601String(),
      }, onConflict: 'user_id, token');
    } catch (e) {
      debugPrint('[Turno] Error registering push token: $e');
    }
  }
}
