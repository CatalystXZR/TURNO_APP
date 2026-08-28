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
import '../core/error_mapper.dart';
import 'dart:typed_data';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/user_profile.dart';
import '../models/enums.dart';

class ProfileService {
  final _client = SupabaseConfig.client;
  static const String _profilePhotosBucket = 'profile-photos';

  Future<void> saveBasicProfile({
    required String userId,
    required String fullName,
    String? universityId,
    bool? acceptedTerms,
    String? termsVersion,
    bool? hasValidLicense,
    String? roleMode,
    String? vehicleBrand,
    String? vehicleModel,
    String? vehicleVersion,
    int? vehicleDoors,
    String? vehiclePlate,
  }) async {
    try {
      await _client.from('users_profile').upsert({
        'id': userId,
        'full_name': fullName,
        if (universityId != null) 'university_id': universityId,
        if (acceptedTerms != null) 'accepted_terms': acceptedTerms,
        if (acceptedTerms == true)
          'accepted_terms_at': DateTime.now().toIso8601String(),
        if (termsVersion != null) 'terms_version': termsVersion,
        if (hasValidLicense != null) 'has_valid_license': hasValidLicense,
        if (hasValidLicense == true)
          'license_checked_at': DateTime.now().toIso8601String(),
        if (roleMode != null) 'role_mode': roleMode,
        if (vehicleBrand != null) 'vehicle_brand': vehicleBrand,
        if (vehicleModel != null) 'vehicle_model': vehicleModel,
        if (vehicleVersion != null) 'vehicle_version': vehicleVersion,
        if (vehicleDoors != null) 'vehicle_doors': vehicleDoors,
        if (vehiclePlate != null)
          'vehicle_plate': vehiclePlate.toUpperCase().replaceAll(' ', ''),
      });
    } catch (e) {
      throw Exception(AppErrorMapper.toMessage(e));
    }
  }

  Future<UserProfile> updateSafetyProfile({
    required String emergencyContact,
    String? safetyNotes,
    bool? hasValidLicense,
  }) async {
    final uid = _client.auth.currentUser?.id;
    if (uid == null) throw Exception('Usuario no autenticado.');
    final data = await _client
        .from('users_profile')
        .update({
          'emergency_contact': emergencyContact,
          'safety_notes': safetyNotes,
          if (hasValidLicense != null) 'has_valid_license': hasValidLicense,
          if (hasValidLicense == true)
            'license_checked_at': DateTime.now().toIso8601String(),
        })
        .eq('id', uid)
        .select()
        .maybeSingle();
    if (data == null) throw Exception('Usuario no encontrado.');
    return UserProfile.fromJson(data);
  }

  Future<UserProfile> updateProfileDetails({
    required String fullName,
    String? profilePhotoUrl,
    String? vehicleModel,
    String? vehicleBrand,
    String? vehicleVersion,
    int? vehicleDoors,
    String? vehiclePlate,
    String? vehicleColor,
    String? emergencyContact,
    String? safetyNotes,
    bool? hasValidLicense,
  }) async {
    try {
      final uid = _client.auth.currentUser?.id;
      if (uid == null) throw Exception('Usuario no autenticado.');
      final data = await _client
          .from('users_profile')
          .update({
            'full_name': fullName,
            'profile_photo_url': profilePhotoUrl,
            'vehicle_brand': vehicleBrand,
            'vehicle_model': vehicleModel,
            'vehicle_version': vehicleVersion,
            'vehicle_doors': vehicleDoors,
            'vehicle_plate': vehiclePlate,
            'vehicle_color': vehicleColor,
            'emergency_contact': emergencyContact,
            'safety_notes': safetyNotes,
            if (hasValidLicense != null) 'has_valid_license': hasValidLicense,
            if (hasValidLicense == true)
              'license_checked_at': DateTime.now().toIso8601String(),
          })
          .eq('id', uid)
          .select()
          .maybeSingle();
      if (data == null) throw Exception('Perfil no encontrado.');
      return UserProfile.fromJson(data);
    } catch (e) {
      throw Exception(AppErrorMapper.toMessage(e));
    }
  }

  Future<String> uploadProfilePhoto({
    required Uint8List bytes,
    required String fileName,
  }) async {
    final uid = _client.auth.currentUser?.id;
    if (uid == null) throw Exception('Usuario no autenticado.');
    final ext = _fileExtension(fileName);
    final path = '$uid/avatar.$ext';

    await _client.storage.from(_profilePhotosBucket).uploadBinary(
          path,
          bytes,
          fileOptions: FileOptions(
            upsert: true,
            cacheControl: '3600',
            contentType: _contentTypeForExt(ext),
          ),
        );

    return _client.storage.from(_profilePhotosBucket).getPublicUrl(path);
  }

  String _fileExtension(String fileName) {
    final lower = fileName.toLowerCase();
    if (lower.endsWith('.png')) return 'png';
    if (lower.endsWith('.webp')) return 'webp';
    return 'jpg';
  }

  String _contentTypeForExt(String ext) {
    switch (ext) {
      case 'png':
        return 'image/png';
      case 'webp':
        return 'image/webp';
      default:
        return 'image/jpeg';
    }
  }

  Future<UserProfile?> getProfile() async {
    try {
      final uid = _client.auth.currentUser?.id;
      if (uid == null) return null;

      final data = await _client
          .rpc('get_profile_current_state', params: {'p_user_id': uid});

      if (data == null) return null;

      final row = data is List ? data.firstOrNull : data;
      if (row == null) return null;
      return UserProfile.fromJson(Map<String, dynamic>.from(row));
    } catch (e) {
      throw Exception(AppErrorMapper.toMessage(e));
    }
  }

  Future<UserProfile?> getProfileById(String userId) async {
    final data = await _client
        .from('users_profile')
        .select()
        .eq('id', userId)
        .maybeSingle();

    if (data == null) return null;
    return UserProfile.fromJson(data);
  }

  /// Upserts the profile. Used after sign-up to set name, university, campus.
  Future<UserProfile> upsertProfile(UserProfile profile) async {
    final data = await _client
        .from('users_profile')
        .upsert(profile.toJson())
        .select()
        .maybeSingle();
    if (data == null) throw Exception('No se pudo guardar el perfil.');
    return UserProfile.fromJson(data);
  }

  Future<UserProfile> setRoleMode(RoleMode mode) async {
    final uid = _client.auth.currentUser?.id;
    if (uid == null) throw Exception('Usuario no autenticado.');
    final data = await _client
        .from('users_profile')
        .update({
          'role_mode': mode == RoleMode.driver ? 'driver' : 'passenger',
        })
        .eq('id', uid)
        .select()
        .maybeSingle();
    if (data == null) throw Exception('No se pudo actualizar el rol.');
    return UserProfile.fromJson(data);
  }
}
