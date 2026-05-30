import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/error_mapper.dart';
import '../core/supabase_client.dart';
import '../models/enums.dart';
import '../models/user_profile.dart';
import '../models/wallet.dart';
import 'service_providers.dart';

class HomeState {
  final UserProfile? profile;
  final Wallet? wallet;
  final bool loading;
  final bool switchingRole;
  final String? errorMessage;

  const HomeState({
    this.profile,
    this.wallet,
    this.loading = true,
    this.switchingRole = false,
    this.errorMessage,
  });

  HomeState copyWith({
    UserProfile? profile,
    Wallet? wallet,
    bool? loading,
    bool? switchingRole,
    String? errorMessage,
    bool clearError = false,
  }) {
    return HomeState(
      profile: profile ?? this.profile,
      wallet: wallet ?? this.wallet,
      loading: loading ?? this.loading,
      switchingRole: switchingRole ?? this.switchingRole,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
    );
  }
}

class HomeNotifier extends StateNotifier<HomeState> {
  HomeNotifier(this._ref) : super(const HomeState()) {
    _startRealtime();
    load();
  }

  final Ref _ref;
  RealtimeChannel? _profileChannel;
  RealtimeChannel? _walletChannel;
  Timer? _refreshDebounceTimer;

  static const _realtimeDebounce = Duration(milliseconds: 600);

  bool _loading = false;
  bool _disposed = false;

  @override
  void dispose() {
    _disposed = true;
    _refreshDebounceTimer?.cancel();
    final pc = _profileChannel;
    _profileChannel = null;
    if (pc != null) {
      SupabaseConfig.client.removeChannel(pc);
    }
    final wc = _walletChannel;
    _walletChannel = null;
    if (wc != null) {
      SupabaseConfig.client.removeChannel(wc);
    }
    super.dispose();
  }

  void _startRealtime() {
    final uid = SupabaseConfig.client.auth.currentUser?.id;
    if (uid == null || uid.isEmpty) return;

    final profileChannel = SupabaseConfig.client.channel('profile-$uid');
    profileChannel.onPostgresChanges(
      event: PostgresChangeEvent.all,
      schema: 'public',
      table: 'users_profile',
      filter: PostgresChangeFilter(
        type: PostgresChangeFilterType.eq,
        column: 'id',
        value: uid,
      ),
      callback: (_) => _scheduleRefresh(),
    );
    profileChannel.subscribe();
    _profileChannel = profileChannel;

    final walletChannel = SupabaseConfig.client.channel('home-wallet-$uid');
    walletChannel.onPostgresChanges(
      event: PostgresChangeEvent.all,
      schema: 'public',
      table: 'wallets',
      filter: PostgresChangeFilter(
        type: PostgresChangeFilterType.eq,
        column: 'user_id',
        value: uid,
      ),
      callback: (payload) {
        if (_disposed) return;
        if (payload.eventType == PostgresChangeEvent.update ||
            payload.eventType == PostgresChangeEvent.insert) {
          try {
            state = state.copyWith(
              wallet: Wallet.fromJson(payload.newRecord),
            );
          } catch (e) {
            debugPrint('[Turno] HomeProvider: wallet parse error, falling back to refresh: $e');
            _scheduleRefresh();
          }
        } else {
          _scheduleRefresh();
        }
      },
    );
    walletChannel.subscribe();
    _walletChannel = walletChannel;
  }

  void _scheduleRefresh() {
    _refreshDebounceTimer?.cancel();
    _refreshDebounceTimer = Timer(_realtimeDebounce, () {
      if (_disposed || !mounted) return;
      load();
    });
  }

  Future<void> load() async {
    if (_loading) return;
    _loading = true;
    state = state.copyWith(loading: state.profile == null, clearError: true);
    final profileService = _ref.read(profileServiceProvider);
    final walletService = _ref.read(walletServiceProvider);
    try {
      final results = await Future.wait([
        profileService.getProfile(),
        walletService.getWallet(),
      ]);
      if (!mounted || _disposed) return;
      state = state.copyWith(
        profile: results[0] as UserProfile?,
        wallet: results[1] as Wallet?,
        loading: false,
      );
    } catch (e) {
      if (!mounted || _disposed) return;
      state = state.copyWith(
        loading: false,
        errorMessage: AppErrorMapper.toMessage(
          e,
          fallback: 'No pudimos cargar tu inicio. Intenta nuevamente.',
        ),
      );
    } finally {
      _loading = false;
    }
  }

  Future<void> refresh() => load();

  void clearError() {
    state = state.copyWith(clearError: true);
  }

  Future<void> setRoleMode(RoleMode mode) async {
    state = state.copyWith(switchingRole: true);
    try {
      final profileService = _ref.read(profileServiceProvider);
      final updated = await profileService.setRoleMode(mode);
      state = state.copyWith(profile: updated, switchingRole: false);
    } catch (_) {
      state = state.copyWith(switchingRole: false);
      rethrow;
    }
  }
}

final homeProvider = StateNotifierProvider<HomeNotifier, HomeState>(
  (ref) => HomeNotifier(ref),
);
