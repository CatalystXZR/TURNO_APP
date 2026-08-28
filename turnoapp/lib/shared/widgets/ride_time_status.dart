import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../app/theme.dart';

class RideTimeStatus extends StatelessWidget {
  final DateTime departureAt;
  final bool showLabel;

  const RideTimeStatus({
    super.key,
    required this.departureAt,
    this.showLabel = true,
  });

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final diff = departureAt.difference(now);
    final isPast = departureAt.isBefore(now);
    final isSoon = !isPast && diff.inMinutes <= 15;

    Color color;
    String label;
    IconData icon;

    if (isPast) {
      color = Colors.grey;
      label = 'Completado';
      icon = Icons.check_circle_outline;
    } else if (isSoon) {
      color = AppTheme.success;
      if (diff.inMinutes <= 5) {
        label = 'Por partir';
        icon = Icons.warning_amber_rounded;
      } else {
        label = 'En ${diff.inMinutes} min';
        icon = Icons.access_time;
      }
    } else {
      color = AppTheme.completedStatus;
      final diffHours = diff.inHours;
      if (diffHours < 1) {
        label = 'En ${diff.inMinutes} min';
      } else if (diffHours < 24) {
        label = 'En $diffHours hrs';
      } else {
        label = DateFormat('EEE d MMM', 'es').format(departureAt);
      }
      icon = Icons.schedule;
    }

    if (!showLabel) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: color),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                color: color,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      );
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(width: 6),
        Text(
          label,
          style: TextStyle(
            color: color,
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}
