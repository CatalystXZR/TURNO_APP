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
      createdAt: DateTime.parse(json['created_at'] as String).toLocal(),
      rideOriginCommune: json['ride_origin_commune'] as String?,
      rideDepartureAt: json['ride_departure_at'] != null
          ? DateTime.parse(json['ride_departure_at'] as String)
          : null,
      universityName: json['university_name'] as String?,
      campusName: json['campus_name'] as String?,
    );
  }

  bool get isReserved => status == BookingStatus.reserved;
  bool get isCompleted => status == BookingStatus.completed;
  bool get canPassengerConfirmBoarding =>
      isReserved &&
      (dispatchStatus == BookingDispatchStatus.accepted ||
          dispatchStatus == BookingDispatchStatus.driverArriving ||
          dispatchStatus == BookingDispatchStatus.driverArrived);
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
}
