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

class Booking {
  final String id;
  final String rideId;
  final String passengerId;
  final String? driverId;
  final String? driverName;
  final double? driverRating;
  final String? driverPhotoUrl;
  final String? driverVehiclePlate;
  final String? driverVehicleModel;
  final String? driverEmergencyContact;
  final String? passengerName;
  final double? passengerRating;
  final String? passengerPhotoUrl;
  final String? passengerVehiclePlate;
  final String? passengerVehicleModel;
  final int? passengerRatingCount;
  final int? driverRatingCount;
  final int amountTotal;
  final BookingStatus status;
  final BookingDispatchStatus dispatchStatus;
  final DateTime? confirmedAt;
  final DateTime? reportedNoShowAt;
  final String? noShowNotes;
  final DateTime? driverAcceptedAt;
  final DateTime? driverArrivingAt;
  final DateTime? driverArrivedAt;
  final DateTime? passengerBoardedAt;
  final DateTime? tripStartedAt;
  final DateTime? tripCompletedAt;
  final DateTime? cancelledAt;
  final String? cancelReason;
  final DateTime createdAt;

  // Optional joined fields
  final String? rideOriginCommune;
  final DateTime? rideDepartureAt;
  final String? universityName;
  final String? campusName;

  const Booking({
    required this.id,
    required this.rideId,
    required this.passengerId,
    this.driverId,
    this.driverName,
    this.driverRating,
    this.driverPhotoUrl,
    this.driverVehiclePlate,
    this.driverVehicleModel,
    this.driverEmergencyContact,
    this.passengerName,
    this.passengerRating,
    this.passengerPhotoUrl,
    this.passengerVehiclePlate,
    this.passengerVehicleModel,
    this.passengerRatingCount,
    this.driverRatingCount,
    required this.amountTotal,
    required this.status,
    required this.dispatchStatus,
    this.confirmedAt,
    this.reportedNoShowAt,
    this.noShowNotes,
    this.driverAcceptedAt,
    this.driverArrivingAt,
    this.driverArrivedAt,
    this.passengerBoardedAt,
    this.tripStartedAt,
    this.tripCompletedAt,
    this.cancelledAt,
    this.cancelReason,
    required this.createdAt,
    this.rideOriginCommune,
    this.rideDepartureAt,
    this.universityName,
    this.campusName,
  });

  factory Booking.fromJson(Map<String, dynamic> json) {
    BookingStatus parseStatus(String s) {
      switch (s) {
        case 'cancelled':
          return BookingStatus.cancelled;
        case 'completed':
          return BookingStatus.completed;
        case 'no_show':
          return BookingStatus.noShow;
        default:
          return BookingStatus.reserved;
      }
    }

    BookingDispatchStatus parseDispatchStatus(String s) {
      final normalized =
          s.trim().toLowerCase().replaceAll('"', '').replaceAll("'", '');
      switch (normalized) {
        case 'reserved':
          return BookingDispatchStatus.reserved;
        case 'accepted':
          return BookingDispatchStatus.accepted;
        case 'driver_arriving':
          return BookingDispatchStatus.driverArriving;
        case 'driver_arrived':
          return BookingDispatchStatus.driverArrived;
        case 'passenger_boarded':
          return BookingDispatchStatus.passengerBoarded;
        case 'in_progress':
          return BookingDispatchStatus.inProgress;
        case 'completed':
          return BookingDispatchStatus.completed;
        case 'cancelled':
          return BookingDispatchStatus.cancelled;
        case 'no_show':
          return BookingDispatchStatus.noShow;
        default:
          // ignore: avoid_print
          print(
              '⚠ dispatch_status desconocido desde API: "$s" (normalized: "$normalized"), usando reserved');
          return BookingDispatchStatus.reserved;
      }
    }

    return Booking(
      id: json['id'] as String,
      rideId: json['ride_id'] as String,
      passengerId: json['passenger_id'] as String,
      driverId: json['driver_id'] as String?,
      driverName: json['driver_name'] as String?,
      driverRating: (json['driver_rating'] as num?)?.toDouble(),
      driverPhotoUrl: json['driver_photo_url'] as String?,
      driverVehiclePlate: json['driver_vehicle_plate'] as String?,
      driverVehicleModel: json['driver_vehicle_model'] as String?,
      driverEmergencyContact: json['driver_emergency_contact'] as String?,
      passengerName: json['passenger_name'] as String?,
      passengerRating: (json['passenger_rating'] as num?)?.toDouble(),
      passengerPhotoUrl: json['passenger_photo_url'] as String?,
      passengerVehiclePlate: json['passenger_vehicle_plate'] as String?,
      passengerVehicleModel: json['passenger_vehicle_model'] as String?,
      passengerRatingCount: (json['passenger_rating_count'] as num?)?.toInt(),
      driverRatingCount: (json['driver_rating_count'] as num?)?.toInt(),
      amountTotal: (json['amount_total'] as int?) ?? 2000,
      status: parseStatus((json['status'] as String?) ?? 'reserved'),
      dispatchStatus: parseDispatchStatus(
        (json['dispatch_status'] as String?) ?? 'reserved',
      ),
      confirmedAt: json['confirmed_at'] != null
          ? DateTime.parse(json['confirmed_at'] as String).toLocal()
          : null,
      reportedNoShowAt: json['reported_no_show_at'] != null
          ? DateTime.parse(json['reported_no_show_at'] as String).toLocal()
          : null,
      noShowNotes: json['no_show_notes'] as String?,
      driverAcceptedAt: json['driver_accepted_at'] != null
          ? DateTime.parse(json['driver_accepted_at'] as String).toLocal()
          : null,
      driverArrivingAt: json['driver_arriving_at'] != null
          ? DateTime.parse(json['driver_arriving_at'] as String).toLocal()
          : null,
      driverArrivedAt: json['driver_arrived_at'] != null
          ? DateTime.parse(json['driver_arrived_at'] as String).toLocal()
          : null,
      passengerBoardedAt: json['passenger_boarded_at'] != null
          ? DateTime.parse(json['passenger_boarded_at'] as String).toLocal()
          : null,
      tripStartedAt: json['trip_started_at'] != null
          ? DateTime.parse(json['trip_started_at'] as String).toLocal()
          : null,
      tripCompletedAt: json['trip_completed_at'] != null
          ? DateTime.parse(json['trip_completed_at'] as String).toLocal()
          : null,
      cancelledAt: json['cancelled_at'] != null
          ? DateTime.parse(json['cancelled_at'] as String).toLocal()
          : null,
      cancelReason: json['cancel_reason'] as String?,
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'] as String).toLocal()
          : DateTime.now(),
      rideOriginCommune: json['ride_origin_commune'] as String?,
      rideDepartureAt: json['ride_departure_at'] != null
          ? DateTime.parse(json['ride_departure_at'] as String).toLocal()
          : null,
      universityName: json['university_name'] as String?,
      campusName: json['campus_name'] as String?,
    );
  }

