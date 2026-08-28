import 'package:flutter/material.dart';

import '../../app/theme.dart';
import '../../models/booking.dart';
import '../../models/enums.dart';

class BookingFlowButtons extends StatelessWidget {
  final Booking booking;
  final VoidCallback? onAccept;
  final VoidCallback? onReject;
  final VoidCallback? onMarkArriving;
  final VoidCallback? onMarkArrived;
  final VoidCallback? onStartTrip;
  final VoidCallback? onCompleteTrip;
  final VoidCallback? onReview;
  final VoidCallback? onFavorite;
  final VoidCallback? onReportNoShow;
  final bool isFavorite;

  const BookingFlowButtons({
    super.key,
    required this.booking,
    this.onAccept,
    this.onReject,
    this.onMarkArriving,
    this.onMarkArrived,
    this.onStartTrip,
    this.onCompleteTrip,
    this.onReview,
    this.onFavorite,
    this.onReportNoShow,
    this.isFavorite = false,
  });

  @override
  Widget build(BuildContext context) {
    final actions = _buildActions();
    if (actions.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: actions.length == 1
          ? actions.first
          : actions.length == 2
              ? Row(
                  children: [
                    Expanded(child: actions[0]),
                    const SizedBox(width: 8),
                    Expanded(child: actions[1]),
                  ],
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    ...actions.map(
                      (a) => Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: a,
                      ),
                    ),
                  ],
                ),
    );
  }

  List<Widget> _buildActions() {
    final actions = <Widget>[];

    if (booking.isReserved &&
        booking.dispatchStatus == BookingDispatchStatus.reserved) {
      actions.addAll([
        OutlinedButton(
          onPressed: onReject,
          style: OutlinedButton.styleFrom(
            foregroundColor: AppTheme.danger,
            side: const BorderSide(color: AppTheme.danger),
            minimumSize: const Size(0, 40),
          ),
          child: const Text('Rechazar'),
        ),
        ElevatedButton(
          onPressed: onAccept,
          style: ElevatedButton.styleFrom(
            backgroundColor: AppTheme.success,
            foregroundColor: Colors.white,
            minimumSize: const Size(0, 40),
          ),
          child: const Text('Aceptar'),
        ),
      ]);
    } else if (booking.isReserved &&
        booking.dispatchStatus == BookingDispatchStatus.accepted) {
      actions.add(
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: onMarkArriving,
            icon: const Icon(Icons.route_outlined, size: 18),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primary,
              foregroundColor: Colors.white,
            ),
            label: const Text('En camino'),
          ),
        ),
      );
    } else if (booking.isReserved &&
        booking.dispatchStatus == BookingDispatchStatus.driverArriving) {
      actions.add(
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: onMarkArrived,
            icon: const Icon(Icons.place_outlined, size: 18),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.success,
              foregroundColor: Colors.white,
            ),
            label: const Text('Llegue a destino'),
          ),
        ),
      );
    } else if (booking.isReserved &&
        booking.dispatchStatus == BookingDispatchStatus.driverArrived) {
      if (onReportNoShow != null) {
        actions.add(
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: onReportNoShow,
              icon: const Icon(Icons.warning_amber_outlined, size: 16),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppTheme.warning,
                side: const BorderSide(color: AppTheme.warning),
                minimumSize: const Size(0, 36),
              ),
              label: const Text('Pasajero no llego', style: TextStyle(fontSize: 12)),
            ),
          ),
        );
      }
      actions.add(
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 4),
          child: Row(
            children: [
              Icon(Icons.access_time, size: 16, color: AppTheme.subtle),
              SizedBox(width: 6),
              Expanded(
                child: Text(
                  'Esperando que el pasajero confirme abordaje...',
                  style: TextStyle(color: AppTheme.subtle, fontSize: 12),
                ),
              ),
            ],
          ),
        ),
      );
    } else if (booking.canDriverStartTrip) {
      actions.add(
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: onStartTrip,
            icon: const Icon(Icons.play_arrow_rounded, size: 18),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primary,
              foregroundColor: Colors.white,
            ),
            label: const Text('Iniciar viaje'),
          ),
        ),
      );
    } else if (booking.canDriverCompleteTrip) {
      actions.add(
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: onCompleteTrip,
            icon: const Icon(Icons.check_circle_outline, size: 18),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.success,
              foregroundColor: Colors.white,
            ),
            label: const Text('Finalizar viaje'),
          ),
        ),
      );
    }

    if (booking.isCompleted && onReview != null) {
      actions.add(
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: onReview,
            icon: const Icon(Icons.star_outline, size: 18),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primary,
              foregroundColor: Colors.white,
            ),
            label: const Text('Calificar pasajero'),
          ),
        ),
      );
    }

    if (onFavorite != null) {
      actions.add(
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: onFavorite,
            style: ElevatedButton.styleFrom(
              backgroundColor:
                  isFavorite ? AppTheme.favorite : Colors.white,
              foregroundColor: isFavorite ? Colors.white : AppTheme.primary,
            ),
            icon: Icon(
              isFavorite ? Icons.favorite : Icons.favorite_outline,
              size: 18,
            ),
            label: Text(
              isFavorite ? 'Pasajero favorito' : 'Agregar pasajero a favoritos',
            ),
          ),
        ),
      );
    }

    return actions;
  }
}
