/**
 * Project: Turno
 * 
 * Project Owners: Cristobal Cordova, Carlos Ibarra, Agustin Puelma
 * Software Architecture & Code: Matias Toledo (@catalystxzr)
 * 
 * Description: Production-grade implementation for UDD carpooling system.
 * 
 * Copyright (c) 2026 Turno. All rights reserved.
 * This software is proprietary and confidential.
 */

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../app/theme.dart';
import '../../core/error_mapper.dart';
import '../../models/booking.dart';
import '../../models/enums.dart';
import '../../models/ride.dart';
import '../../providers/driver_rides_provider.dart';
import '../../services/favorites_service.dart';
import '../../services/review_service.dart';
import '../../shared/widgets/app_snackbar.dart';
import '../../shared/widgets/booking_flow_buttons.dart';
import '../../shared/widgets/decorative_background.dart';
import '../../shared/widgets/loading_overlay.dart';
import '../../shared/widgets/review_dialog.dart';

class DriverRidesScreen extends ConsumerStatefulWidget {
  const DriverRidesScreen({super.key});

  @override
  ConsumerState<DriverRidesScreen> createState() => _DriverRidesScreenState();
}

class _DriverRidesScreenState extends ConsumerState<DriverRidesScreen>
    with SingleTickerProviderStateMixin {
  final _reviewService = ReviewService();
  final _favoritesService = FavoritesService();
  late TabController _tabController;
  bool _busy = false;
  String? _busyMessage;
  Set<String> _favoritePassengerIds = <String>{};

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

  Future<void> _completeRideAction(Ride ride) async {
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
        await ref.read(driverRidesProvider.notifier).completeRide(ride.id);
        if (!mounted) return;
        AppSnackbar.show(context, 'Viaje completado.');
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
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(driverRidesProvider.notifier).load();
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
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
        debugPrint('[Turno] DriverRides: getMyFavorites failed: $e');
        if (!mounted) return;
        setState(() => _favoritePassengerIds = <String>{});
      }
    } catch (e) {
      if (!mounted) return;
      AppSnackbar.show(
        context,
        AppErrorMapper.toMessage(
          e,
          fallback: 'No pudimos cargar tus turnos publicados.',
        ),
        isError: true,
      );
    }
  }

  Future<void> _cancelRide(Ride ride) async {
    final reasonController = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cancelar turno publicado'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Se reembolsara a los pasajeros reservados y podrias recibir strike por cancelacion.',
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
        AppSnackbar.show(
          context,
          'Turno cancelado. Reembolsos aplicados y strike evaluado.',
        );
      } catch (e) {
        if (!mounted) return;
        AppSnackbar.show(
          context,
          AppErrorMapper.toMessage(
            e,
            fallback: 'No pudimos cancelar el turno en este momento.',
          ),
          isError: true,
        );
      } finally {
        reasonController.dispose();
      }
    });
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
          AppErrorMapper.toMessage(
            e,
            fallback: 'No pudimos aceptar la reserva.',
          ),
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

    await _runBusy('Rechazando reserva...', () async {
      try {
        await ref.read(driverRidesProvider.notifier).rejectBooking(
              booking.id,
              reason: reasonController.text.trim().isEmpty
                  ? null
                  : reasonController.text.trim(),
            );
        if (!mounted) return;
        AppSnackbar.show(context, 'Reserva rechazada y reembolsada.');
      } catch (e) {
        if (!mounted) return;
        AppSnackbar.show(
          context,
          AppErrorMapper.toMessage(
            e,
            fallback: 'No pudimos rechazar la reserva.',
          ),
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
        AppSnackbar.show(context, 'Estado actualizado: en camino.');
      } catch (e) {
        if (!mounted) return;
        AppSnackbar.show(
          context,
          AppErrorMapper.toMessage(
            e,
            fallback: 'No pudimos actualizar a en camino.',
          ),
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
        AppSnackbar.show(context, 'Estado actualizado: conductor llego.');
      } catch (e) {
        if (!mounted) return;
        AppSnackbar.show(
          context,
          AppErrorMapper.toMessage(
            e,
            fallback: 'No pudimos actualizar llegada.',
          ),
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
          AppErrorMapper.toMessage(
            e,
            fallback: 'No pudimos iniciar el viaje.',
          ),
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
      } catch (e) {
        if (!mounted) return;
        AppSnackbar.show(
          context,
          AppErrorMapper.toMessage(
            e,
            fallback: 'No pudimos finalizar el viaje.',
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
        await _load();
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

  void _openActiveRide(Ride ride) {
    context.push('/driver-ride/${ride.id}');
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(driverRidesProvider);
    final activeRides = state.rides.where((r) => r.isActive).toList();
    final pastRides = state.rides.where((r) => !r.isActive).toList();
    final pendingCount = state.bookings
        .where((b) =>
            b.isReserved && b.dispatchStatus == BookingDispatchStatus.reserved)
        .length;

    return LoadingOverlay(
      isLoading: _busy,
      message: _busyMessage,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Mis turnos'),
          actions: [
            Stack(
              children: [
                IconButton(
                  icon: const Icon(Icons.notifications_outlined),
                  onPressed: () => context.push('/notifications'),
                ),
                if (pendingCount > 0)
                  Positioned(
                    right: 6,
                    top: 6,
                    child: Container(
                      padding: const EdgeInsets.all(4),
                      decoration: const BoxDecoration(
                        color: AppTheme.danger,
                        shape: BoxShape.circle,
                      ),
                      constraints: const BoxConstraints(
                        minWidth: 18,
                        minHeight: 18,
                      ),
                      child: Text(
                        pendingCount > 99 ? '99+' : pendingCount.toString(),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
              ],
            ),
          ],
          bottom: TabBar(
            controller: _tabController,
            tabs: [
              Tab(text: 'Activos'),
              Tab(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('Pasajeros'),
                    if (pendingCount > 0) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 7, vertical: 2),
                        decoration: BoxDecoration(
                          color: AppTheme.danger,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          pendingCount.toString(),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
        body: DecorativeBackground(
          child: state.loading && state.errorMessage == null
              ? const Center(child: CircularProgressIndicator())
              : state.errorMessage != null
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(32),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.cloud_off,
                                size: 64, color: AppTheme.subtle),
                            const SizedBox(height: 12),
                            const Text(
                              'No pudimos cargar tus turnos',
                              style: TextStyle(
                                  fontWeight: FontWeight.w600, fontSize: 16),
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 8),
                            Text(
                              state.errorMessage!,
                              style: const TextStyle(
                                  color: AppTheme.subtle, fontSize: 12),
                              textAlign: TextAlign.center,
                              maxLines: 4,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 16),
                            ElevatedButton.icon(
                              onPressed: () {
                                ref
                                    .read(driverRidesProvider.notifier)
                                    .clearError();
                                _load();
                              },
                              icon: const Icon(Icons.refresh),
                              label: const Text('Reintentar'),
                            ),
                          ],
                        ),
                      ),
                    )
                  : TabBarView(
                      controller: _tabController,
                      children: [
                        if (activeRides.isEmpty && pastRides.isEmpty)
                          const _EmptyState(
                            message: 'No has publicado turnos aun',
                          )
                        else
                          RefreshIndicator(
                            onRefresh: _load,
                            child: ListView(
                              padding: const EdgeInsets.symmetric(vertical: 6),
                              children: [
                                 if (activeRides.isNotEmpty) ...[
                                  const _SectionHeader(title: 'Activos'),
                                  ...activeRides.map(
                                    (r) {
                                      final rideBookings = state.bookings
                                          .where((b) => b.rideId == r.id)
                                          .toList();
                                      final hasBoarded = rideBookings.any(
                                        (b) => b.isReserved && (
                                          b.dispatchStatus == BookingDispatchStatus.passengerBoarded ||
                                          b.dispatchStatus == BookingDispatchStatus.inProgress),
                                      );
                                      return _RideCard(
                                        ride: r,
                                        onCancel: hasBoarded ? null : () => _cancelRide(r),
                                        onComplete: () => _completeRideAction(r),
                                        onOpenActiveRide: () =>
                                            _openActiveRide(r),
                                      );
                                    },
                                  ),
                                ],
                                if (pastRides.isNotEmpty) ...[
                                  const _SectionHeader(title: 'Historial'),
                                  ...pastRides.map((r) => _RideCard(ride: r)),
                                ],
                              ],
                            ),
                          ),
                        if (state.bookings.isEmpty)
                          const _EmptyState(
                              message: 'Sin pasajeros registrados')
                        else
                          RefreshIndicator(
                            onRefresh: _load,
                            child: ListView.builder(
                              padding: const EdgeInsets.symmetric(vertical: 6),
                              itemCount: state.bookings.length,
                              itemBuilder: (ctx, i) {
                                final booking = state.bookings[i];
                                final rideActive = state.rides.any(
                                  (r) => r.id == booking.rideId && r.isActive,
                                );
                                return _PassengerBookingCard(
                                  booking: booking,
                                  onAccept: rideActive ? _acceptBooking : null,
                                  onReject: rideActive ? _rejectBooking : null,
                                  onMarkArriving: rideActive ? _markArriving : null,
                                  onMarkArrived: rideActive ? _markArrived : null,
                                  onStartTrip: rideActive ? _startTrip : null,
                                  onCompleteTrip: rideActive ? _completeTrip : null,
                                  onFavoritePassenger: _toggleFavoritePassenger,
                                  isFavoritePassenger: _favoritePassengerIds
                                      .contains(booking.passengerId),
                                   onReviewPassenger: _reviewPassenger,
                                );
                              },
                            ),
                          ),
                      ],
                    ),
        ),
      ),
    );
  }
}

class _RideCard extends StatelessWidget {
  final Ride ride;
  final VoidCallback? onCancel;
  final VoidCallback? onComplete;
  final VoidCallback? onOpenActiveRide;

  const _RideCard(
      {required this.ride,
      this.onCancel,
      this.onComplete,
      this.onOpenActiveRide});

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
      margin: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    ride.direction == RideDirection.toCampus
                        ? '${ride.originCommune} -> Campus'
                        : 'Campus -> ${ride.originCommune}',
                    style: const TextStyle(
                        fontWeight: FontWeight.w600, fontSize: 15),
                  ),
                ),
                _StatusBadge(label: statusLabel, color: statusColor),
              ],
            ),
            const SizedBox(height: 6),
            Text(dateFmt,
                style: const TextStyle(color: AppTheme.subtle, fontSize: 13)),
            if (ride.meetingPoint != null && ride.meetingPoint!.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                'Punto: ${ride.meetingPoint}',
                style: const TextStyle(fontSize: 12, color: AppTheme.subtle),
              ),
            ],
            const SizedBox(height: 4),
            Row(
              children: [
                Icon(Icons.event_seat_outlined,
                    size: 14, color: Colors.grey.shade600),
                const SizedBox(width: 4),
                Text(
                  '${ride.seatsAvailable} / ${ride.seatsTotal} cupos libres',
                  style: const TextStyle(fontSize: 13),
                ),
                const Spacer(),
                Text(
                  '$priceFmt / asiento',
                  style: const TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w500),
                ),
              ],
            ),
            if (ride.isActive && onOpenActiveRide != null) ...[
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: onOpenActiveRide,
                  icon: const Icon(Icons.list_alt_outlined),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primary,
                    foregroundColor: Colors.white,
                  ),
                  label: const Text('Gestionar viaje'),
                ),
              ),
            ],
            if (ride.isActive && onCancel != null) ...[
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: onCancel,
                  icon: const Icon(Icons.cancel_outlined),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppTheme.danger,
                    side: const BorderSide(color: AppTheme.danger),
                  ),
                  label: const Text('Cancelar turno'),
                ),
              ),
            ],
            if (ride.isActive && onComplete != null) ...[
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: onComplete,
                  icon: const Icon(Icons.check_circle_outline),
                  label: const Text('Finalizar viaje'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.success,
                    foregroundColor: Colors.white,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _PassengerBookingCard extends StatelessWidget {
  final Booking booking;
  final void Function(Booking)? onAccept;
  final void Function(Booking)? onReject;
  final void Function(Booking)? onMarkArriving;
  final void Function(Booking)? onMarkArrived;
  final void Function(Booking)? onStartTrip;
  final void Function(Booking)? onCompleteTrip;
  final void Function(Booking)? onFavoritePassenger;
  final bool isFavoritePassenger;
  final void Function(Booking)? onReviewPassenger;
  final void Function(Booking)? onReportNoShow;

  const _PassengerBookingCard({
    required this.booking,
    this.onAccept,
    this.onReject,
    this.onMarkArriving,
    this.onMarkArrived,
    this.onStartTrip,
    this.onCompleteTrip,
    this.onFavoritePassenger,
    required this.isFavoritePassenger,
    this.onReviewPassenger,
    this.onReportNoShow,
  });

  @override
  Widget build(BuildContext context) {
    final priceFmt = NumberFormat.currency(
      locale: 'es_CL',
      symbol: '\$',
      decimalDigits: 0,
    ).format(booking.amountTotal);

    final dateFmt = booking.rideDepartureAt != null
        ? DateFormat('EEE d MMM, HH:mm', 'es').format(booking.rideDepartureAt!)
        : '--';

    Color statusColor;
    String statusLabel;
    switch (booking.status) {
      case BookingStatus.reserved:
        statusColor = AppTheme.primary;
        statusLabel = 'Reservado';
        break;
      case BookingStatus.completed:
        statusColor = AppTheme.success;
        statusLabel = 'Completado';
        break;
      case BookingStatus.cancelled:
        statusColor = AppTheme.danger;
        statusLabel = 'Cancelado';
        break;
      case BookingStatus.noShow:
        statusColor = AppTheme.warning;
        statusLabel = 'No show';
        break;
    }

    final tile = ListTile(
      leading: CircleAvatar(
        backgroundColor: statusColor.withValues(alpha: 0.12),
        child: Icon(Icons.person_outline, color: statusColor, size: 20),
      ),
      title: Text(
        booking.passengerName ?? booking.rideOriginCommune ?? 'Turno',
        style: const TextStyle(fontWeight: FontWeight.w600),
      ),
      isThreeLine: true,
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(dateFmt,
              style: const TextStyle(fontSize: 12, color: AppTheme.subtle)),
          Text(
            booking.dispatchLabel,
            style: const TextStyle(
              fontSize: 11,
              color: AppTheme.primary,
              fontWeight: FontWeight.w600,
            ),
          ),
          if (booking.passengerVehiclePlate != null ||
              booking.passengerVehicleModel != null)
            Text(
              'Auto ${booking.passengerVehicleModel ?? '-'} · Patente ${booking.passengerVehiclePlate ?? '-'}',
              style: const TextStyle(fontSize: 11, color: AppTheme.subtle),
            ),
          if (booking.passengerRating != null)
            Text(
              'Rating ${booking.passengerRating!.toStringAsFixed(2)} (${booking.passengerRatingCount ?? 0})',
              style: const TextStyle(fontSize: 11, color: AppTheme.subtle),
            ),
        ],
      ),
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(priceFmt,
              style:
                  const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
          _StatusBadge(label: statusLabel, color: statusColor),
        ],
      ),
    );

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            tile,
            BookingFlowButtons(
              booking: booking,
              onAccept: onAccept == null ? null : () => onAccept!(booking),
              onReject: onReject == null ? null : () => onReject!(booking),
              onMarkArriving: onMarkArriving == null
                  ? null
                  : () => onMarkArriving!(booking),
              onMarkArrived:
                  onMarkArrived == null ? null : () => onMarkArrived!(booking),
              onStartTrip:
                  onStartTrip == null ? null : () => onStartTrip!(booking),
              onCompleteTrip: onCompleteTrip == null
                  ? null
                  : () => onCompleteTrip!(booking),
              onReview: onReviewPassenger == null
                  ? null
                  : () => onReviewPassenger!(booking),
              onFavorite: onFavoritePassenger == null
                  ? null
                  : () => onFavoritePassenger!(booking),
              isFavorite: isFavoritePassenger,
              onReportNoShow: onReportNoShow == null
                  ? null
                  : () => onReportNoShow!(booking),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  final String label;
  final Color color;

  const _StatusBadge({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Text(
        label,
        style:
            TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w600),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;

  const _SectionHeader({required this.title});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 4),
      child: Text(
        title,
        style: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: AppTheme.subtle,
          letterSpacing: 0.8,
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final String message;

  const _EmptyState({required this.message});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.drive_eta, size: 64, color: Colors.grey.shade300),
          const SizedBox(height: 12),
          Text(message, style: const TextStyle(color: AppTheme.subtle)),
        ],
      ),
    );
  }
}
