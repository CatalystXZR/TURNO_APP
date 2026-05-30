/**
 *
 * Project: Turno
 *
 * Original Concept: Agustín Puelma, Cristobal Cordova, Carlos Ibarra
 *
 * Software Architecture & Code: Matías Toledo (catalystxzr)
 *
 * Description: Production-grade implementation for UDD carpooling system.
 *
 * Copyright (c) 2026. All rights reserved.
 *
 */

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../app/theme.dart';
import '../../core/constants.dart';
import '../../core/error_mapper.dart';
import '../../models/enums.dart';
import '../../models/ride.dart';
import '../../models/user_profile.dart';
import '../../services/ride_service.dart';
import '../../services/booking_service.dart';
import '../../services/profile_service.dart';
import '../../services/wallet_service.dart';
import '../../models/wallet.dart';
import '../../models/user_review.dart';
import '../../services/favorites_service.dart';
import '../../services/report_service.dart';
import '../../services/review_service.dart';
import '../../shared/widgets/app_snackbar.dart';
import '../../shared/widgets/decorative_background.dart';
import '../../shared/widgets/loading_overlay.dart';
import '../../shared/widgets/report_user_dialog.dart';

class BookingScreen extends StatefulWidget {
  final String rideId;
  const BookingScreen({super.key, required this.rideId});

  @override
  State<BookingScreen> createState() => _BookingScreenState();
}

class _BookingScreenState extends State<BookingScreen> {
  final _rideService = RideService();
  final _bookingService = BookingService();
  final _walletService = WalletService();
  final _profileService = ProfileService();
  final _reviewService = ReviewService();
  final _favoritesService = FavoritesService();
  final _reportService = ReportService();

  Ride? _ride;
  Wallet? _wallet;
  UserProfile? _driverProfile;
  List<UserReview> _driverReviews = const [];
  bool _isFavoriteDriver = false;
  bool _favoriteLoading = false;
  bool _loading = true;
  bool _booking = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final results = await Future.wait([
        _rideService.getRideById(widget.rideId),
        _walletService.getWallet(),
      ]);
      final ride = results[0] as Ride?;
      UserProfile? driverProfile;
      List<UserReview> reviews = const [];
      bool isFavorite = false;
      if (ride != null) {
        driverProfile = await _profileService.getProfileById(ride.driverId);
        reviews = await _reviewService.getPublicUserReviews(ride.driverId);
        isFavorite = await _favoritesService.isFavorite(ride.driverId);
      }
      if (mounted) {
        setState(() {
          _ride = ride;
          _wallet = results[1] as Wallet?;
          _driverProfile = driverProfile;
          _driverReviews = reviews;
          _isFavoriteDriver = isFavorite;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
        AppSnackbar.show(
          context,
          AppErrorMapper.toMessage(
            e,
            fallback: 'No pudimos cargar el detalle del turno.',
          ),
          isError: true,
        );
      }
    }
  }

  Future<void> _toggleDriverFavorite() async {
    final ride = _ride;
    if (ride == null || _favoriteLoading) return;

    setState(() => _favoriteLoading = true);
    try {
      final next = await _favoritesService.toggleFavorite(ride.driverId);
      if (!mounted) return;
      setState(() {
        _isFavoriteDriver = next;
        _favoriteLoading = false;
      });
      AppSnackbar.show(
        context,
        next
            ? 'Conductor agregado a favoritos.'
            : 'Conductor eliminado de favoritos.',
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _favoriteLoading = false);
      AppSnackbar.show(
        context,
        AppErrorMapper.toMessage(
          e,
          fallback: 'No pudimos actualizar favoritos.',
        ),
        isError: true,
      );
    }
  }

  void _reportDriver() {
    final ride = _ride;
    final driver = _driverProfile;
    if (ride == null || driver == null) return;

    showDialog<bool>(
      context: context,
      builder: (_) => ReportUserDialog(
        reportedUserId: ride.driverId,
        reportedUserName: driver.fullName ?? 'Conductor',
      ),
    );
  }

