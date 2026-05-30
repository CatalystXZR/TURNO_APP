import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/supabase_client.dart';
import '../models/app_notification.dart';
import '../models/booking.dart';
import '../models/ride.dart';
import '../services/booking_notification_service.dart';
import 'in_app_notification_provider.dart';
import 'lifecycle_provider.dart';
import 'service_providers.dart';

class DriverRidesState {
  final List<Ride> rides;
  final List<Booking> bookings;
  final bool loading;
  final String? errorMessage;
  final DateTime lastFetchedAt;

  DriverRidesState({
    this.rides = const [],
    this.bookings = const [],
    this.loading = true,
    this.errorMessage,
    DateTime? lastFetchedAt,
  }) : lastFetchedAt = lastFetchedAt ?? DateTime(2000);

  DriverRidesState copyWith({
    List<Ride>? rides,
    List<Booking>? bookings,
    bool? loading,
    String? errorMessage,
    DateTime? lastFetchedAt,
  }) {
    return DriverRidesState(
      rides: rides ?? this.rides,
      bookings: bookings ?? this.bookings,
      loading: loading ?? this.loading,
      errorMessage: errorMessage ?? this.errorMessage,
      lastFetchedAt: lastFetchedAt ?? this.lastFetchedAt,
    );
  }
}

class DriverRidesNotifier extends StateNotifier<DriverRidesState> {
  DriverRidesNotifier(this._ref) : super(DriverRidesState()) {
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
  RealtimeChannel? _ridesChannel;
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
    final ridesChannel = _ridesChannel;
    _ridesChannel = null;
    if (ridesChannel != null) {
      SupabaseConfig.client.removeChannel(ridesChannel);
    }
    final bookingsChannel = _bookingsChannel;
    _bookingsChannel = null;
    if (bookingsChannel != null) {
      SupabaseConfig.client.removeChannel(bookingsChannel);
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
      final rides = _ridesChannel;
      _ridesChannel = null;
      if (rides != null) {
        _subscriptionCleanup(() async {
          await SupabaseConfig.client.removeChannel(rides);
        });
      }
      final bookings = _bookingsChannel;
      _bookingsChannel = null;
      if (bookings != null) {
        _subscriptionCleanup(() async {
          await SupabaseConfig.client.removeChannel(bookings);
        });
      }
    } else if (next == AppLifecycleState.resumed) {
      if (_ridesChannel == null || _bookingsChannel == null) {
        _startRealtime();
      }
      _startFallbackTimer();
      _scheduleLazyRefresh();
    }
  }

  void _startRealtime() {
    final uid = SupabaseConfig.client.auth.currentUser?.id;
    if (uid == null || uid.isEmpty) return;

    final ridesChannel = SupabaseConfig.client.channel('rides-driver-$uid');
    ridesChannel.onPostgresChanges(
      event: PostgresChangeEvent.all,
      schema: 'public',
      table: 'rides',
      filter: PostgresChangeFilter(
        type: PostgresChangeFilterType.eq,
        column: 'driver_id',
        value: uid,
      ),
      callback: (_) => _scheduleRealtimeRefresh(),
    );
    try {
      ridesChannel.subscribe();
    } catch (e) {
      debugPrint('[Turno] DriverRides: rides channel subscribe failed: $e');
    }
    _ridesChannel = ridesChannel;

    final bookingsChannel =
        SupabaseConfig.client.channel('bookings-driver-$uid');
    bookingsChannel.onPostgresChanges(
      event: PostgresChangeEvent.all,
      schema: 'public',
      table: 'bookings',
      filter: PostgresChangeFilter(
        type: PostgresChangeFilterType.eq,
        column: 'driver_id',
        value: uid,
      ),
      callback: (_) => _scheduleRealtimeRefresh(),
    );
    try {
      bookingsChannel.subscribe();
    } catch (e) {
      debugPrint(
          '[Turno] DriverRides: bookings channel subscribe failed: $e');
    }
    _bookingsChannel = bookingsChannel;
  }

  void _startFallbackTimer() {
    _fallbackTimer?.cancel();
    _fallbackTimer =
        Timer.periodic(_fallbackInterval, (_) => _refreshSilently());
  }

  void _subscriptionCleanup(Future<void> Function() action) {
    try {
      action();
    } catch (e) {
      debugPrint('[Turno] DriverRides: subscription cleanup failed: $e');
    }
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
    state = state.copyWith(loading: true, errorMessage: null);
    try {
      await _fetch().timeout(const Duration(seconds: 15));
    } catch (e) {
      state = state.copyWith(
        loading: false,
        errorMessage: e.toString(),
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
      await _fetch();
    } catch (e) {
      if (!mounted) return;
      if (state.loading) {
        state = state.copyWith(loading: false);
      }
    } finally {
      _loading = false;
      if (gen >= _generation) {
        _generation = gen + 1;
      }
    }
  }

  Future<void> _fetch() async {
    final rideService = _ref.read(rideServiceProvider);
    final bookingService = _ref.read(bookingServiceProvider);
    final results = await Future.wait([
      rideService.getMyRides(),
      bookingService.getBookingsForMyRides(),
    ]);
    if (!mounted) return;
    state = state.copyWith(
      rides: results[0] as List<Ride>,
      bookings: results[1] as List<Booking>,
      loading: false,
      errorMessage: null,
      lastFetchedAt: DateTime.now(),
    );
    await BookingNotificationService.instance
        .syncDriverBookings(results[1] as List<Booking>);
  }

  void clearError() {
    state = state.copyWith(errorMessage: null);
  }

  Future<void> cancelRide(String rideId, {required String reason}) async {
    final rideService = _ref.read(rideServiceProvider);
    await rideService.cancelRide(rideId, reason: reason);
    await load();
  }

  Future<void> acceptBooking(String bookingId) async {
    final bookingService = _ref.read(bookingServiceProvider);
    await bookingService.driverAcceptBooking(bookingId);
    await load();
  }

  Future<void> rejectBooking(String bookingId, {String? reason}) async {
    final bookingService = _ref.read(bookingServiceProvider);
    await bookingService.driverRejectBooking(bookingId, reason: reason);
    await load();
  }

  Future<void> markArriving(String bookingId) async {
    final bookingService = _ref.read(bookingServiceProvider);
    await bookingService.driverMarkArriving(bookingId);
    await load();
  }

  Future<void> markArrived(String bookingId) async {
    final bookingService = _ref.read(bookingServiceProvider);
    await bookingService.driverMarkArrived(bookingId);
    await load();
  }

  Future<void> startTrip(String bookingId) async {
    final bookingService = _ref.read(bookingServiceProvider);
    await bookingService.driverStartTrip(bookingId);
    await load();
  }

  Future<void> completeTrip(String bookingId) async {
    final bookingService = _ref.read(bookingServiceProvider);
    await bookingService.driverCompleteTrip(bookingId);
    await load();
  }

  Future<void> completeRide(String rideId) async {
    final bookingService = _ref.read(bookingServiceProvider);
    await bookingService.driverCompleteRide(rideId);
    await load();
  }
}

final driverRidesProvider =
    StateNotifierProvider<DriverRidesNotifier, DriverRidesState>(
  (ref) => DriverRidesNotifier(ref),
);
