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

class UserProfile {
  final String id;
  final String? fullName;
  final String? universityId;
  final String? campusId;
  final RoleMode roleMode;
  final bool acceptedTerms;
  final DateTime? acceptedTermsAt;
  final String? termsVersion;
  final bool hasValidLicense;
  final DateTime? licenseCheckedAt;
  final bool isDriverVerified;
  final int strikesCount;
  final DateTime? suspendedUntil;
  final DateTime? vehicleSuspendedUntil;
  final String? emergencyContact;
  final String? safetyNotes;
  final String? profilePhotoUrl;
  final double ratingAvg;
  final int ratingCount;
  final String? vehicleModel;
  final String? vehicleBrand;
  final String? vehicleVersion;
  final int? vehicleDoors;
  final String? vehiclePlate;
  final String? vehicleColor;
  final DateTime createdAt;

  const UserProfile({
    required this.id,
    this.fullName,
    this.universityId,
    this.campusId,
    required this.roleMode,
    required this.acceptedTerms,
    this.acceptedTermsAt,
    this.termsVersion,
    required this.hasValidLicense,
    this.licenseCheckedAt,
    required this.isDriverVerified,
    required this.strikesCount,
    this.suspendedUntil,
    this.vehicleSuspendedUntil,
    this.emergencyContact,
    this.safetyNotes,
    this.profilePhotoUrl,
    required this.ratingAvg,
    required this.ratingCount,
    this.vehicleModel,
    this.vehicleBrand,
    this.vehicleVersion,
    this.vehicleDoors,
    this.vehiclePlate,
    this.vehicleColor,
    required this.createdAt,
  });

  factory UserProfile.fromJson(Map<String, dynamic> json) {
    return UserProfile(
      id: json['id'] as String,
      fullName: json['full_name'] as String?,
      universityId: json['university_id'] as String?,
      campusId: json['campus_id'] as String?,
      roleMode:
          json['role_mode'] == 'driver' ? RoleMode.driver : RoleMode.passenger,
      acceptedTerms: (json['accepted_terms'] as bool?) ?? false,
      acceptedTermsAt: json['accepted_terms_at'] != null
          ? DateTime.parse(json['accepted_terms_at'] as String)
          : null,
      termsVersion: json['terms_version'] as String?,
      hasValidLicense: (json['has_valid_license'] as bool?) ?? false,
      licenseCheckedAt: json['license_checked_at'] != null
          ? DateTime.parse(json['license_checked_at'] as String)
          : null,
      isDriverVerified: (json['is_driver_verified'] as bool?) ?? false,
      strikesCount: (json['strikes_count'] as int?) ?? 0,
      suspendedUntil: json['suspended_until'] != null
          ? DateTime.parse(json['suspended_until'] as String)
          : null,
      vehicleSuspendedUntil: json['vehicle_suspended_until'] != null
          ? DateTime.parse(json['vehicle_suspended_until'] as String)
          : null,
      emergencyContact: json['emergency_contact'] as String?,
      safetyNotes: json['safety_notes'] as String?,
      profilePhotoUrl: json['profile_photo_url'] as String?,
      ratingAvg: (json['rating_avg'] as num?)?.toDouble() ?? 5,
      ratingCount: (json['rating_count'] as int?) ?? 0,
      vehicleModel: json['vehicle_model'] as String?,
      vehicleBrand: json['vehicle_brand'] as String?,
      vehicleVersion: json['vehicle_version'] as String?,
      vehicleDoors: json['vehicle_doors'] as int?,
      vehiclePlate: json['vehicle_plate'] as String?,
      vehicleColor: json['vehicle_color'] as String?,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'full_name': fullName,
        'university_id': universityId,
        'campus_id': campusId,
        'role_mode': roleMode == RoleMode.driver ? 'driver' : 'passenger',
        'accepted_terms': acceptedTerms,
        'accepted_terms_at': acceptedTermsAt?.toIso8601String(),
        'terms_version': termsVersion,
        'has_valid_license': hasValidLicense,
        'license_checked_at': licenseCheckedAt?.toIso8601String(),
        'is_driver_verified': isDriverVerified,
        'strikes_count': strikesCount,
        'suspended_until': suspendedUntil?.toIso8601String(),
        'vehicle_suspended_until': vehicleSuspendedUntil?.toIso8601String(),
        'emergency_contact': emergencyContact,
        'safety_notes': safetyNotes,
        'profile_photo_url': profilePhotoUrl,
        'rating_avg': ratingAvg,
        'rating_count': ratingCount,
        'vehicle_model': vehicleModel,
        'vehicle_brand': vehicleBrand,
        'vehicle_version': vehicleVersion,
        'vehicle_doors': vehicleDoors,
        'vehicle_plate': vehiclePlate,
        'vehicle_color': vehicleColor,
        'created_at': createdAt.toIso8601String(),
      };

  UserProfile copyWith({
    String? fullName,
    String? universityId,
    String? campusId,
    RoleMode? roleMode,
    bool? acceptedTerms,
    DateTime? acceptedTermsAt,
    String? termsVersion,
    bool? hasValidLicense,
    DateTime? licenseCheckedAt,
    bool? isDriverVerified,
    int? strikesCount,
    DateTime? suspendedUntil,
    DateTime? vehicleSuspendedUntil,
    String? emergencyContact,
    String? safetyNotes,
    String? profilePhotoUrl,
    double? ratingAvg,
    int? ratingCount,
    String? vehicleModel,
    String? vehicleBrand,
    String? vehicleVersion,
    int? vehicleDoors,
    String? vehiclePlate,
    String? vehicleColor,
  }) {
    return UserProfile(
      id: id,
      fullName: fullName ?? this.fullName,
      universityId: universityId ?? this.universityId,
      campusId: campusId ?? this.campusId,
      roleMode: roleMode ?? this.roleMode,
      acceptedTerms: acceptedTerms ?? this.acceptedTerms,
      acceptedTermsAt: acceptedTermsAt ?? this.acceptedTermsAt,
      termsVersion: termsVersion ?? this.termsVersion,
      hasValidLicense: hasValidLicense ?? this.hasValidLicense,
      licenseCheckedAt: licenseCheckedAt ?? this.licenseCheckedAt,
      isDriverVerified: isDriverVerified ?? this.isDriverVerified,
      strikesCount: strikesCount ?? this.strikesCount,
      suspendedUntil: suspendedUntil ?? this.suspendedUntil,
      vehicleSuspendedUntil:
          vehicleSuspendedUntil ?? this.vehicleSuspendedUntil,
      emergencyContact: emergencyContact ?? this.emergencyContact,
      safetyNotes: safetyNotes ?? this.safetyNotes,
      profilePhotoUrl: profilePhotoUrl ?? this.profilePhotoUrl,
      ratingAvg: ratingAvg ?? this.ratingAvg,
      ratingCount: ratingCount ?? this.ratingCount,
      vehicleModel: vehicleModel ?? this.vehicleModel,
      vehicleBrand: vehicleBrand ?? this.vehicleBrand,
      vehicleVersion: vehicleVersion ?? this.vehicleVersion,
      vehicleDoors: vehicleDoors ?? this.vehicleDoors,
      vehiclePlate: vehiclePlate ?? this.vehiclePlate,
      vehicleColor: vehicleColor ?? this.vehicleColor,
      createdAt: createdAt,
    );
  }
}