  Future<void> _blockDriver() async {
    final ride = _ride;
    final driver = _driverProfile;
    if (ride == null || driver == null) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Bloquear conductor'),
        content: Text(
          'Al bloquear a ${driver.fullName ?? 'este conductor'}, no podra ver tu perfil ni reservar tus turnos, y tu no podras reservar los suyos.',
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

    try {
      await _reportService.blockUser(ride.driverId);
      if (mounted) {
        AppSnackbar.show(
          context,
          'Conductor bloqueado.',
        );
        context.pop();
      }
    } catch (e) {
      if (mounted) {
        AppSnackbar.show(
          context,
          'No pudimos bloquear al conductor.',
          isError: true,
        );
      }
    }
  }

  Future<void> _confirmBooking() async {
    if (_ride == null) return;

    final balance = _wallet?.balanceAvailable ?? 0;
    final totalCharge = _ride!.seatPrice + (_ride!.platformFee);

    if (balance < totalCharge) {
      AppSnackbar.show(
        context,
        'Saldo insuficiente. Recarga tu billetera.',
        isError: true,
      );
      return;
    }

    final totalFmt = NumberFormat.currency(
      locale: 'es_CL',
      symbol: '\$',
      decimalDigits: 0,
    ).format(totalCharge);

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Confirmar reserva'),
        content: Text(
          'Se descontarán $totalFmt de tu saldo y quedarán retenidos hasta que confirmes el abordaje.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Reservar'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    setState(() => _booking = true);
    try {
      await _bookingService.createBooking(widget.rideId);
      if (mounted) {
        AppSnackbar.show(context, 'Reserva confirmada');
        context.go('/my-rides');
      }
    } catch (e) {
      if (mounted) {
        AppSnackbar.show(
          context,
          AppErrorMapper.toMessage(
            e,
            fallback: 'No pudimos procesar tu reserva. Intenta nuevamente.',
          ),
          isError: true,
        );
      }
    } finally {
      if (mounted) setState(() => _booking = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final price = _ride?.seatPrice ?? 0;
    final priceFmt = NumberFormat.currency(
      locale: 'es_CL',
      symbol: '\$',
      decimalDigits: 0,
    ).format(price);

    final balanceFmt = NumberFormat.currency(
      locale: 'es_CL',
      symbol: '\$',
      decimalDigits: 0,
    ).format(_wallet?.balanceAvailable ?? 0);

    final canBook = (_ride?.isActive ?? false) && !(_ride?.isFull ?? true);

    return LoadingOverlay(
      isLoading: _booking,
      message: 'Procesando reserva...',
      child: Scaffold(
        appBar: AppBar(title: const Text('Detalle del turno')),
        body: DecorativeBackground(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _ride == null
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.directions_car_outlined,
                              size: 52,
                              color: Colors.grey.shade400,
                            ),
                            const SizedBox(height: 10),
                            const Text(
                              'Este turno ya no esta disponible.',
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 12),
                            OutlinedButton(
                              onPressed: () => context.pop(),
                              child: const Text('Volver'),
                            ),
                          ],
                        ),
                      ),
                    )
                  : ListView(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 120),
                      children: [
                        _InfoSection(ride: _ride!),
                        const SizedBox(height: 12),
                        if (_driverProfile != null)
                          _DriverProfileSection(
                            profile: _driverProfile!,
                            reviews: _driverReviews,
                            isFavorite: _isFavoriteDriver,
                            isFavoriteLoading: _favoriteLoading,
                            onToggleFavorite: _toggleDriverFavorite,
                            onReport: _reportDriver,
                            onBlock: _blockDriver,
                          ),
                        const SizedBox(height: 12),
                        Card(
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Resumen de pago',
                                  style: Theme.of(context)
                                      .textTheme
                                      .titleSmall
                                      ?.copyWith(fontWeight: FontWeight.w700),
                                ),
                                const SizedBox(height: 12),
                                _PriceRow(
                                  label: 'Precio por asiento',
                                  value: priceFmt,
                                ),
                                const Divider(),
                                _PriceRow(
                                  label: 'Comision pasajero (incluida)',
                                  value: NumberFormat.currency(
                                    locale: 'es_CL',
                                    symbol: '\$',
                                    decimalDigits: 0,
                                  ).format(_ride?.platformFee ?? 0),
                                ),
                                _PriceRow(
                                  label: 'Neto conductor (sin descuento extra)',
                                  value: NumberFormat.currency(
                                    locale: 'es_CL',
                                    symbol: '\$',
                                    decimalDigits: 0,
                                  ).format(_ride?.driverNetAmount ?? price),
                                ),
                                _PriceRow(
                                  label: 'Total a retener',
                                  value: priceFmt,
                                  bold: true,
                                ),
                                const SizedBox(height: 8),
                                Container(
                                  width: double.infinity,
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: (_wallet?.balanceAvailable ?? 0) >=
                                            price
                                        ? const Color(0xFFE9F6EE)
                                        : const Color(0xFFFCEDEF),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Text(
                                    'Tu saldo actual: $balanceFmt',
                                    style: TextStyle(
                                      color: (_wallet?.balanceAvailable ?? 0) >=
                                              price
                                          ? const Color(0xFF1B734D)
                                          : AppTheme.danger,
                                      fontWeight: FontWeight.w700,
                                      fontSize: 13,
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 8),
                                const Text(
                                  'El flujo ahora es: conductor acepta -> en camino -> llego -> abordas -> viaje -> finaliza.',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: AppTheme.subtle,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  'Tiempo de espera recomendado: ${AppConstants.waitTimeMinutesNoShow} minutos en el punto de encuentro.',
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: AppTheme.subtle,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                const Text(
                                  'Turno actua como intermediario. Usa boton de panico y llama al 133 ante emergencias.',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: AppTheme.danger,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
        ),
        bottomNavigationBar: _ride == null
            ? null
            : SafeArea(
                minimum: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ElevatedButton(
                      onPressed: canBook ? _confirmBooking : null,
                      child: const Text('Reservar asiento'),
                    ),
                    if (_ride!.isFull)
                      const Padding(
                        padding: EdgeInsets.only(top: 8),
                        child: Text(
                          'Turno sin cupos disponibles',
                          style:
                              TextStyle(color: AppTheme.danger, fontSize: 12),
                        ),
                      ),
                  ],
                ),
              ),
      ),
    );
  }
}

class _InfoSection extends StatelessWidget {
  final Ride ride;
  const _InfoSection({required this.ride});

  @override
  Widget build(BuildContext context) {
    final dateFmt =
        DateFormat('EEEE d \'de\' MMMM, HH:mm', 'es').format(ride.departureAt);
    final isTo = ride.direction == RideDirection.toCampus;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: const Color(0xFFE7F3FF),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    isTo ? Icons.school_outlined : Icons.home_outlined,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  ride.directionLabel,
                  style: const TextStyle(
                      fontWeight: FontWeight.w700, fontSize: 16),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _InfoRow(
              icon: Icons.location_on_outlined,
              label: isTo
                  ? '${ride.originCommune} → ${ride.campusName ?? ''}'
                  : '${ride.campusName ?? ''} → ${ride.originCommune}',
            ),
            if (ride.meetingPoint != null && ride.meetingPoint!.isNotEmpty) ...[
              const SizedBox(height: 8),
              _InfoRow(
                icon: Icons.pin_drop_outlined,
                label: 'Punto de encuentro: ${ride.meetingPoint}',
              ),
            ],
            const SizedBox(height: 8),
            _InfoRow(icon: Icons.access_time, label: dateFmt),
            const SizedBox(height: 8),
            _InfoRow(
              icon: Icons.event_seat_outlined,
              label:
                  '${ride.seatsAvailable} de ${ride.seatsTotal} cupos libres',
            ),
            if (ride.driverName != null) ...[
              const SizedBox(height: 8),
              _InfoRow(icon: Icons.person_outline, label: ride.driverName!),
            ],
          ],
        ),
      ),
    );
  }
}