  bool get isReserved => status == BookingStatus.reserved;
  bool get isCompleted => status == BookingStatus.completed;
  bool get canPassengerConfirmBoarding =>
      isReserved &&
      (dispatchStatus == BookingDispatchStatus.driverArrived);
  bool get canDriverStartTrip =>
      isReserved && dispatchStatus == BookingDispatchStatus.passengerBoarded;
  bool get canDriverCompleteTrip =>
      isReserved &&
      (dispatchStatus == BookingDispatchStatus.inProgress ||
          dispatchStatus == BookingDispatchStatus.passengerBoarded);

  String get dispatchLabel {
    switch (dispatchStatus) {
      case BookingDispatchStatus.reserved:
        return 'Pendiente aceptacion';
      case BookingDispatchStatus.accepted:
        return 'Aceptado';
      case BookingDispatchStatus.driverArriving:
        return 'Conductor en camino';
      case BookingDispatchStatus.driverArrived:
        return 'Conductor llego';
      case BookingDispatchStatus.passengerBoarded:
        return 'Pasajero abordo';
      case BookingDispatchStatus.inProgress:
        return 'Viaje en curso';
      case BookingDispatchStatus.completed:
        return 'Viaje finalizado';
      case BookingDispatchStatus.cancelled:
        return 'Cancelado';
      case BookingDispatchStatus.noShow:
        return 'No-show';
    }
  }

