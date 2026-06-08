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

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/retry_config.dart';
import '../core/supabase_client.dart';
import '../models/booking.dart';

class BookingService {
  final _client = SupabaseConfig.client;

  String _mapPostgresError(dynamic error) {
    final errorStr = error.toString().toLowerCase();

    if (errorStr.contains('p0004') || errorStr.contains('insufficient')) {
      return 'Saldo insuficiente en billetera';
    }
    if (errorStr.contains('p0016') || errorStr.contains('overlapping')) {
      return 'Choque de horarios con otro viaje';
    }
    if (errorStr.contains('p0010') ||
        errorStr.contains('ride_departed') ||
        errorStr.contains('partio')) {
      return 'El viaje ya partio';
    }
    if (errorStr.contains('p0001') || errorStr.contains('unauthorized')) {
      return 'Sesion expirada. Vuelve a iniciar sesion';
    }
    if (errorStr.contains('p0002') || errorStr.contains('unavailable')) {
      return 'Este turno ya no esta disponible';
    }
    if (errorStr.contains('p0003') || errorStr.contains('already booked')) {
      return 'Ya tienes una reserva en este turno';
    }
    if (errorStr.contains('p0011') || errorStr.contains('forbidden')) {
      return 'No puedes realizar esta accion';
    }

    if (error is PostgrestException) {
      final details = error.details as String?;
      final hint = error.hint;
      if (details != null && details.isNotEmpty) return details;
      if (hint != null && hint.isNotEmpty) return hint;
    }

    return error.toString();
  }

  Future<T> _retryRpc<T>(
    String fn, {
    Map<String, dynamic>? params,
  }) {
    return RetryConfig.withRetry(
      () async {
        final result = await _client.rpc(fn, params: params);
        return result as T;
      },
      isRetryable: (e) => RetryConfig.isNetworkError(e),
    );
  }

  Future<void> _retryRpcVoid(
    String fn, {
    Map<String, dynamic>? params,
  }) {
    return RetryConfig.withRetry(
      () async {
        await _client.rpc(fn, params: params);
      },
      isRetryable: (e) => RetryConfig.isNetworkError(e),
    );
  }

  Future<String> createBooking(String rideId) async {
    try {
      final uuidValid = _isValidUuid(rideId);
      if (!uuidValid) {
        throw Exception('ID de ride invalido');
      }

      final result = await _retryRpc<String>('create_booking', params: {
        'p_ride_id': rideId,
      });

      return result;
    } on PostgrestException catch (e) {
      throw Exception(_mapPostgresError(e));
    } catch (e) {
      throw Exception(_mapPostgresError(e));
    }
  }

  bool _isValidUuid(String value) {
    final uuidRegex = RegExp(
        r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
        caseSensitive: false);
    return uuidRegex.hasMatch(value.trim());
  }

  Future<void> confirmBoarding(String bookingId) async {
    await _retryRpcVoid('confirm_boarding', params: {
      'p_booking_id': bookingId,
    });
  }

  Future<void> driverAcceptBooking(String bookingId) async {
    await _retryRpcVoid('driver_accept_booking', params: {
      'p_booking_id': bookingId,
    });
  }

  Future<void> driverRejectBooking(String bookingId, {String? reason}) async {
    await _retryRpcVoid('driver_reject_booking', params: {
      'p_booking_id': bookingId,
      'p_reason': reason,
    });
  }

  Future<void> driverMarkArriving(String bookingId) async {
    await _retryRpcVoid('driver_mark_arriving', params: {
      'p_booking_id': bookingId,
    });
  }

  Future<void> driverMarkArrived(String bookingId) async {
    await _retryRpcVoid('driver_mark_arrived', params: {
      'p_booking_id': bookingId,
    });
  }

  Future<void> driverStartTrip(String bookingId) async {
    await _retryRpcVoid('driver_start_trip', params: {
      'p_booking_id': bookingId,
    });
  }

  Future<void> driverCompleteTrip(String bookingId) async {
    await _retryRpcVoid('driver_complete_trip', params: {
      'p_booking_id': bookingId,
    });
  }

  Future<void> driverCompleteRide(String rideId) async {
    await _retryRpcVoid('complete_ride_manual', params: {
      'p_ride_id': rideId,
    });
  }

  Future<void> cancelBooking(String bookingId) async {
    await _retryRpcVoid('cancel_booking', params: {
      'p_booking_id': bookingId,
    });
  }

  Future<void> reportDriverNoShow(String bookingId, {String? notes}) async {
    await _retryRpcVoid('passenger_report_no_show', params: {
      'p_booking_id': bookingId,
      'p_notes': notes,
    });
  }

