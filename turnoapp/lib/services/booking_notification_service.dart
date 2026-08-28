import '../models/app_notification.dart';
import '../models/booking.dart';
import '../models/enums.dart';
import 'notification_service.dart';

typedef InAppNotifyCallback = void Function(AppNotification notification);

class BookingNotificationService {
  BookingNotificationService._();

  static final BookingNotificationService instance =
      BookingNotificationService._();

  final Map<String, String> _passengerSnapshot = {};
  final Map<String, String> _driverSnapshot = {};
  bool _passengerHydrated = false;
  bool _driverHydrated = false;

  final List<InAppNotifyCallback> _inAppCallbacks = [];

  void addInAppNotifyCallback(InAppNotifyCallback callback) {
    _inAppCallbacks.add(callback);
  }

  void removeInAppNotifyCallback(InAppNotifyCallback callback) {
    _inAppCallbacks.remove(callback);
  }

  void clearPassengerSnapshots() {
    _passengerSnapshot.clear();
    _passengerHydrated = false;
  }

  void clearDriverSnapshots() {
    _driverSnapshot.clear();
    _driverHydrated = false;
  }

  void clearSnapshots() {
    clearPassengerSnapshots();
    clearDriverSnapshots();
  }

  Future<void> syncPassengerBookings(List<Booking> bookings) async {
    final activeIds = <String>{};
    final shouldNotify = _passengerHydrated;

    for (final booking in bookings) {
      activeIds.add(booking.id);
      final key = '${booking.status.name}|${booking.dispatchStatus.name}';
      final prev = _passengerSnapshot[booking.id];
      _passengerSnapshot[booking.id] = key;

      if (!shouldNotify || prev == null || prev == key) continue;

      final message = _passengerTransitionMessage(booking);
      if (message == null) continue;

      final title = 'Actualizacion de tu reserva';
      await NotificationService.instance.show(
        id: _notifId(booking.id, key),
        title: title,
        body: message,
      );

      _addInApp(
        title: title,
        body: message,
        bookingId: booking.id,
        rideId: booking.rideId,
        seed: key,
      );
    }

    _passengerSnapshot.removeWhere((id, _) => !activeIds.contains(id));
    _passengerHydrated = true;
  }

  Future<void> syncDriverBookings(List<Booking> bookings) async {
    final activeIds = <String>{};
    final shouldNotify = _driverHydrated;

    for (final booking in bookings) {
      activeIds.add(booking.id);
      final key = '${booking.status.name}|${booking.dispatchStatus.name}';
      final prev = _driverSnapshot[booking.id];
      _driverSnapshot[booking.id] = key;

      if (prev == null) {
        if (!shouldNotify) continue;
        if (booking.status == BookingStatus.reserved &&
            booking.dispatchStatus == BookingDispatchStatus.reserved) {
          final title = 'Nueva solicitud de viaje';
          final body =
              '${booking.passengerName ?? 'Un pasajero'} quiere reservar tu turno.';

          await NotificationService.instance.show(
            id: _notifId(booking.id, 'new_request'),
            title: title,
            body: body,
          );

          _addInApp(
            title: title,
            body: body,
            bookingId: booking.id,
            rideId: booking.rideId,
            seed: 'new_request',
          );
        }
        continue;
      }

      if (prev == key) continue;
      if (!shouldNotify) continue;

      final event = _driverTransitionEvent(booking);
      if (event == null) continue;

      await NotificationService.instance.show(
        id: _notifId(booking.id, key),
        title: event.title,
        body: event.body,
      );

      _addInApp(
        title: event.title,
        body: event.body,
        bookingId: booking.id,
        rideId: booking.rideId,
        seed: key,
      );
    }

    _driverSnapshot.removeWhere((id, _) => !activeIds.contains(id));
    _driverHydrated = true;
  }

  _DriverEvent? _driverTransitionEvent(Booking booking) {
    final name = booking.passengerName ?? 'El pasajero';

    switch (booking.dispatchStatus) {
      case BookingDispatchStatus.accepted:
        return _DriverEvent(
            'Reserva aceptada', 'Aceptaste la reserva de $name.');
      case BookingDispatchStatus.cancelled:
        return _DriverEvent('Reserva cancelada', '$name cancelo su reserva.');
      case BookingDispatchStatus.noShow:
        return _DriverEvent(
            'Viaje no-show', 'El viaje con $name fue cerrado como no-show.');
      case BookingDispatchStatus.passengerBoarded:
        return _DriverEvent('Pasajero a bordo',
            '$name confirmo abordaje. Ya puedes iniciar el viaje.');
      case BookingDispatchStatus.inProgress:
        return _DriverEvent(
            'Viaje en curso', 'El viaje con $name esta en curso.');
      case BookingDispatchStatus.completed:
        return _DriverEvent('Viaje finalizado',
            'El viaje con $name fue completado y liquidado a tu billetera.');
      case BookingDispatchStatus.driverArriving:
      case BookingDispatchStatus.driverArrived:
        return null;
      case BookingDispatchStatus.reserved:
        return null;
    }
  }

  String? _passengerTransitionMessage(Booking booking) {
    switch (booking.dispatchStatus) {
      case BookingDispatchStatus.accepted:
        return 'Te han confirmado el Ride! ${booking.driverName ?? 'El conductor'} acepto tu reserva.';
      case BookingDispatchStatus.driverArriving:
        return 'El rider va en camino! ${booking.driverName ?? 'Tu conductor'} se dirige al punto de encuentro.';
      case BookingDispatchStatus.driverArrived:
        return 'El rider ha llegado! ${booking.driverName ?? 'Tu conductor'} ya esta en el punto de encuentro.';
      case BookingDispatchStatus.inProgress:
        return 'Viaje en curso.';
      case BookingDispatchStatus.completed:
        return 'Viaje finalizado. Puedes calificar a ${booking.driverName ?? 'tu conductor'}.';
      case BookingDispatchStatus.cancelled:
        return 'Tu reserva fue cancelada.';
      case BookingDispatchStatus.noShow:
        return 'El viaje se cerro como no-show.';
      case BookingDispatchStatus.reserved:
      case BookingDispatchStatus.passengerBoarded:
        return null;
    }
  }

  void _addInApp({
    required String title,
    required String body,
    String? bookingId,
    String? rideId,
    String? seed,
  }) {
    final notification = AppNotification(
      id: (bookingId ?? DateTime.now().millisecondsSinceEpoch.toString()) +
          (seed ?? ''),
      title: title,
      body: body,
      createdAt: DateTime.now(),
      bookingId: bookingId,
      rideId: rideId,
    );

    for (final callback in _inAppCallbacks) {
      callback(notification);
    }
  }

  int _notifId(String bookingId, String seed) {
    return (bookingId.hashCode ^ seed.hashCode).abs() & 0x7fffffff;
  }
}

class _DriverEvent {
  final String title;
  final String body;
  const _DriverEvent(this.title, this.body);
}
