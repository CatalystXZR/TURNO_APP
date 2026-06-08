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

import 'enums.dart';

class Ride {
  final String id;
  final String driverId;
  final String universityId;
  final String? universityCode;
  final String campusId;
  final String originCommune;
  final String? meetingPoint;
  final bool isRadial;
  final RideDirection direction;
  final DateTime departureAt;
  final int seatPrice;
  final int platformFee;
  final int driverNetAmount;
  final int seatsTotal;
  final int seatsAvailable;
  final String status; // active | cancelled | completed
  final String? cancelReason;
  final DateTime? cancelledAt;
  final DateTime createdAt;

  // Optional joined fields
  final String? driverName;
  final double? driverRating;
  final int? driverRatingCount;
  final String? universityName;
  final String? campusName;

  const Ride({
    required this.id,
    required this.driverId,
    required this.universityId,
    this.universityCode,
    required this.campusId,
    required this.originCommune,
    this.meetingPoint,
    required this.isRadial,
    required this.direction,
    required this.departureAt,
    required this.seatPrice,
    required this.platformFee,
    required this.driverNetAmount,
    required this.seatsTotal,
    required this.seatsAvailable,
    required this.status,
    this.cancelReason,
    this.cancelledAt,
    required this.createdAt,
    this.driverName,
    this.driverRating,
    this.driverRatingCount,
    this.universityName,
    this.campusName,
  });

  factory Ride.fromJson(Map<String, dynamic> json) {
    return Ride(
      id: json['id'] as String,
      driverId: json['driver_id'] as String,
      universityId: json['university_id'] as String,
      universityCode: json['university_code'] as String?,
      campusId: json['campus_id'] as String,
      originCommune: json['origin_commune'] as String,
      meetingPoint: json['meeting_point'] as String?,
      isRadial: (json['is_radial'] as bool?) ?? false,
      direction: json['direction'] == 'to_campus'
          ? RideDirection.toCampus
          : RideDirection.fromCampus,
      departureAt:
          _parseChileTime(json['departure_at'] as String?) ?? DateTime.now(),
      seatPrice: (json['seat_price'] as int?) ?? 2000,
      platformFee: (json['platform_fee'] as int?) ?? 190,
      driverNetAmount: (json['driver_net_amount'] as int?) ??
          ((json['seat_price'] as int?) ?? 2000),
      seatsTotal: json['seats_total'] as int,
      seatsAvailable: json['seats_available'] as int,
      status: (json['status'] as String?) ?? 'active',
      cancelReason: json['cancel_reason'] as String?,
      cancelledAt: json['cancelled_at'] != null
          ? DateTime.parse(json['cancelled_at'] as String).toLocal()
          : null,
      createdAt: DateTime.parse(json['created_at'] as String).toLocal(),
      driverName: json['driver_name'] as String?,
      driverRating: (json['driver_rating'] as num?)?.toDouble(),
      driverRatingCount: (json['driver_rating_count'] as num?)?.toInt(),
      universityName: json['university_name'] as String?,
      campusName: json['campus_name'] as String?,
    );
  }

  Map<String, dynamic> toInsertJson() => {
        'driver_id': driverId,
        'university_id': universityId,
        'campus_id': campusId,
        'origin_commune': originCommune,
        if (meetingPoint != null) 'meeting_point': meetingPoint,
        'is_radial': isRadial,
        'direction':
            direction == RideDirection.toCampus ? 'to_campus' : 'from_campus',
        'departure_at': departureAt.toIso8601String(),
        'seat_price': seatPrice,
        'platform_fee': platformFee,
        'driver_net_amount': driverNetAmount,
        'seats_total': seatsTotal,
        'seats_available': seatsAvailable,
      };

  bool get isFull => seatsAvailable == 0;
  bool get isActive => status == 'active';

  String get directionLabel =>
      direction == RideDirection.toCampus ? 'Hacia campus' : 'Desde campus';
}

DateTime? _parseChileTime(String? value) {
  if (value == null) return null;
  final dt = DateTime.parse(value);
  if (dt.timeZoneName.isEmpty) return dt;
  return dt.toLocal();
}