  Future<List<Booking>> getMyBookings({int limit = 80}) async {
    final uid = _client.auth.currentUser!.id;
    final rows = await _client
        .from('bookings')
        .select('''
          *,
          rides!ride_id(
            driver_id,
            origin_commune,
            departure_at,
            universities!university_id(name),
            campuses!campus_id(name),
            users_profile!driver_id(
              full_name,
              rating_avg,
              rating_count,
              profile_photo_url,
              vehicle_plate,
              vehicle_model,
              emergency_contact
            )
          ),
          users_profile!passenger_id(
            full_name,
            rating_avg,
            rating_count,
            profile_photo_url,
            vehicle_plate,
            vehicle_model
          )
        ''')
        .eq('passenger_id', uid)
        .order('created_at', ascending: false)
        .limit(limit);

    return rows.map((row) {
      final flat = Map<String, dynamic>.from(row);
      final ride = row['rides'] as Map?;
      flat['ride_origin_commune'] = ride?['origin_commune'];
      flat['ride_departure_at'] = ride?['departure_at'];
      flat['driver_id'] = ride?['driver_id'];
      flat['university_name'] = (ride?['universities'] as Map?)?['name'];
      flat['campus_name'] = (ride?['campuses'] as Map?)?['name'];
      final passenger = row['users_profile'] as Map?;
      flat['passenger_name'] = passenger?['full_name'];
      flat['passenger_rating'] = passenger?['rating_avg'];
      flat['passenger_rating_count'] = passenger?['rating_count'];
      flat['passenger_photo_url'] = passenger?['profile_photo_url'];
      flat['passenger_vehicle_plate'] = passenger?['vehicle_plate'];
      flat['passenger_vehicle_model'] = passenger?['vehicle_model'];
      final driver = (ride?['users_profile'] as Map?);
      flat['driver_name'] = driver?['full_name'];
      flat['driver_rating'] = driver?['rating_avg'];
      flat['driver_rating_count'] = driver?['rating_count'];
      flat['driver_photo_url'] = driver?['profile_photo_url'];
      flat['driver_vehicle_plate'] = driver?['vehicle_plate'];
      flat['driver_vehicle_model'] = driver?['vehicle_model'];
      flat['driver_emergency_contact'] = driver?['emergency_contact'];
      return Booking.fromJson(flat);
    }).toList();
  }

  Future<List<Booking>> getBookingsForMyRides({int limit = 100}) async {
    final uid = _client.auth.currentUser!.id;

    try {
      final rows = await _client
          .from('bookings')
          .select('''
          *,
          rides!ride_id(origin_commune, departure_at,
            driver_id,
            universities!university_id(name),
            campuses!campus_id(name)
          ),
          users_profile!passenger_id(
            full_name,
            rating_avg,
            rating_count,
            profile_photo_url,
            vehicle_plate,
            vehicle_model
          )
        ''')
          .eq('driver_id', uid)
          .order('created_at', ascending: false)
          .limit(limit);

      return _mapBookingsWithRideAndPassenger(rows);
    } on PostgrestException catch (e) {
      debugPrint(
          '[Turno] BookingService: direct query failed (driver_id col may not exist), using fallback: $e');
    }

    final rideRows =
        await _client.from('rides').select('id').eq('driver_id', uid);

    if (rideRows.isEmpty) return [];

    final rideIds = rideRows.map((r) => r['id'] as String).toList();

    final rows = await _client
        .from('bookings')
        .select('''
          *,
          rides!ride_id(origin_commune, departure_at,
            driver_id,
            universities!university_id(name),
            campuses!campus_id(name)
          ),
          users_profile!passenger_id(
            full_name,
            rating_avg,
            rating_count,
            profile_photo_url,
            vehicle_plate,
            vehicle_model
          )
        ''')
        .inFilter('ride_id', rideIds)
        .order('created_at', ascending: false)
        .limit(limit);

    return _mapBookingsWithRideAndPassenger(rows);
  }

  List<Booking> _mapBookingsWithRideAndPassenger(List<dynamic> rows) {
    return rows.map((row) {
      final flat = Map<String, dynamic>.from(row);
      final ride = row['rides'] as Map?;
      flat['ride_origin_commune'] = ride?['origin_commune'];
      flat['ride_departure_at'] = ride?['departure_at'];
      flat['driver_id'] = ride?['driver_id'];
      flat['university_name'] = (ride?['universities'] as Map?)?['name'];
      flat['campus_name'] = (ride?['campuses'] as Map?)?['name'];
      final passenger = row['users_profile'] as Map?;
      flat['passenger_name'] = passenger?['full_name'];
      flat['passenger_rating'] = passenger?['rating_avg'];
      flat['passenger_rating_count'] = passenger?['rating_count'];
      flat['passenger_photo_url'] = passenger?['profile_photo_url'];
      flat['passenger_vehicle_plate'] = passenger?['vehicle_plate'];
      flat['passenger_vehicle_model'] = passenger?['vehicle_model'];
      return Booking.fromJson(flat);
    }).toList();
  }
}
