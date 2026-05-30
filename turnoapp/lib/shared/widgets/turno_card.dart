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
import 'package:intl/intl.dart';

import '../../app/theme.dart';

class TurnoCard extends StatelessWidget {
  final String originCommune;
  final String universityName;
  final String? universityCode;
  final String campusName;
  final String? meetingPoint;
  final DateTime departureAt;
  final String direction;
  final String? driverName;
  final double? driverRating;
  final int? driverRatingCount;
  final int seatsAvailable;
  final int seatPrice;
  final int? platformFee;
  final int? driverNetAmount;
  final bool? isRadial;
  final VoidCallback? onTap;

  const TurnoCard({
    super.key,
    required this.originCommune,
    required this.universityName,
    this.universityCode,
    required this.campusName,
    this.meetingPoint,
    required this.departureAt,
    required this.direction,
    this.driverName,
    this.driverRating,
    this.driverRatingCount,
    required this.seatsAvailable,
    required this.seatPrice,
    this.platformFee,
    this.driverNetAmount,
    this.isRadial,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final timeStr = DateFormat('HH:mm').format(departureAt);
    final dateStr = DateFormat('EEE d MMM', 'es').format(departureAt);
    final priceStr = NumberFormat.currency(
      locale: 'es_CL',
      symbol: '\$',
      decimalDigits: 0,
    ).format(seatPrice);

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      color: const Color(0xFFE7F3FF),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(
                      direction == 'to_campus'
                          ? Icons.school_outlined
                          : Icons.home_outlined,
                      size: 18,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      direction == 'to_campus'
                          ? '$originCommune → $campusName'
                          : '$campusName → $originCommune',
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                      ),
                    ),
                  ),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: const Color(0xFFEAF4FF),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      priceStr,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.primary,
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  const Icon(Icons.access_time,
                      size: 14, color: AppTheme.subtle),
                  const SizedBox(width: 4),
                  Text('$dateStr  $timeStr',
                      style: const TextStyle(
                          color: AppTheme.subtle, fontSize: 13)),
                  const Spacer(),
                  Icon(
                    Icons.event_seat_outlined,
                    size: 14,
                    color: seatsAvailable > 0
                        ? const Color(0xFF178E68)
                        : AppTheme.danger,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    '$seatsAvailable cupo${seatsAvailable == 1 ? '' : 's'}',
                    style: TextStyle(
                      color: seatsAvailable > 0
                          ? const Color(0xFF178E68)
                          : AppTheme.danger,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                universityName,
                style: const TextStyle(
                  color: AppTheme.subtle,
                  fontSize: 12,
                ),
              ),
              if ((driverName ?? '').isNotEmpty || driverRating != null) ...[
                const SizedBox(height: 4),
                Text(
                  '${driverName ?? 'Conductor'} · Rating ${(driverRating ?? 5).toStringAsFixed(2)} (${driverRatingCount ?? 0})',
                  style: const TextStyle(
                    color: AppTheme.subtle,
                    fontSize: 12,
                  ),
                ),
              ],
              if (meetingPoint != null && meetingPoint!.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  'Punto: $meetingPoint',
                  style: const TextStyle(
                    color: AppTheme.subtle,
                    fontSize: 12,
                  ),
                ),
              ],
              if (platformFee != null && platformFee! > 0) ...[
                const SizedBox(height: 2),
                Text(
                  'incluye \$' '$platformFee de servicio',
                  style: const TextStyle(
                    color: Color(0xFFBDC3C8),
                    fontSize: 10,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
