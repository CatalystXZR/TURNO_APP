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

import '../core/supabase_client.dart';
import '../models/ride.dart';

class RideService {
  final _client = SupabaseConfig.client;

  Future<Ride> createRide(Ride ride) async {
    final data = await _client
        .from('rides')
        .insert(ride.toInsertJson())
        .select()
        .single();
    return Ride.fromJson(data);
  }

  Future<void> cancelRide(
    String rideId, {
    String reason = 'cancelled_by_driver',
  }) async {
    await _client.rpc('driver_cancel_ride', params: {
      'p_ride_id': rideId,
      'p_reason': reason,
    });
  }

  /// Search rides with optional filters.
  Future<List<Ride>> searchRides({
    String? campusId,
    String? originCommune,
    String? direction, // 'to_campus' | 'from_campus'
    DateTime? date,
    int limit = 50,
  }) async {
    final currentUserId = _client.auth.currentUser?.id;
    var query = _client
        .from('rides')
        .select('''
          *,
          users_profile!driver_id(full_name, rating_avg, rating_count),
          campuses!campus_id(name),
          universities!university_id(name, code)
        ''')
        .eq('status', 'active')
        .gt('seats_available', 0)
        .gt('departure_at', DateTime.now().toIso8601String());

    if (currentUserId != null) {
      query = query.neq('driver_id', currentUserId);
    }

    if (campusId != null) query = query.eq('campus_id', campusId);
    if (originCommune != null)
      query = query.eq('origin_commune', originCommune);
    if (direction != null) query = query.eq('direction', direction);

    if (date != null) {
      final start = DateTime(date.year, date.month, date.day);
      final end = start.add(const Duration(days: 1));
      query = query
          .gte('departure_at', start.toIso8601String())
          .lt('departure_at', end.toIso8601String());
    }

    final rows = await query.order('departure_at').limit(limit);

    return rows.map((row) {
      // flatten joined fields
      final flat = Map<String, dynamic>.from(row);
      final driver = row['users_profile'] as Map?;
      flat['driver_name'] = driver?['full_name'];
      flat['driver_rating'] = driver?['rating_avg'];
      flat['driver_rating_count'] = driver?['rating_count'];
      flat['campus_name'] = (row['campuses'] as Map?)?['name'];
      flat['university_name'] = (row['universities'] as Map?)?['name'];
      flat['university_code'] = (row['universities'] as Map?)?['code'];
      return Ride.fromJson(flat);
    }).toList();
  }

  Future<Ride?> getRideById(String rideId) async {
    final data = await _client.from('rides').select('''
          *,
          users_profile!driver_id(full_name, rating_avg, rating_count),
          campuses!campus_id(name),
          universities!university_id(name, code)
        ''').eq('id', rideId).maybeSingle();
    if (data == null) return null;
    final flat = Map<String, dynamic>.from(data);
    final driver = data['users_profile'] as Map?;
    flat['driver_name'] = driver?['full_name'];
    flat['driver_rating'] = driver?['rating_avg'];
    flat['driver_rating_count'] = driver?['rating_count'];
    flat['campus_name'] = (data['campuses'] as Map?)?['name'];
    flat['university_name'] = (data['universities'] as Map?)?['name'];
    flat['university_code'] = (data['universities'] as Map?)?['code'];
    return Ride.fromJson(flat);
  }

  /// Returns all rides published by the current driver.
  Future<List<Ride>> getMyRides({int limit = 80}) async {
    final uid = _client.auth.currentUser!.id;
    final rows = await _client
        .from('rides')
        .select('''
          *,
          campuses!campus_id(name),
          universities!university_id(name, code)
        ''')
        .eq('driver_id', uid)
        .order('departure_at', ascending: false)
        .limit(limit);
    return rows.map((row) {
      final flat = Map<String, dynamic>.from(row);
      flat['campus_name'] = (row['campuses'] as Map?)?['name'];
      flat['university_name'] = (row['universities'] as Map?)?['name'];
      flat['university_code'] = (row['universities'] as Map?)?['code'];
      return Ride.fromJson(flat);
    }).toList();
  }
}
