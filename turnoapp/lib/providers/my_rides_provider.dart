import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/error_mapper.dart';
import '../core/supabase_client.dart';
import '../models/app_notification.dart';
import '../models/booking.dart';
import '../services/booking_notification_service.dart';
import 'in_app_notification_provider.dart';
import 'lifecycle_provider.dart';
import 'service_providers.dart';

class MyRidesState {
  final List<Booking> bookings;
  final bool loading;
  final String? errorMessage;
  final DateTime lastFetchedAt;

  MyRidesState({
    this.bookings = const [],
    this.loading = true,
    this.errorMessage,
    DateTime? lastFetchedAt,
  }) : lastFetchedAt = lastFetchedAt ?? DateTime(2000);

  MyRidesState copyWith({
    List<Booking>? bookings,
    bool? loading,
    String? errorMessage,
    bool clearError = false,
    DateTime? lastFetchedAt,
  }) {
    return MyRidesState(
      bookings: bookings ?? this.bookings,
      loading: loading ?? this.loading,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
      lastFetchedAt: lastFetchedAt ?? this.lastFetchedAt,
    );
  }
}

class MyRidesNotifier extends StateNotifier<MyRidesState> {
  MyRidesNotifier(this._ref) : super(MyRidesState()) {
    _inAppCallback = (notif) {
      _ref.read(inAppNotificationProvider.notifier).add(
            title: notif.title,
            body: notif.body,
            bookingId: notif.bookingId,
            rideId: notif.rideId,
            notifId: notif.id.hashCode,
          );
    };
    BookingNotificationService.instance
        .addInAppNotifyCallback(_inAppCallback);

    _ref.listen<AppLifecycleState>(
      lifecycleStateProvider,
      _onLifecycleChange,
    );

    load();
    _startRealtime();
    _startFallbackTimer();
  }

  final Ref _ref;
  RealtimeChannel? _bookingsChannel;
  Timer? _fallbackTimer;
  Timer? _refreshDebounceTimer;
  late final void Function(AppNotification) _inAppCallback;

  static const _fallbackInterval = Duration(seconds: 45);
  static const _realtimeDebounce = Duration(milliseconds: 600);

  bool _loading = false;
  int _generation = 0;
  bool _scheduledLazyRefresh = false;

  @override
  void dispose() {
    _fallbackTimer?.cancel();
    _refreshDebounceTimer?.cancel();
    final channel = _bookingsChannel;
    _bookingsChannel = null;
    if (channel != null) {
      SupabaseConfig.client.removeChannel(channel);
    }
    BookingNotificationService.instance
        .removeInAppNotifyCallback(_inAppCallback);
    super.dispose();
  }

  void _onLifecycleChange(AppLifecycleState? prev, AppLifecycleState next) {
    if (prev == next) return;

    if (next == AppLifecycleState.paused ||
        next == AppLifecycleState.detached) {
      _fallbackTimer?.cancel();
      final channel = _bookingsChannel;
      _bookingsChannel = null;
      if (channel != null) {
        _subscriptionCleanup(() async {
          await SupabaseConfig.client.removeChannel(channel);
        });
      }
    } else if (next == AppLifecycleState.resumed) {
      if (_bookingsChannel == null) {
        _startRealtime();
      }
      _startFallbackTimer();
      _scheduleLazyRefresh();
    }
  }

  void _startRealtime() {
    final uid = SupabaseConfig.client.auth.currentUser?.id;
    if (uid == null || uid.isEmpty) return;

    final channel = SupabaseConfig.client.channel('bookings-passenger-$uid');
    channel.onPostgresChanges(
      event: PostgresChangeEvent.all,
      schema: 'public',
      table: 'bookings',
      filter: PostgresChangeFilter(
        type: PostgresChangeFilterType.eq,
        column: 'passenger_id',
        value: uid,
      ),
      callback: (_) => _scheduleRealtimeRefresh(),
    );
    try {
      channel.subscribe();
    } catch (e) {
      debugPrint('[Turno] MyRides: realtime subscribe failed: $e');
    }
    _bookingsChannel = channel;
  }

