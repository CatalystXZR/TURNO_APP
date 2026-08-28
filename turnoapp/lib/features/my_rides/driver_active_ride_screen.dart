import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app/theme.dart';
import '../../core/constants.dart';
import '../../core/error_mapper.dart';
import '../../models/booking.dart';
import '../../models/enums.dart';
import '../../models/ride.dart';
import '../../providers/driver_rides_provider.dart';
import '../../services/favorites_service.dart';
import '../../services/review_service.dart';
import '../../shared/widgets/app_snackbar.dart';
import '../../shared/widgets/booking_flow_buttons.dart';
import '../../shared/widgets/loading_overlay.dart';
import '../../shared/widgets/review_dialog.dart';

class DriverActiveRideScreen extends ConsumerStatefulWidget {
  final String rideId;

  const DriverActiveRideScreen({super.key, required this.rideId});

  @override
  ConsumerState<DriverActiveRideScreen> createState() =>
      _DriverActiveRideScreenState();
}

class _DriverActiveRideScreenState
    extends ConsumerState<DriverActiveRideScreen> {
  final _favoritesService = FavoritesService();
  final _reviewService = ReviewService();
  bool _busy = false;
  String? _busyMessage;
  Set<String> _favoritePassengerIds = <String>{};
  bool _navigatedToArrival = false;
  bool _callbackRegistered = false;

  Future<void> _runBusy(
    String message,
    Future<void> Function() action,
  ) async {
    if (_busy) return;
    if (mounted) {
      setState(() {
        _busy = true;
        _busyMessage = message;
      });
    }
    try {
      await action();
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _busyMessage = null;
        });
      }
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _refresh();
    });
  }

  Ride? _rideFromState(DriverRidesState state) {
    try {
      return state.rides.firstWhere((r) => r.id == widget.rideId);
    } catch (e) {
      debugPrint('[Turno] DriverActive: rideFromState: $e');
      return null;
    }
  }

  List<Booking> _bookingsForThisRide(DriverRidesState state) {
    return state.bookings.where((b) => b.rideId == widget.rideId).toList();
  }

  Future<void> _refresh() async {
    try {
      await ref.read(driverRidesProvider.notifier).load();
      try {
        final favorites = await _favoritesService.getMyFavorites();
        if (!mounted) return;
        setState(() {
          _favoritePassengerIds = favorites
              .where((item) => item.roleMode == RoleMode.passenger)
              .map((item) => item.userId)
              .toSet();
        });
      } catch (e) {
        debugPrint('[Turno] DriverActive: getMyFavorites failed: $e');
        if (!mounted) return;
        setState(() => _favoritePassengerIds = <String>{});
      }
      if (!mounted) return;
      _checkArrival();
    } catch (e) {
      if (!mounted) return;
      AppSnackbar.show(
        context,
        AppErrorMapper.toMessage(e,
            fallback: 'No pudimos actualizar el estado del viaje.'),
        isError: true,
      );
    }
  }

  Future<void> _checkArrival() async {
    if (_navigatedToArrival) return;
    final state = ref.read(driverRidesProvider);
    final ride = _rideFromState(state);
    if (ride != null && ride.status == 'completed') {
      _navigatedToArrival = true;
      if (!mounted) return;
      context.push('/arrival');
    }
  }

  Future<void> _acceptBooking(Booking booking) async {
    await _runBusy('Aceptando reserva...', () async {
      try {
        await ref.read(driverRidesProvider.notifier).acceptBooking(booking.id);
        if (!mounted) return;
        AppSnackbar.show(context, 'Reserva aceptada.');
      } catch (e) {
        if (!mounted) return;
        AppSnackbar.show(
          context,
          AppErrorMapper.toMessage(e,
              fallback: 'No pudimos aceptar la reserva.'),
          isError: true,
        );
      }
    });
  }

  Future<void> _rejectBooking(Booking booking) async {
    final reasonController = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Rechazar reserva'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Se devolvera el monto retenido al pasajero.'),
            const SizedBox(height: 8),
            TextField(
              controller: reasonController,
              decoration: const InputDecoration(
                labelText: 'Motivo (opcional)',
              ),
              maxLines: 2,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.danger,
              foregroundColor: Colors.white,
            ),
            child: const Text('Rechazar'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) {
      reasonController.dispose();
      return;
    }

    await _runBusy('Rechazando...', () async {
      try {
        await ref.read(driverRidesProvider.notifier).rejectBooking(
              booking.id,
              reason: reasonController.text.trim().isEmpty
                  ? null
                  : reasonController.text.trim(),
            );
        if (!mounted) return;
        AppSnackbar.show(context, 'Reserva rechazada.');
      } catch (e) {
        if (!mounted) return;
        AppSnackbar.show(
          context,
          AppErrorMapper.toMessage(e,
              fallback: 'No pudimos rechazar la reserva.'),
          isError: true,
        );
      } finally {
        reasonController.dispose();
      }
    });
  }

  Future<void> _markArriving(Booking booking) async {
    await _runBusy('Actualizando estado...', () async {
      try {
        await ref.read(driverRidesProvider.notifier).markArriving(booking.id);
        if (!mounted) return;
        AppSnackbar.show(context, 'Marcado: En camino.');
      } catch (e) {
        if (!mounted) return;
        AppSnackbar.show(
          context,
          AppErrorMapper.toMessage(e,
              fallback: 'No pudimos actualizar a en camino.'),
          isError: true,
        );
      }
    });
  }

  Future<void> _markArrived(Booking booking) async {
    await _runBusy('Actualizando estado...', () async {
      try {
        await ref.read(driverRidesProvider.notifier).markArrived(booking.id);
        if (!mounted) return;
        AppSnackbar.show(context, 'Marcado: Llegue a destino.');
      } catch (e) {
        if (!mounted) return;
        AppSnackbar.show(
          context,
          AppErrorMapper.toMessage(e,
              fallback: 'No pudimos actualizar llegada.'),
          isError: true,
        );
      }
    });
  }

  Future<void> _startTrip(Booking booking) async {
    await _runBusy('Iniciando viaje...', () async {
      try {
        await ref.read(driverRidesProvider.notifier).startTrip(booking.id);
        if (!mounted) return;
        AppSnackbar.show(context, 'Viaje iniciado.');
      } catch (e) {
        if (!mounted) return;
        AppSnackbar.show(
          context,
          AppErrorMapper.toMessage(e, fallback: 'No pudimos iniciar el viaje.'),
          isError: true,
        );
      }
    });
  }

  Future<void> _completeTrip(Booking booking) async {
    await _runBusy('Finalizando viaje...', () async {
      try {
        await ref.read(driverRidesProvider.notifier).completeTrip(booking.id);
        if (!mounted) return;
        AppSnackbar.show(context, 'Viaje finalizado y liquidado.');
        _refresh();
        _checkArrival();
      } catch (e) {
        if (!mounted) return;
        AppSnackbar.show(
          context,
          AppErrorMapper.toMessage(e,
              fallback: 'No pudimos finalizar el viaje.'),
          isError: true,
        );
      }
    });
  }

  Future<void> _reviewPassenger(Booking booking) async {
    await _runBusy('Publicando resena...', () async {
      try {
        final already = await _reviewService.hasReviewForBooking(booking.id);
        if (already) {
          if (!mounted) return;
          AppSnackbar.show(context, 'Ya enviaste una resena para este viaje.');
          return;
        }
        if (!mounted) return;
        final result = await showDialog<Map<String, dynamic>>(
          context: context,
          builder: (_) => const ReviewDialog(
            title: 'Calificar pasajero',
            subtitle:
                'Tu referencia sera publica para ayudar a otros conductores.',
            confirmLabel: 'Publicar resena',
          ),
        );
        if (result == null) return;
        await _reviewService.submitReview(
          bookingId: booking.id,
          stars: (result['stars'] as int?) ?? 5,
          comment: (result['comment'] as String?)?.trim(),
        );
        await _refresh();
        if (!mounted) return;
        AppSnackbar.show(context, 'Resena publicada correctamente.');
      } catch (e) {
        if (!mounted) return;
        AppSnackbar.show(
          context,
          AppErrorMapper.toMessage(
            e,
            fallback: 'No pudimos publicar la resena.',
          ),
          isError: true,
        );
      }
    });
  }

  Future<void> _toggleFavoritePassenger(Booking booking) async {
    await _runBusy('Actualizando favoritos...', () async {
      try {
        final isFav =
            await _favoritesService.toggleFavorite(booking.passengerId);
        if (!mounted) return;
        setState(() {
          if (isFav) {
            _favoritePassengerIds.add(booking.passengerId);
          } else {
            _favoritePassengerIds.remove(booking.passengerId);
          }
        });
        AppSnackbar.show(
          context,
          isFav
              ? 'Pasajero agregado a favoritos.'
              : 'Pasajero eliminado de favoritos.',
        );
      } catch (e) {
        if (!mounted) return;
        AppSnackbar.show(
          context,
          AppErrorMapper.toMessage(
            e,
            fallback: 'No pudimos actualizar favoritos.',
          ),
          isError: true,
        );
      }
    });
  }

  Future<void> _completeRide() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Finalizar viaje'),
        content: const Text(
            'El viaje terminara y se pagara al conductor. Continuar?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Finalizar'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    await _runBusy('Finalizando...', () async {
      try {
        await ref
            .read(driverRidesProvider.notifier)
            .completeRide(widget.rideId);
        if (!mounted) return;
        AppSnackbar.show(context, 'Viaje completado.');
        _refresh();
        _checkArrival();
      } catch (e) {
        if (!mounted) return;
        AppSnackbar.show(
          context,
          AppErrorMapper.toMessage(e, fallback: 'Error al finalizar.'),
          isError: true,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(driverRidesProvider);
    final ride = _rideFromState(state);
    final bookings = _bookingsForThisRide(state);

    if (ride == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Gestion de viaje')),
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('No encontramos este turno.'),
              const SizedBox(height: 12),
              OutlinedButton(
                onPressed: _refresh,
                child: const Text('Actualizar'),
              ),
            ],
          ),
        ),
      );
    }

    if (!_callbackRegistered) {
      _callbackRegistered = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _checkArrival();
      });
    }

    final int acceptedCount = bookings
        .where((b) =>
            b.isReserved && b.dispatchStatus != BookingDispatchStatus.reserved)
        .length;
    final int boardedCount = bookings
        .where((b) =>
            b.isReserved &&
            (b.dispatchStatus == BookingDispatchStatus.passengerBoarded ||
                b.dispatchStatus == BookingDispatchStatus.inProgress))
        .length;
    final int pendingCount = bookings
        .where((b) =>
            b.isReserved && b.dispatchStatus == BookingDispatchStatus.reserved)
        .length;
    final int completedCount = bookings
        .where((b) => b.dispatchStatus == BookingDispatchStatus.completed)
        .length;

    final hasAnyInProgress = bookings
        .any((b) => b.dispatchStatus == BookingDispatchStatus.inProgress);
    final allPassengersBoarded = bookings.where((b) => b.isReserved).every(
        (b) =>
            b.dispatchStatus == BookingDispatchStatus.passengerBoarded ||
            b.dispatchStatus == BookingDispatchStatus.inProgress ||
            b.dispatchStatus == BookingDispatchStatus.completed);

    return LoadingOverlay(
      isLoading: _busy,
      message: _busyMessage,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Gestion de viaje'),
          actions: [
            IconButton(
              onPressed: _refresh,
              icon: const Icon(Icons.refresh),
            ),
          ],
        ),
        body: RefreshIndicator(
          onRefresh: _refresh,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 110),
            children: [
              _RideInfoHeader(ride: ride),
              const SizedBox(height: 16),
              _ProgressTracker(
                acceptedCount: acceptedCount,
                boardedCount: boardedCount,
                completedCount: completedCount,
                totalBookings: bookings.length,
              ),
              const SizedBox(height: 16),
              if (pendingCount > 0) ...[
                Card(
                  color: AppTheme.warningBg,
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Row(
                      children: [
                        const Icon(Icons.info_outline,
                            color: AppTheme.warning, size: 20),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            '$pendingCount pasajero${pendingCount > 1 ? 's' : ''} pendiente${pendingCount > 1 ? 's' : ''} de aceptacion',
                            style: const TextStyle(
                              fontWeight: FontWeight.w600,
                              color: AppTheme.warning,
                              fontSize: 13,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
              ],
              if (ride.isActive && allPassengersBoarded && !hasAnyInProgress)
                _RideLevelActionCard(
                  icon: Icons.play_arrow_rounded,
                  label: 'Iniciar viaje para todos',
                  description:
                      'Todos los pasajeros han abordado. Inicia el viaje.',
                  color: AppTheme.primary,
                  onPressed: () async {
                    final activeBookings = bookings
                        .where((b) =>
                            b.isReserved &&
                            b.dispatchStatus ==
                                BookingDispatchStatus.passengerBoarded)
                        .toList();
                    int succeeded = 0;
                    for (final b in activeBookings) {
                      try {
                        await ref
                            .read(driverRidesProvider.notifier)
                            .startTrip(b.id);
                        succeeded++;
                      } catch (e) {
                        debugPrint(
                            '[Turno] DriverActive: startTrip failed for ${b.id}: $e');
                      }
                    }
                    AppSnackbar.show(
                      context,
                      'Viaje iniciado: $succeeded/${activeBookings.length} pasajeros.',
                    );
                    _refresh();
                  },
                ),
              if (ride.isActive && hasAnyInProgress)
                _RideLevelActionCard(
                  icon: Icons.check_circle_rounded,
                  label: 'Finalizar viaje completo',
                  description:
                      'Marca el fin del viaje. Se liberaran los pagos a tu billetera.',
                  color: AppTheme.success,
                  onPressed: _completeRide,
                ),
              if (ride.isActive && !allPassengersBoarded && !hasAnyInProgress)
                _RideLevelActionCard(
                  icon: Icons.cancel_outlined,
                  label: 'Cancelar turno',
                  description:
                      'Se reembolsara a los pasajeros y podrias recibir un strike.',
                  color: AppTheme.danger,
                  outlined: true,
                  onPressed: () => _cancelRide(ride),
                ),
              if (bookings.isNotEmpty) ...[
                const SizedBox(height: 8),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 4, vertical: 8),
                  child: Text(
                    'PASAJEROS',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.subtle,
                      letterSpacing: 0.8,
                    ),
                  ),
                ),
                ...bookings.map(
                  (booking) => _PassengerCard(
                    booking: booking,
                    onAccept: () => _acceptBooking(booking),
                    onReject: () => _rejectBooking(booking),
                    onMarkArriving: () => _markArriving(booking),
                    onMarkArrived: () => _markArrived(booking),
                    onStartTrip: () => _startTrip(booking),
                    onCompleteTrip: () => _completeTrip(booking),
                    onReviewPassenger: () => _reviewPassenger(booking),
                    onFavoritePassenger: () =>
                        _toggleFavoritePassenger(booking),
                    isFavorite:
                        _favoritePassengerIds.contains(booking.passengerId),
                  ),
                ),
              ],
              if (bookings.isEmpty && ride.isActive) ...[
                const SizedBox(height: 32),
                const Center(
                  child: Column(
                    children: [
                      Icon(Icons.people_outline,
                          size: 48, color: AppTheme.subtle),
                      SizedBox(height: 8),
                      Text(
                        'Aun no hay pasajeros en este turno',
                        style: TextStyle(color: AppTheme.subtle),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 12),
              Card(
                color: AppTheme.errorBg,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Seguridad',
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Si hay emergencia, llama al ${AppConstants.emergencyPhoneCL} de inmediato.',
                        style: const TextStyle(color: AppTheme.danger),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        bottomNavigationBar: SafeArea(
          minimum: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () async {
                final uri = Uri.parse('tel:${AppConstants.emergencyPhoneCL}');
                if (await canLaunchUrl(uri)) {
                  await launchUrl(uri);
                } else {
                  if (!mounted) return;
                  AppSnackbar.show(
                    context,
                    'No se pudo realizar la llamada. Marca ${AppConstants.emergencyPhoneCL} manualmente.',
                    isError: true,
                  );
                }
              },
              style: OutlinedButton.styleFrom(
                foregroundColor: AppTheme.danger,
                side: const BorderSide(color: AppTheme.danger),
              ),
              icon: const Icon(Icons.emergency_outlined),
              label: const Text('Llamar emergencia'),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _cancelRide(Ride ride) async {
    final reasonController = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cancelar turno'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Se reembolsara a los pasajeros reservados y podrias recibir strike.',
            ),
            const SizedBox(height: 10),
            TextField(
              controller: reasonController,
              decoration: const InputDecoration(
                labelText: 'Motivo',
                hintText: 'Ej: emergencia mecanica',
              ),
              maxLines: 2,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Volver'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.danger,
              foregroundColor: Colors.white,
            ),
            child: const Text('Cancelar turno'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) {
      reasonController.dispose();
      return;
    }

    await _runBusy('Cancelando turno...', () async {
      try {
        await ref.read(driverRidesProvider.notifier).cancelRide(
              ride.id,
              reason: reasonController.text.trim().isEmpty
                  ? 'cancelled_by_driver'
                  : reasonController.text.trim(),
            );
        if (!mounted) return;
        AppSnackbar.show(context, 'Turno cancelado.');
      } catch (e) {
        if (!mounted) return;
        AppSnackbar.show(
          context,
          AppErrorMapper.toMessage(e,
              fallback: 'No pudimos cancelar el turno.'),
          isError: true,
        );
      } finally {
        reasonController.dispose();
      }
    });
  }
}

class _RideInfoHeader extends StatelessWidget {
  final Ride ride;

  const _RideInfoHeader({required this.ride});

  @override
  Widget build(BuildContext context) {
    final dateFmt =
        DateFormat('EEE d MMM, HH:mm', 'es').format(ride.departureAt);
    final priceFmt = NumberFormat.currency(
      locale: 'es_CL',
      symbol: '\$',
      decimalDigits: 0,
    ).format(ride.seatPrice);

    Color statusColor;
    String statusLabel;
    switch (ride.status) {
      case 'active':
        statusColor = AppTheme.success;
        statusLabel = 'Activo';
        break;
      case 'completed':
        statusColor = AppTheme.completedStatus;
        statusLabel = 'Completado';
        break;
      default:
        statusColor = AppTheme.danger;
        statusLabel = 'Cancelado';
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        ride.direction == RideDirection.toCampus
                            ? '${ride.originCommune} \u2192 Campus'
                            : 'Campus \u2192 ${ride.originCommune}',
                        style: const TextStyle(
                            fontWeight: FontWeight.w700, fontSize: 17),
                      ),
                      if (ride.universityName != null) ...[
                        const SizedBox(height: 2),
                        Text(
                          '${ride.universityName} \u00b7 ${ride.campusName ?? ''}',
                          style: const TextStyle(
                              color: AppTheme.subtle, fontSize: 13),
                        ),
                      ],
                    ],
                  ),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(20),
                    border:
                        Border.all(color: statusColor.withValues(alpha: 0.4)),
                  ),
                  child: Text(
                    statusLabel,
                    style: TextStyle(
                      color: statusColor,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
            const Divider(height: 24),
            Row(
              children: [
                const Icon(Icons.access_time, size: 16, color: AppTheme.subtle),
                const SizedBox(width: 6),
                Text(dateFmt,
                    style: const TextStyle(
                        fontWeight: FontWeight.w600, fontSize: 14)),
              ],
            ),
            if (ride.meetingPoint != null && ride.meetingPoint!.isNotEmpty) ...[
              const SizedBox(height: 6),
              Row(
                children: [
                  const Icon(Icons.location_on_outlined,
                      size: 16, color: AppTheme.subtle),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      ride.meetingPoint!,
                      style:
                          const TextStyle(color: AppTheme.subtle, fontSize: 13),
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 8),
            Row(
              children: [
                const Icon(Icons.event_seat_outlined,
                    size: 16, color: AppTheme.subtle),
                const SizedBox(width: 6),
                Text(
                  '${ride.seatsAvailable} de ${ride.seatsTotal} cupos libres',
                  style: const TextStyle(fontSize: 13),
                ),
                const Spacer(),
                Text(
                  '$priceFmt / asiento',
                  style: const TextStyle(
                      fontWeight: FontWeight.w600, fontSize: 14),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ProgressTracker extends StatelessWidget {
  final int acceptedCount;
  final int boardedCount;
  final int completedCount;
  final int totalBookings;

  const _ProgressTracker({
    required this.acceptedCount,
    required this.boardedCount,
    required this.completedCount,
    required this.totalBookings,
  });

  @override
  Widget build(BuildContext context) {
    if (totalBookings == 0) return const SizedBox.shrink();

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Progreso del viaje',
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
            ),
            const SizedBox(height: 12),
            _ProgressStep(
              label: 'Pasajeros aceptados',
              count: acceptedCount,
              total: totalBookings,
              done: acceptedCount >= totalBookings,
            ),
            _ProgressStep(
              label: 'Pasajeros abordo',
              count: boardedCount,
              total: totalBookings,
              done: boardedCount >= totalBookings,
            ),
            _ProgressStep(
              label: 'Viajes finalizados',
              count: completedCount,
              total: totalBookings,
              done: completedCount >= totalBookings,
              isLast: true,
            ),
          ],
        ),
      ),
    );
  }
}

class _ProgressStep extends StatelessWidget {
  final String label;
  final int count;
  final int total;
  final bool done;
  final bool isLast;

  const _ProgressStep({
    required this.label,
    required this.count,
    required this.total,
    required this.done,
    this.isLast = false,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          Icon(
            done ? Icons.check_circle : Icons.radio_button_unchecked,
            size: 18,
            color: done ? AppTheme.success : Colors.grey.shade400,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '$label ($count/$total)',
              style: TextStyle(
                fontSize: 13,
                color: done ? AppTheme.success : AppTheme.subtle,
                fontWeight: done ? FontWeight.w600 : FontWeight.w400,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PassengerCard extends StatelessWidget {
  final Booking booking;
  final VoidCallback? onAccept;
  final VoidCallback? onReject;
  final VoidCallback? onMarkArriving;
  final VoidCallback? onMarkArrived;
  final VoidCallback? onStartTrip;
  final VoidCallback? onCompleteTrip;
  final VoidCallback? onReviewPassenger;
  final VoidCallback? onFavoritePassenger;
  final bool isFavorite;

  const _PassengerCard({
    required this.booking,
    this.onAccept,
    this.onReject,
    this.onMarkArriving,
    this.onMarkArrived,
    this.onStartTrip,
    this.onCompleteTrip,
    this.onReviewPassenger,
    this.onFavoritePassenger,
    required this.isFavorite,
  });

  @override
  Widget build(BuildContext context) {
    final priceFmt = NumberFormat.currency(
      locale: 'es_CL',
      symbol: '\$',
      decimalDigits: 0,
    ).format(booking.amountTotal);

    final statusColor = _colorForDispatch(booking.dispatchStatus);
    final statusIcon = _iconForDispatch(booking.dispatchStatus);

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 0, vertical: 5),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 18,
                  backgroundColor: statusColor.withValues(alpha: 0.12),
                  child: Icon(statusIcon, color: statusColor, size: 20),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              booking.passengerName ?? 'Pasajero',
                              style: const TextStyle(
                                  fontWeight: FontWeight.w600, fontSize: 14),
                            ),
                          ),
                          if (isFavorite)
                            const Icon(Icons.favorite,
                                size: 16, color: AppTheme.favorite),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: statusColor.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                  color: statusColor.withValues(alpha: 0.4)),
                            ),
                            child: Text(
                              booking.dispatchLabel,
                              style: TextStyle(
                                color: statusColor,
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 3),
                      Text(
                        '$priceFmt retenido',
                        style: const TextStyle(
                            fontSize: 12, color: AppTheme.subtle),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (booking.passengerRating != null &&
                (booking.passengerRating ?? 0) > 0) ...[
              const SizedBox(height: 6),
              Text(
                'Rating: ${booking.passengerRating!.toStringAsFixed(1)} (${booking.passengerRatingCount ?? 0})',
                style: const TextStyle(fontSize: 11, color: AppTheme.subtle),
              ),
            ],
            BookingFlowButtons(
              booking: booking,
              onAccept: onAccept,
              onReject: onReject,
              onMarkArriving: onMarkArriving,
              onMarkArrived: onMarkArrived,
              onStartTrip: onStartTrip,
              onCompleteTrip: onCompleteTrip,
              onReview: onReviewPassenger,
              onFavorite: onFavoritePassenger,
              isFavorite: isFavorite,
            ),
          ],
        ),
      ),
    );
  }

  static Color _colorForDispatch(BookingDispatchStatus status) {
    switch (status) {
      case BookingDispatchStatus.reserved:
        return AppTheme.warning;
      case BookingDispatchStatus.accepted:
        return AppTheme.primary;
      case BookingDispatchStatus.driverArriving:
        return AppTheme.primary;
      case BookingDispatchStatus.driverArrived:
        return AppTheme.success;
      case BookingDispatchStatus.passengerBoarded:
        return AppTheme.success;
      case BookingDispatchStatus.inProgress:
        return AppTheme.completedStatus;
      case BookingDispatchStatus.completed:
        return AppTheme.completedStatus;
      case BookingDispatchStatus.cancelled:
        return AppTheme.danger;
      case BookingDispatchStatus.noShow:
        return AppTheme.warning;
    }
  }

  static IconData _iconForDispatch(BookingDispatchStatus status) {
    switch (status) {
      case BookingDispatchStatus.reserved:
        return Icons.access_time_outlined;
      case BookingDispatchStatus.accepted:
        return Icons.check_outlined;
      case BookingDispatchStatus.driverArriving:
        return Icons.route_outlined;
      case BookingDispatchStatus.driverArrived:
        return Icons.place_outlined;
      case BookingDispatchStatus.passengerBoarded:
        return Icons.person_outline;
      case BookingDispatchStatus.inProgress:
        return Icons.directions_car_outlined;
      case BookingDispatchStatus.completed:
        return Icons.check_circle_outline;
      case BookingDispatchStatus.cancelled:
        return Icons.cancel_outlined;
      case BookingDispatchStatus.noShow:
        return Icons.error_outline;
    }
  }
}

class _RideLevelActionCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String description;
  final Color color;
  final VoidCallback onPressed;
  final bool outlined;

  const _RideLevelActionCard({
    required this.icon,
    required this.label,
    required this.description,
    required this.color,
    required this.onPressed,
    this.outlined = false,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      color: color.withValues(alpha: 0.06),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(icon, color: color, size: 22),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    label,
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                      color: color,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              description,
              style: const TextStyle(fontSize: 12, color: AppTheme.subtle),
            ),
            const SizedBox(height: 10),
            outlined
                ? OutlinedButton(
                    onPressed: onPressed,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: color,
                      side: BorderSide(color: color),
                    ),
                    child: Text(label),
                  )
                : ElevatedButton.icon(
                    onPressed: onPressed,
                    icon: Icon(icon, size: 18),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: color,
                      foregroundColor: Colors.white,
                    ),
                    label: Text(label),
                  ),
          ],
        ),
      ),
    );
  }
}
