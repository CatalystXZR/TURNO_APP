import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme.dart';
import '../../core/constants.dart';
import '../../core/error_mapper.dart';
import '../../models/booking.dart';
import '../../models/enums.dart';
import '../../providers/my_rides_provider.dart';
import '../../services/favorites_service.dart';
import '../../services/review_service.dart';
import '../../shared/widgets/app_snackbar.dart';
import '../../shared/widgets/loading_overlay.dart';
import '../../shared/widgets/review_dialog.dart';

class ActiveTripScreen extends ConsumerStatefulWidget {
  final String bookingId;

  const ActiveTripScreen({super.key, required this.bookingId});

  @override
  ConsumerState<ActiveTripScreen> createState() => _ActiveTripScreenState();
}

class _ActiveTripScreenState extends ConsumerState<ActiveTripScreen> {
  final _reviewService = ReviewService();
  final _favoritesService = FavoritesService();
  bool _busy = false;
  String? _busyMessage;
  bool _isFavoriteDriver = false;
  bool _navigatedToArrival = false;

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

  Booking? _bookingFromState(MyRidesState state) {
    try {
      return state.bookings.firstWhere((b) => b.id == widget.bookingId);
    } catch (_) {
      return null;
    }
  }

  Future<void> _checkArrival(Booking booking) async {
    if (_navigatedToArrival) return;
    if (booking.isCompleted &&
        booking.dispatchStatus == BookingDispatchStatus.completed) {
      _navigatedToArrival = true;
      if (!mounted) return;
      await Future.delayed(const Duration(milliseconds: 500));
      if (!mounted) return;
      context.go('/arrival');
    }
  }

  Future<void> _refresh() async {
    try {
      await ref.read(myRidesProvider.notifier).load();
      final booking = _bookingFromState(ref.read(myRidesProvider));
      if (booking != null) {
        if (booking.driverId != null) {
          try {
            final isFav = await _favoritesService.isFavorite(booking.driverId!);
            if (!mounted) return;
            setState(() => _isFavoriteDriver = isFav);
          } catch (_) {
            if (!mounted) return;
            setState(() => _isFavoriteDriver = false);
          }
        }
        if (!mounted) return;
        _checkArrival(booking);
      }
    } catch (e) {
      if (!mounted) return;
      AppSnackbar.show(
        context,
        AppErrorMapper.toMessage(
          e,
          fallback: 'No pudimos actualizar el estado del viaje.',
        ),
        isError: true,
      );
    }
  }

  Future<void> _confirmBoarding(Booking booking) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Confirmar abordaje'),
        content: const Text(
          'Confirma solo cuando estes dentro del auto. Esto habilita el inicio del viaje.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Confirmar abordaje'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    await _runBusy('Confirmando abordaje...', () async {
      try {
        await ref.read(myRidesProvider.notifier).confirmBoarding(booking.id);
        if (!mounted) return;
        AppSnackbar.show(context, 'Abordaje confirmado.');
      } catch (e) {
        if (!mounted) return;
        AppSnackbar.show(
          context,
          AppErrorMapper.toMessage(
            e,
            fallback: 'No pudimos confirmar tu abordaje.',
          ),
          isError: true,
        );
      }
    });
  }

