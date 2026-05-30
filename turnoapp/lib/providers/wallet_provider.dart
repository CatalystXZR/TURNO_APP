import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/supabase_client.dart';
import '../models/transaction.dart';
import '../models/wallet.dart';
import 'lifecycle_provider.dart';
import 'service_providers.dart';

class WalletState {
  final Wallet? wallet;
  final List<Transaction> transactions;
  final bool loading;
  final bool topupLoading;
  final DateTime lastFetchedAt;

  WalletState({
    this.wallet,
    this.transactions = const [],
    this.loading = true,
    this.topupLoading = false,
    DateTime? lastFetchedAt,
  }) : lastFetchedAt = lastFetchedAt ?? DateTime(2000);

  WalletState copyWith({
    Wallet? wallet,
    List<Transaction>? transactions,
    bool? loading,
    bool? topupLoading,
    DateTime? lastFetchedAt,
  }) {
    return WalletState(
      wallet: wallet ?? this.wallet,
      transactions: transactions ?? this.transactions,
      loading: loading ?? this.loading,
      topupLoading: topupLoading ?? this.topupLoading,
      lastFetchedAt: lastFetchedAt ?? this.lastFetchedAt,
    );
  }
}

class WalletNotifier extends StateNotifier<WalletState> {
  WalletNotifier(this._ref) : super(WalletState()) {
    _ref.listen<AppLifecycleState>(
      lifecycleStateProvider,
      _onLifecycleChange,
    );

    _startRealtime();
    load();
  }

  final Ref _ref;
  RealtimeChannel? _walletChannel;
  Timer? _refreshDebounceTimer;

  static const _realtimeDebounce = Duration(milliseconds: 600);

  bool _loading = false;
  bool _disposed = false;

  @override
  void dispose() {
    _disposed = true;
    _refreshDebounceTimer?.cancel();
    final channel = _walletChannel;
    _walletChannel = null;
    if (channel != null) {
      SupabaseConfig.client.removeChannel(channel);
    }
    super.dispose();
  }

  void _onLifecycleChange(AppLifecycleState? prev, AppLifecycleState next) {
    if (prev == next) return;

    if (next == AppLifecycleState.paused ||
        next == AppLifecycleState.detached) {
      final channel = _walletChannel;
      _walletChannel = null;
      if (channel != null) {
        try {
          SupabaseConfig.client.removeChannel(channel);
        } catch (_) {}
      }
    } else if (next == AppLifecycleState.resumed) {
      if (_walletChannel == null) {
        _startRealtime();
      }
      Future.delayed(const Duration(milliseconds: 200), () {
        if (_disposed || !mounted) return;
        load();
      });
    }
  }

  void _startRealtime() {
    final uid = SupabaseConfig.client.auth.currentUser?.id;
    if (uid == null || uid.isEmpty) return;

    final channel = SupabaseConfig.client.channel('wallet-$uid');
    channel.onPostgresChanges(
      event: PostgresChangeEvent.all,
      schema: 'public',
      table: 'wallets',
      filter: PostgresChangeFilter(
        type: PostgresChangeFilterType.eq,
        column: 'user_id',
        value: uid,
      ),
      callback: (payload) {
        if (_disposed || !mounted) return;
        if (payload.eventType == PostgresChangeEvent.update ||
            payload.eventType == PostgresChangeEvent.insert) {
          if (state.wallet != null) {
            final record = payload.newRecord;
            try {
              state = state.copyWith(
                wallet: Wallet.fromJson(record),
              );
            } catch (_) {
              _scheduleRefresh();
            }
          } else {
            _scheduleRefresh();
          }
        } else {
          _scheduleRefresh();
        }
      },
    );
    try {
      channel.subscribe();
    } catch (_) {}
    _walletChannel = channel;
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
    state = state.copyWith(loading: state.wallet == null);
    final walletService = _ref.read(walletServiceProvider);
    try {
      final results = await Future.wait([
        walletService.getWallet(),
        walletService.getTransactions(),
      ]);
      if (_disposed || !mounted) return;
      state = state.copyWith(
        wallet: results[0] as Wallet?,
        transactions: results[1] as List<Transaction>,
        loading: false,
        lastFetchedAt: DateTime.now(),
      );
    } finally {
      _loading = false;
    }
  }

  Future<String> createTopupIntent(int amount) async {
    state = state.copyWith(topupLoading: true);
    try {
      final walletService = _ref.read(walletServiceProvider);
      return await walletService.createTopupIntent(amount);
    } finally {
      state = state.copyWith(topupLoading: false);
    }
  }

  Future<void> requestWithdrawal(int amount) async {
    final withdrawalService = _ref.read(withdrawalServiceProvider);
    await withdrawalService.requestWithdrawal(amount);
    await load();
  }

  Future<void> sandboxTopup(int amount) async {
    if (_disposed || !mounted) return;
    state = state.copyWith(topupLoading: true);
    try {
      final walletService = _ref.read(walletServiceProvider);
      await walletService.sandboxTopup(amount);
      if (_disposed || !mounted) return;
      await load();
    } finally {
      if (!_disposed && mounted) {
        state = state.copyWith(topupLoading: false);
      }
    }
  }

  Future<void> sandboxWithdraw(int amount) async {
    if (_disposed || !mounted) return;
    state = state.copyWith(topupLoading: true);
    try {
      final walletService = _ref.read(walletServiceProvider);
      await walletService.sandboxWithdraw(amount);
      if (_disposed || !mounted) return;
      await load();
    } finally {
      if (!_disposed && mounted) {
        state = state.copyWith(topupLoading: false);
      }
    }
  }
}

final walletProvider = StateNotifierProvider<WalletNotifier, WalletState>((
  ref,
) {
  return WalletNotifier(ref);
});