class _DriverProfileSection extends StatelessWidget {
  final UserProfile profile;
  final List<UserReview> reviews;
  final bool isFavorite;
  final bool isFavoriteLoading;
  final VoidCallback onToggleFavorite;
  final VoidCallback? onReport;
  final VoidCallback? onBlock;

  const _DriverProfileSection({
    required this.profile,
    required this.reviews,
    required this.isFavorite,
    required this.isFavoriteLoading,
    required this.onToggleFavorite,
    this.onReport,
    this.onBlock,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Perfil del conductor',
              style: Theme.of(context)
                  .textTheme
                  .titleSmall
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                CircleAvatar(
                  radius: 22,
                  backgroundColor: const Color(0xFFE7F3FF),
                  backgroundImage: (profile.profilePhotoUrl != null &&
                          profile.profilePhotoUrl!.isNotEmpty)
                      ? NetworkImage(profile.profilePhotoUrl!)
                      : null,
                  child: (profile.profilePhotoUrl == null ||
                          profile.profilePhotoUrl!.isEmpty)
                      ? const Icon(Icons.person_outline)
                      : null,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        profile.fullName ?? 'Conductor',
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      Text(
                        'Rating ${profile.ratingAvg.toStringAsFixed(2)} (${profile.ratingCount})',
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppTheme.subtle,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: isFavoriteLoading ? null : onToggleFavorite,
                  tooltip: isFavorite
                      ? 'Quitar de favoritos'
                      : 'Agregar a favoritos',
                  icon: Icon(
                    isFavorite ? Icons.favorite : Icons.favorite_border,
                    color: isFavorite
                        ? const Color(0xFFFF5A7A)
                        : Theme.of(context).colorScheme.primary,
                  ),
                ),
              ],
            ),
            if (profile.vehiclePlate != null ||
                profile.vehicleModel != null) ...[
              const SizedBox(height: 10),
              Text(
                'Auto: ${(profile.vehicleModel ?? '-')} · Patente: ${(profile.vehiclePlate ?? '-')}',
                style: const TextStyle(fontSize: 13),
              ),
            ],
            if (reviews.isNotEmpty) ...[
              const SizedBox(height: 12),
              const Divider(),
              const SizedBox(height: 6),
              const Text(
                'Referencias recientes',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              ...reviews.take(3).map(
                    (review) => Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Text(
                                review.reviewerName ?? 'Usuario',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 12,
                                ),
                              ),
                              const SizedBox(width: 6),
                              Text(
                                '· ${review.stars}/5',
                                style: const TextStyle(
                                  color: AppTheme.subtle,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                          if ((review.comment ?? '').isNotEmpty)
                            Text(
                              review.comment!,
                              style: const TextStyle(
                                fontSize: 12,
                                color: AppTheme.subtle,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
            ],
            if (onReport != null || onBlock != null) ...[
              const SizedBox(height: 12),
              const Divider(),
              const SizedBox(height: 8),
              Row(
                children: [
                  if (onReport != null) ...[
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: onReport,
                        icon: const Icon(Icons.flag_outlined, size: 16),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppTheme.warning,
                          side: const BorderSide(color: AppTheme.warning),
                        ),
                        label: const Text('Reportar', style: TextStyle(fontSize: 12)),
                      ),
                    ),
                    const SizedBox(width: 8),
                  ],
                  if (onBlock != null) ...[
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: onBlock,
                        icon: const Icon(Icons.block_outlined, size: 16),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppTheme.danger,
                          side: const BorderSide(color: AppTheme.danger),
                        ),
                        label: const Text('Bloquear', style: TextStyle(fontSize: 12)),
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

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String label;
  const _InfoRow({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 16, color: AppTheme.subtle),
        const SizedBox(width: 8),
        Expanded(child: Text(label, style: const TextStyle(fontSize: 14))),
      ],
    );
  }
}

class _PriceRow extends StatelessWidget {
  final String label;
  final String value;
  final bool bold;
  const _PriceRow(
      {required this.label, required this.value, this.bold = false});

  @override
  Widget build(BuildContext context) {
    final style = TextStyle(
      fontWeight: bold ? FontWeight.w700 : FontWeight.normal,
      fontSize: bold ? 15 : 14,
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [Text(label, style: style), Text(value, style: style)],
      ),
    );
  }
}
