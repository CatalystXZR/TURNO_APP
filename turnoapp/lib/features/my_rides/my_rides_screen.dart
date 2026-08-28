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
import '../../core/constants.dart';
import '../../core/error_mapper.dart';
import '../../models/booking.dart';
import '../../models/enums.dart';
import '../../providers/my_rides_provider.dart';
import '../../services/favorites_service.dart';
import '../../services/report_service.dart';
import '../../services/review_service.dart';
import '../../shared/widgets/app_snackbar.dart';
import '../../shared/widgets/decorative_background.dart';
import '../../shared/widgets/loading_overlay.dart';
import '../../shared/widgets/report_user_dialog.dart';
import '../../shared/widgets/review_dialog.dart';

class MyRidesScreen extends ConsumerStatefulWidget {
  const MyRidesScreen({super.key});

  @override
  ConsumerState<MyRidesScreen> createState() => _MyRidesScreenState();
}

class _MyRidesScreenState extends ConsumerState<MyRidesScreen>
    with SingleTickerProviderStateMixin {
  final _reviewService = ReviewService();
  final _favoritesService = FavoritesService();
  final _reportService = ReportService();
  late TabController _tabController;
  bool _busy = false;
  String? _busyMessage;
  Set<String> _favoriteDriverIds = <String>{};
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
    _tabController = TabController(length: 2, vsync: this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(myRidesProvider.notifier).load();
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      await ref.read(myRidesProvider.notifier).load();
      try {
        final favorites = await _favoritesService.getMyFavorites();
        if (!mounted) return;
        setState(() {
          _favoriteDriverIds = favorites
              .where((item) => item.roleMode == RoleMode.driver)
              .map((item) => item.userId)
              .toSet();
        });
      } catch (e) {
        debugPrint('[Turno] MyRides: check favorites failed: $e');
        if (!mounted) return;
        setState(() => _favoriteDriverIds = <String>{});
      }

      if (!mounted) return;
      _checkArrivalOnLoad();
    } catch (e) {
      if (!mounted) return;
      AppSnackbar.show(
        context,
        AppErrorMapper.toMessage(e,
            fallback: 'No pudimos cargar tus reservas.'),
        isError: true,
      );
    }
  }

  void _checkArrivalOnLoad() {
    if (_navigatedToArrival) return;
    final state = ref.read(myRidesProvider);
    final hasCompletedTrip = state.bookings.any(
      (b) =>
          b.isCompleted && b.dispatchStatus == BookingDispatchStatus.completed,
    );
    if (hasCompletedTrip && !_hasShownArrivalPrompt) {
      _hasShownArrivalPrompt = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
      final completedBooking = state.bookings
          .firstWhere(
            (b) => b.isCompleted && b.dispatchStatus == BookingDispatchStatus.completed,
            orElse: () => state.bookings.first,
          );
        context.push('/arrival?bookingId=${completedBooking.id}');
      });
    }
  }

  bool _hasShownArrivalPrompt = false;

  Future<void> _confirmBoarding(Booking booking) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Confirmar abordaje'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              booking.dispatchStatus == BookingDispatchStatus.driverArrived
                  ? 'El conductor marco llegada. Confirma solo si realmente abordaste.'
                  : 'Confirma abordaje solo cuando subas al auto. Esto habilita inicio de viaje.',
              style: const TextStyle(fontSize: 14),
            ),
            const SizedBox(height: 12),
            Text(
              'Monto retenido: \$${booking.amountTotal}',
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
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
              backgroundColor: AppTheme.success,
              foregroundColor: Colors.white,
            ),
            child: const Text('ME SUBI AL AUTO'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    await _runBusy('Confirmando abordaje...', () async {
      try {
        await ref.read(myRidesProvider.notifier).confirmBoarding(booking.id);
        if (!mounted) return;
        AppSnackbar.show(
          context,
          'Abordaje confirmado. El conductor puede iniciar viaje.',
        );
      } catch (e) {
        if (!mounted) return;
        AppSnackbar.show(
          context,
          AppErrorMapper.toMessage(
            e,
            fallback: 'No pudimos confirmar el abordaje.',
          ),
          isError: true,
        );
      }
    });
  }

  Future<void> _cancelBooking(Booking booking) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cancelar reserva'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Se cancelara tu reserva y los fondos seran devueltos a tu billetera.',
              style: TextStyle(fontSize: 14),
            ),
            const SizedBox(height: 12),
            Text(
              'Se devolveran \$${booking.amountTotal} a tu saldo.',
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
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
            child: const Text('Cancelar reserva'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    await _runBusy('Cancelando reserva...', () async {
      try {
        await ref.read(myRidesProvider.notifier).cancelBooking(booking.id);
        if (!mounted) return;
        AppSnackbar.show(context, 'Reserva cancelada. Fondos devueltos.');
      } catch (e) {
        if (!mounted) return;
        AppSnackbar.show(
          context,
          AppErrorMapper.toMessage(
            e,
            fallback: 'No pudimos cancelar la reserva.',
          ),
          isError: true,
        );
      }
    });
  }

  Future<void> _reportNoShow(Booking booking) async {
    final notesController = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Reportar conductor no-show'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Debes esperar al menos ${AppConstants.waitTimeMinutesNoShow} minutos en el punto de encuentro antes de reportar.',
            ),
            const SizedBox(height: 10),
            TextField(
              controller: notesController,
              decoration: const InputDecoration(
                labelText: 'Notas (opcional)',
                hintText: 'Ej: espere en el punto acordado y no llego',
              ),
              maxLines: 3,
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
            child: const Text('Reportar no-show'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) {
      notesController.dispose();
      return;
    }

    await _runBusy('Reportando no-show...', () async {
      try {
        await ref.read(myRidesProvider.notifier).reportNoShow(
              booking.id,
              notes: notesController.text.trim().isEmpty
                  ? null
                  : notesController.text.trim(),
            );
        if (!mounted) return;
        AppSnackbar.show(
          context,
          'Reporte enviado. Se aplico reembolso y evaluacion de strike.',
        );
      } catch (e) {
        if (!mounted) return;
        AppSnackbar.show(
          context,
          AppErrorMapper.toMessage(
            e,
            fallback: 'No pudimos reportar no-show en este momento.',
          ),
          isError: true,
        );
      } finally {
        notesController.dispose();
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
        setState(() {
          if (isFav) {
            _favoriteDriverIds.add(driverId);
          } else {
            _favoriteDriverIds.remove(driverId);
          }
        });
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

  Future<void> _reportDriver(Booking booking) async {
    final driverId = booking.driverId;
    if (driverId == null) return;

    await showDialog<bool>(
      context: context,
      builder: (_) => ReportUserDialog(
        reportedUserId: driverId,
        reportedUserName: booking.driverName ?? 'Conductor',
        bookingId: booking.id,
      ),
    );
  }

  Future<void> _blockDriver(Booking booking) async {
    final driverId = booking.driverId;
    if (driverId == null) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Bloquear conductor'),
        content: Text(
          'Al bloquear a ${booking.driverName ?? 'este conductor'}, no podran interactuar entre si.',
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
            child: const Text('Bloquear'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    await _runBusy('Bloqueando...', () async {
      try {
        await _reportService.blockUser(driverId);
        if (!mounted) return;
        AppSnackbar.show(context, 'Conductor bloqueado.');
        _load();
      } catch (e) {
        if (!mounted) return;
        AppSnackbar.show(
          context,
          'No pudimos bloquear al conductor.',
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
          builder: (_) => ReviewDialog(
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
        await _load();
        if (!mounted) return;
        AppSnackbar.show(context, 'Resena publicada correctamente.');
      } catch (e) {
        if (!mounted) return;
        AppSnackbar.show(
          context,
          AppErrorMapper.toMessage(
            e,
            fallback: 'No pudimos publicar tu resena.',
          ),
          isError: true,
        );
      }
    });
  }

  void _openActiveTrip(Booking booking) {
    context.push('/active-trip/${booking.id}');
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(myRidesProvider);
    final active = state.bookings.where((b) => b.isReserved).toList();
    final history = state.bookings.where((b) => !b.isReserved).toList();

    return LoadingOverlay(
      isLoading: _busy,
      message: _busyMessage,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Mis reservas'),
          bottom: TabBar(
            controller: _tabController,
            tabs: const [
              Tab(text: 'Activas'),
              Tab(text: 'Historial'),
            ],
          ),
        ),
        body: DecorativeBackground(
          child: state.loading
              ? const Center(child: CircularProgressIndicator())
              : RefreshIndicator(
                  onRefresh: _load,
                  child: TabBarView(
                    controller: _tabController,
                    children: [
                      active.isEmpty
                          ? const _EmptyState(
                              message: 'No tienes reservas activas',
                            )
                          : ListView.builder(
                              padding: const EdgeInsets.symmetric(vertical: 6),
                              itemCount: active.length,
                              itemBuilder: (ctx, i) => _BookingCard(
                                booking: active[i],
                                onConfirmBoarding: _confirmBoarding,
                                onCancelBooking: _cancelBooking,
                                onReportNoShow: _reportNoShow,
                                onOpenActiveTrip: _openActiveTrip,
                                onFavoriteDriver: _toggleFavoriteDriver,
                                isFavoriteDriver: _favoriteDriverIds
                                    .contains(active[i].driverId),
                                onReviewDriver: _reviewDriver,
                                onReportDriver: _reportDriver,
                                onBlockDriver: _blockDriver,
                              ),
                            ),
                      history.isEmpty
                          ? const _EmptyState(message: 'Sin historial aun')
                          : ListView.builder(
                              padding: const EdgeInsets.symmetric(vertical: 6),
                              itemCount: history.length,
                              itemBuilder: (ctx, i) => _BookingCard(
                                booking: history[i],
                                onConfirmBoarding: null,
                                onOpenActiveTrip: null,
                                onFavoriteDriver: _toggleFavoriteDriver,
                                isFavoriteDriver: _favoriteDriverIds
                                    .contains(history[i].driverId),
                                onReviewDriver: _reviewDriver,
                                onReportDriver: _reportDriver,
                                onBlockDriver: _blockDriver,
                              ),
                            ),
                    ],
                  ),
                ),
        ),
      ),
    );
  }
}

class _BookingCard extends StatelessWidget {
  final Booking booking;
  final void Function(Booking)? onConfirmBoarding;
  final void Function(Booking)? onCancelBooking;
  final void Function(Booking)? onReportNoShow;
  final void Function(Booking)? onOpenActiveTrip;
  final void Function(Booking)? onFavoriteDriver;
  final bool isFavoriteDriver;
  final void Function(Booking)? onReviewDriver;
  final void Function(Booking)? onReportDriver;
  final void Function(Booking)? onBlockDriver;

  const _BookingCard({
    required this.booking,
    this.onConfirmBoarding,
    this.onCancelBooking,
    this.onReportNoShow,
    this.onOpenActiveTrip,
    this.onFavoriteDriver,
    required this.isFavoriteDriver,
    this.onReviewDriver,
    this.onReportDriver,
    this.onBlockDriver,
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

    final dispatchLabel = booking.dispatchLabel;
    final dispatchColor = switch (booking.dispatchStatus) {
      BookingDispatchStatus.reserved => AppTheme.subtle,
      BookingDispatchStatus.accepted => AppTheme.primary,
      BookingDispatchStatus.driverArriving => AppTheme.primary,
      BookingDispatchStatus.driverArrived => AppTheme.success,
      BookingDispatchStatus.passengerBoarded => AppTheme.success,
      BookingDispatchStatus.inProgress => AppTheme.success,
      BookingDispatchStatus.completed => AppTheme.completedStatus,
      BookingDispatchStatus.cancelled => AppTheme.danger,
      BookingDispatchStatus.noShow => AppTheme.warning,
    };

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
                    booking.rideOriginCommune != null
                        ? '${booking.rideOriginCommune} · ${booking.campusName ?? ''}'
                        : 'Turno',
                    style: const TextStyle(
                        fontWeight: FontWeight.w600, fontSize: 15),
                  ),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
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
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(dateFmt,
                style: const TextStyle(color: AppTheme.subtle, fontSize: 13)),
            const SizedBox(height: 4),
            Text(
              dispatchLabel,
              style: TextStyle(
                fontSize: 12,
                color: dispatchColor,
                fontWeight: FontWeight.w700,
              ),
            ),
            if (booking.driverName != null ||
                booking.driverVehiclePlate != null) ...[
              const SizedBox(height: 4),
              Text(
                'Conductor: ${booking.driverName ?? '-'} · Auto ${booking.driverVehicleModel ?? '-'} · Patente ${booking.driverVehiclePlate ?? '-'}',
                style: const TextStyle(fontSize: 12, color: AppTheme.subtle),
              ),
            ],
            if ((booking.driverRating ?? 0) > 0) ...[
              const SizedBox(height: 4),
              Text(
                'Rating conductor: ${(booking.driverRating ?? 5).toStringAsFixed(2)} (${booking.driverRatingCount ?? 0})',
                style: const TextStyle(fontSize: 12, color: AppTheme.subtle),
              ),
            ],
            if (booking.isReserved && onOpenActiveTrip != null) ...[
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () => onOpenActiveTrip!(booking),
                  icon: const Icon(Icons.local_taxi_outlined),
                  label: const Text('Abrir viaje activo'),
                ),
              ),
            ],
            const SizedBox(height: 6),
            Text('Monto retenido: $priceFmt',
                style: const TextStyle(fontSize: 13)),
            if (booking.canPassengerConfirmBoarding &&
                onConfirmBoarding != null) ...[
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton.icon(
                  onPressed: () => onConfirmBoarding!(booking),
                  icon: const Icon(Icons.directions_car),
                  label: const Text(
                    'ME SUBI AL AUTO',
                    style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.success,
                    foregroundColor: Colors.white,
                  ),
                ),
              ),
            ],
            if (booking.isCompleted &&
                booking.driverId != null &&
                onReviewDriver != null) ...[
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () => onReviewDriver!(booking),
                  icon: const Icon(Icons.star_outline),
                  label: const Text('Calificar conductor'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primary,
                    foregroundColor: Colors.white,
                  ),
                ),
              ),
            ],
            if (booking.driverId != null && onFavoriteDriver != null) ...[
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () => onFavoriteDriver!(booking),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: isFavoriteDriver
                        ? AppTheme.favorite
                        : Colors.white,
                    foregroundColor:
                        isFavoriteDriver ? Colors.white : AppTheme.primary,
                  ),
                  icon: Icon(
                    isFavoriteDriver ? Icons.favorite : Icons.favorite_outline,
                  ),
                  label: Text(
                    isFavoriteDriver
                        ? 'Conductor favorito'
                        : 'Agregar conductor a favoritos',
                  ),
                ),
              ),
            ],
            if (booking.isReserved &&
                booking.dispatchStatus != BookingDispatchStatus.inProgress &&
                booking.dispatchStatus !=
                    BookingDispatchStatus.passengerBoarded &&
                onCancelBooking != null) ...[
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                height: 40,
                child: OutlinedButton(
                  onPressed: () => onCancelBooking!(booking),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppTheme.danger,
                    side: const BorderSide(color: AppTheme.danger),
                  ),
                  child: const Text('Cancelar reserva'),
                ),
              ),
            ],
            if (booking.isReserved &&
                (booking.dispatchStatus ==
                        BookingDispatchStatus.driverArrived) &&
                onReportNoShow != null) ...[
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                height: 40,
                child: OutlinedButton.icon(
                  onPressed: () => onReportNoShow!(booking),
                  icon: const Icon(Icons.warning_amber_outlined),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppTheme.warning,
                    side: const BorderSide(color: AppTheme.warning),
                  ),
                  label: const Text('Conductor no llego (no-show)'),
                ),
              ),
            ],
            if (booking.driverId != null &&
                (onReportDriver != null || onBlockDriver != null)) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  if (onReportDriver != null) ...[
                    Expanded(
                      child: SizedBox(
                        height: 36,
                        child: OutlinedButton.icon(
                          onPressed: () => onReportDriver!(booking),
                          icon: const Icon(Icons.flag_outlined, size: 14),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppTheme.warning,
                            side: const BorderSide(color: AppTheme.warning),
                            textStyle: const TextStyle(fontSize: 11),
                          ),
                          label: const Text('Reportar'),
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                  ],
                  if (onBlockDriver != null) ...[
                    Expanded(
                      child: SizedBox(
                        height: 36,
                        child: OutlinedButton.icon(
                          onPressed: () => onBlockDriver!(booking),
                          icon: const Icon(Icons.block_outlined, size: 14),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppTheme.danger,
                            side: const BorderSide(color: AppTheme.danger),
                            textStyle: const TextStyle(fontSize: 11),
                          ),
                          label: const Text('Bloquear'),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ],
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
          Icon(Icons.confirmation_num_outlined,
              size: 64, color: Colors.grey.shade300),
          const SizedBox(height: 12),
          Text(message, style: const TextStyle(color: AppTheme.subtle)),
        ],
      ),
    );
  }
}