  Booking copyWith({
    String? id,
    String? rideId,
    String? passengerId,
    String? driverId,
    String? driverName,
    double? driverRating,
    String? driverPhotoUrl,
    String? driverVehiclePlate,
    String? driverVehicleModel,
    String? driverEmergencyContact,
    String? passengerName,
    double? passengerRating,
    String? passengerPhotoUrl,
    String? passengerVehiclePlate,
    String? passengerVehicleModel,
    int? passengerRatingCount,
    int? driverRatingCount,
    int? amountTotal,
    BookingStatus? status,
    BookingDispatchStatus? dispatchStatus,
    DateTime? confirmedAt,
    DateTime? reportedNoShowAt,
    String? noShowNotes,
    DateTime? driverAcceptedAt,
    DateTime? driverArrivingAt,
    DateTime? driverArrivedAt,
    DateTime? passengerBoardedAt,
    DateTime? tripStartedAt,
    DateTime? tripCompletedAt,
    DateTime? cancelledAt,
    String? cancelReason,
    DateTime? createdAt,
    String? rideOriginCommune,
    DateTime? rideDepartureAt,
    String? universityName,
    String? campusName,
  }) {
    return Booking(
      id: id ?? this.id,
      rideId: rideId ?? this.rideId,
      passengerId: passengerId ?? this.passengerId,
      driverId: driverId ?? this.driverId,
      driverName: driverName ?? this.driverName,
      driverRating: driverRating ?? this.driverRating,
      driverPhotoUrl: driverPhotoUrl ?? this.driverPhotoUrl,
      driverVehiclePlate: driverVehiclePlate ?? this.driverVehiclePlate,
      driverVehicleModel: driverVehicleModel ?? this.driverVehicleModel,
      driverEmergencyContact: driverEmergencyContact ?? this.driverEmergencyContact,
      passengerName: passengerName ?? this.passengerName,
      passengerRating: passengerRating ?? this.passengerRating,
      passengerPhotoUrl: passengerPhotoUrl ?? this.passengerPhotoUrl,
      passengerVehiclePlate: passengerVehiclePlate ?? this.passengerVehiclePlate,
      passengerVehicleModel: passengerVehicleModel ?? this.passengerVehicleModel,
      passengerRatingCount: passengerRatingCount ?? this.passengerRatingCount,
      driverRatingCount: driverRatingCount ?? this.driverRatingCount,
      amountTotal: amountTotal ?? this.amountTotal,
      status: status ?? this.status,
      dispatchStatus: dispatchStatus ?? this.dispatchStatus,
      confirmedAt: confirmedAt ?? this.confirmedAt,
      reportedNoShowAt: reportedNoShowAt ?? this.reportedNoShowAt,
      noShowNotes: noShowNotes ?? this.noShowNotes,
      driverAcceptedAt: driverAcceptedAt ?? this.driverAcceptedAt,
      driverArrivingAt: driverArrivingAt ?? this.driverArrivingAt,
      driverArrivedAt: driverArrivedAt ?? this.driverArrivedAt,
      passengerBoardedAt: passengerBoardedAt ?? this.passengerBoardedAt,
      tripStartedAt: tripStartedAt ?? this.tripStartedAt,
      tripCompletedAt: tripCompletedAt ?? this.tripCompletedAt,
      cancelledAt: cancelledAt ?? this.cancelledAt,
      cancelReason: cancelReason ?? this.cancelReason,
      createdAt: createdAt ?? this.createdAt,
      rideOriginCommune: rideOriginCommune ?? this.rideOriginCommune,
      rideDepartureAt: rideDepartureAt ?? this.rideDepartureAt,
      universityName: universityName ?? this.universityName,
      campusName: campusName ?? this.campusName,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'ride_id': rideId,
      'passenger_id': passengerId,
      if (driverId != null) 'driver_id': driverId,
      if (driverName != null) 'driver_name': driverName,
      if (driverRating != null) 'driver_rating': driverRating,
      if (driverPhotoUrl != null) 'driver_photo_url': driverPhotoUrl,
      if (driverVehiclePlate != null) 'driver_vehicle_plate': driverVehiclePlate,
      if (driverVehicleModel != null) 'driver_vehicle_model': driverVehicleModel,
      if (driverEmergencyContact != null) 'driver_emergency_contact': driverEmergencyContact,
      if (passengerName != null) 'passenger_name': passengerName,
      if (passengerRating != null) 'passenger_rating': passengerRating,
      if (passengerPhotoUrl != null) 'passenger_photo_url': passengerPhotoUrl,
      if (passengerVehiclePlate != null) 'passenger_vehicle_plate': passengerVehiclePlate,
      if (passengerVehicleModel != null) 'passenger_vehicle_model': passengerVehicleModel,
      if (passengerRatingCount != null) 'passenger_rating_count': passengerRatingCount,
      if (driverRatingCount != null) 'driver_rating_count': driverRatingCount,
      'amount_total': amountTotal,
      'status': status.name,
      'dispatch_status': dispatchStatus.name,
      if (confirmedAt != null) 'confirmed_at': confirmedAt!.toIso8601String(),
      if (reportedNoShowAt != null) 'reported_no_show_at': reportedNoShowAt!.toIso8601String(),
      if (noShowNotes != null) 'no_show_notes': noShowNotes,
      if (driverAcceptedAt != null) 'driver_accepted_at': driverAcceptedAt!.toIso8601String(),
      if (driverArrivingAt != null) 'driver_arriving_at': driverArrivingAt!.toIso8601String(),
      if (driverArrivedAt != null) 'driver_arrived_at': driverArrivedAt!.toIso8601String(),
      if (passengerBoardedAt != null) 'passenger_boarded_at': passengerBoardedAt!.toIso8601String(),
      if (tripStartedAt != null) 'trip_started_at': tripStartedAt!.toIso8601String(),
      if (tripCompletedAt != null) 'trip_completed_at': tripCompletedAt!.toIso8601String(),
      if (cancelledAt != null) 'cancelled_at': cancelledAt!.toIso8601String(),
      if (cancelReason != null) 'cancel_reason': cancelReason,
      'created_at': createdAt.toIso8601String(),
      if (rideOriginCommune != null) 'ride_origin_commune': rideOriginCommune,
      if (rideDepartureAt != null) 'ride_departure_at': rideDepartureAt!.toIso8601String(),
      if (universityName != null) 'university_name': universityName,
      if (campusName != null) 'campus_name': campusName,
    };
  }
}