  Future<void> _toggleFavoriteDriver(Booking booking) async {
    final driverId = booking.driverId;
    if (driverId == null) return;
    await _runBusy('Actualizando favoritos...', () async {
      try {
        final isFav = await _favoritesService.toggleFavorite(driverId);
        if (!mounted) return;
        setState(() => _isFavoriteDriver = isFav);
        AppSnackbar.show(
          context,
          isFav
              ? 'Conductor agregado a favoritos.'
              : 'Conductor eliminado de favoritos.',
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

  Future<void> _reviewDriver(Booking booking) async {
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
            title: 'Calificar conductor',
            subtitle:
                'Tu referencia sera publica para ayudar a otros pasajeros.',
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

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(myRidesProvider);
    final booking = _bookingFromState(state);
    if (booking == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Viaje activo')),
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('No encontramos este viaje.'),
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

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _checkArrival(booking);
    });

    const flowOrder = <BookingDispatchStatus>[
      BookingDispatchStatus.reserved,
      BookingDispatchStatus.accepted,
      BookingDispatchStatus.driverArriving,
      BookingDispatchStatus.driverArrived,
      BookingDispatchStatus.passengerBoarded,
      BookingDispatchStatus.inProgress,
      BookingDispatchStatus.completed,
    ];
    final currentFlowIndex = flowOrder.indexOf(booking.dispatchStatus);
    bool reached(BookingDispatchStatus status) {
      final target = flowOrder.indexOf(status);
      if (target < 0 || currentFlowIndex < 0) return false;
      return currentFlowIndex >= target;
    }

    final statusItems = <_StatusStep>[
      _StatusStep(
        icon: Icons.check_circle_outline,
        label: 'Reserva creada',
        subtitle: 'Esperando confirmacion del conductor',
        done: true,
      ),
      _StatusStep(
        icon: Icons.person_add_outlined,
        label: 'Te han confirmado el Ride!',
        subtitle: 'El conductor acepto tu reserva',
        done: reached(BookingDispatchStatus.accepted),
      ),
      _StatusStep(
        icon: Icons.route_outlined,
        label: 'El rider va en camino!',
        subtitle: 'Se dirige al punto de encuentro',
        done: reached(BookingDispatchStatus.driverArriving),
      ),
      _StatusStep(
        icon: Icons.place_outlined,
        label: 'El rider ha llegado!',
        subtitle: 'Ya esta en el punto de encuentro',
        done: reached(BookingDispatchStatus.driverArrived),
        highlight: true,
      ),
      _StatusStep(
        icon: Icons.directions_car_outlined,
        label: 'Ya estas abordo',
        subtitle: 'Viaje en curso',
        done: reached(BookingDispatchStatus.passengerBoarded),
      ),
      _StatusStep(
        icon: Icons.navigation_outlined,
        label: 'Viaje en curso',
        subtitle: 'Viaje en curso',
        done: reached(BookingDispatchStatus.inProgress),
        highlight: true,
      ),
      _StatusStep(
        icon: Icons.flag_outlined,
        label: 'Viaje finalizado',
        subtitle: 'Llegaste a destino',
        done: reached(BookingDispatchStatus.completed),
        highlight: true,
      ),
    ];

    final canConfirmBoarding = booking.canPassengerConfirmBoarding;

    return LoadingOverlay(
      isLoading: _busy,
      message: _busyMessage,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Viaje activo'),
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
              if (booking.dispatchStatus == BookingDispatchStatus.cancelled ||
                  booking.dispatchStatus == BookingDispatchStatus.noShow) ...[
                Card(
                  color: const Color(0xFFFFF3F6),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Text(
                      booking.dispatchStatus == BookingDispatchStatus.cancelled
                          ? 'Este viaje fue cancelado.'
                          : 'Este viaje fue marcado como no-show.',
                      style: const TextStyle(
                        color: AppTheme.danger,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
              ],
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        booking.dispatchLabel,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: AppTheme.primary,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        '${booking.rideOriginCommune ?? '-'} · ${booking.campusName ?? '-'}',
                        style: const TextStyle(color: AppTheme.subtle),
                      ),
                      if (booking.driverName != null) ...[
                        const SizedBox(height: 6),
                        Text(
                          'Conductor: ${booking.driverName}',
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                      ],
                      if (booking.driverVehicleModel != null ||
                          booking.driverVehiclePlate != null)
                        Text(
                          'Auto ${booking.driverVehicleModel ?? '-'} · Patente ${booking.driverVehiclePlate ?? '-'}',
                          style: const TextStyle(color: AppTheme.subtle),
                        ),
                      if (booking.driverEmergencyContact != null) ...[
                        const SizedBox(height: 4),
                        Text(
                          'Contacto conductor: ${booking.driverEmergencyContact}',
                          style: const TextStyle(color: AppTheme.subtle),
                        ),
                      ],
                      if ((booking.driverRating ?? 0) > 0) ...[
                        const SizedBox(height: 4),
                        Text(
                          'Rating ${(booking.driverRating ?? 5).toStringAsFixed(2)} (${booking.driverRatingCount ?? 0})',
                          style: const TextStyle(color: AppTheme.subtle),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Progreso del viaje',
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 10),
                      ...statusItems.map(
                        (step) => Padding(
                          padding: const EdgeInsets.symmetric(vertical: 5),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Container(
                                width: 28,
                                height: 28,
                                decoration: BoxDecoration(
                                  color: step.done
                                      ? (step.highlight
                                              ? AppTheme.primary
                                              : const Color(0xFF178E68))
                                          .withValues(alpha: 0.12)
                                      : const Color(0xFF9AA8B5)
                                          .withValues(alpha: 0.1),
                                  shape: BoxShape.circle,
                                ),
                                child: Icon(
                                  step.done ? Icons.check_circle : step.icon,
                                  size: 16,
                                  color: step.done
                                      ? (step.highlight
                                          ? AppTheme.primary
                                          : const Color(0xFF178E68))
                                      : const Color(0xFF9AA8B5),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      step.label,
                                      style: TextStyle(
                                        fontSize: 13,
                                        fontWeight: step.done
                                            ? FontWeight.w600
                                            : FontWeight.w400,
                                        color: step.done
                                            ? (step.highlight
                                                ? const Color(0xFF178E68)
                                                : Colors.black87)
                                            : const Color(0xFF9AA8B5),
                                      ),
                                    ),
                                    const SizedBox(height: 1),
                                    Text(
                                      step.subtitle,
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: step.done
                                            ? AppTheme.subtle
                                            : const Color(0xFF9AA8B5),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Card(
                color: const Color(0xFFFFF3F6),
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
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (canConfirmBoarding) ...[
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: () => _confirmBoarding(booking),
                    icon: const Icon(Icons.directions_car),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF178E68),
                      foregroundColor: Colors.white,
                    ),
                    label: const Text('ME SUBI AL AUTO'),
                  ),
                ),
                const SizedBox(height: 8),
              ],
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () => _toggleFavoriteDriver(booking),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _isFavoriteDriver
                        ? const Color(0xFFFF5A7A)
                        : Colors.white,
                    foregroundColor:
                        _isFavoriteDriver ? Colors.white : AppTheme.primary,
                  ),
                  icon: Icon(
                    _isFavoriteDriver ? Icons.favorite : Icons.favorite_outline,
                  ),
                  label: Text(
                    _isFavoriteDriver
                        ? 'Conductor favorito'
                        : 'Agregar conductor a favoritos',
                  ),
                ),
              ),
              if (booking.isCompleted) ...[
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: () => _reviewDriver(booking),
                    icon: const Icon(Icons.star_outline),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.primary,
                      foregroundColor: Colors.white,
                    ),
                    label: const Text('Calificar conductor'),
                  ),
                ),
              ],
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () {
                    AppSnackbar.show(
                      context,
                      'Emergencia: llama al ${AppConstants.emergencyPhoneCL}',
                      isError: true,
                    );
                  },
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppTheme.danger,
                    side: const BorderSide(color: AppTheme.danger),
                  ),
                  icon: const Icon(Icons.emergency_outlined),
                  label: const Text('Boton de emergencia'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatusStep {
  final IconData icon;
  final String label;
  final String subtitle;
  final bool done;
  final bool highlight;

  const _StatusStep({
    required this.icon,
    required this.label,
    required this.subtitle,
    required this.done,
    this.highlight = false,
  });
}