  void _startFallbackTimer() {
    _fallbackTimer?.cancel();
    _fallbackTimer =
        Timer.periodic(_fallbackInterval, (_) => _refreshSilently());
  }

  void _subscriptionCleanup(Future<void> Function() action) {
    action().catchError((e) {
      debugPrint('[Turno] MyRides: subscription cleanup failed: $e');
    });
  }

  void _scheduleLazyRefresh() {
    if (_scheduledLazyRefresh) return;
    _scheduledLazyRefresh = true;
    Future.delayed(const Duration(milliseconds: 200), () {
      _scheduledLazyRefresh = false;
      if (mounted) _refreshSilently();
    });
  }

  void _scheduleRealtimeRefresh() {
    _refreshDebounceTimer?.cancel();
    _refreshDebounceTimer = Timer(_realtimeDebounce, _refreshSilently);
  }

  Future<void> load() async {
    if (_loading) {
      _pendingLoad = true;
      return;
    }
    _loading = true;
    _pendingLoad = false;
    state = state.copyWith(loading: true, clearError: true);
    try {
      final service = _ref.read(bookingServiceProvider);
      final rows =
          await service.getMyBookings().timeout(const Duration(seconds: 15));
      await BookingNotificationService.instance.syncPassengerBookings(rows);
      if (!mounted) return;
      _generation++;
      state = state.copyWith(
        bookings: rows,
        loading: false,
        clearError: true,
        lastFetchedAt: DateTime.now(),
      );
    } catch (e) {
      if (!mounted) return;
      state = state.copyWith(
        loading: false,
        errorMessage: AppErrorMapper.toMessage(e),
      );
    } finally {
      _loading = false;
      if (_pendingLoad) {
        _pendingLoad = false;
        if (mounted) load();
      }
    }
  }

  bool _pendingLoad = false;

  Future<void> _refreshSilently() async {
    if (_loading) return;
    _loading = true;
    final gen = _generation;
    try {
      final service = _ref.read(bookingServiceProvider);
      final rows = await service.getMyBookings();
      await BookingNotificationService.instance.syncPassengerBookings(rows);
      if (!mounted) return;
      if (gen < _generation) return;
      _generation = gen + 1;
      state = state.copyWith(
        bookings: rows,
        loading: false,
        lastFetchedAt: DateTime.now(),
      );
    } catch (e) {
      if (!mounted) return;
      if (state.loading) {
        state = state.copyWith(loading: false);
      }
    } finally {
      _loading = false;
    }
  }

  Future<void> confirmBoarding(String bookingId) async {
    final service = _ref.read(bookingServiceProvider);
    await service.confirmBoarding(bookingId);
    await load();
  }

  Future<void> driverAcceptBooking(String bookingId) async {
    final service = _ref.read(bookingServiceProvider);
    await service.driverAcceptBooking(bookingId);
    await load();
  }

  Future<void> driverMarkArriving(String bookingId) async {
    final service = _ref.read(bookingServiceProvider);
    await service.driverMarkArriving(bookingId);
    await load();
  }

  Future<void> driverMarkArrived(String bookingId) async {
    final service = _ref.read(bookingServiceProvider);
    await service.driverMarkArrived(bookingId);
    await load();
  }

  Future<void> driverStartTrip(String bookingId) async {
    final service = _ref.read(bookingServiceProvider);
    await service.driverStartTrip(bookingId);
    await load();
  }

  Future<void> driverCompleteTrip(String bookingId) async {
    final service = _ref.read(bookingServiceProvider);
    await service.driverCompleteTrip(bookingId);
    await load();
  }

  Future<void> cancelBooking(String bookingId) async {
    final service = _ref.read(bookingServiceProvider);
    await service.cancelBooking(bookingId);
    await load();
  }

  Future<void> reportNoShow(String bookingId, {String? notes}) async {
    final service = _ref.read(bookingServiceProvider);
    await service.reportDriverNoShow(bookingId, notes: notes);
    await load();
  }
}

final myRidesProvider = StateNotifierProvider<MyRidesNotifier, MyRidesState>(
  (ref) => MyRidesNotifier(ref),
);
