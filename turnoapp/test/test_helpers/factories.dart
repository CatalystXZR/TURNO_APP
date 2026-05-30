import 'dart:math';

const _testUuid = '00000000-0000-4000-a000-000000000';

String _uuid(int seed) =>
    '00000000-0000-4000-a000-${seed.toString().padLeft(12, '0')}';

String ts(int hoursAgo) =>
    DateTime.now().toUtc().subtract(Duration(hours: hoursAgo)).toIso8601String();

final now = DateTime.now().toUtc();
String nowTs = now.toIso8601String();
String futureTs = now.add(const Duration(days: 1)).toIso8601String();

Map<String, dynamic> mockUserProfile({
  String id = '00000000-0000-4000-a000-000000000001',
  String fullName = 'Test User',
  String roleMode = 'passenger',
  bool acceptedTerms = true,
  bool hasValidLicense = false,
  int strikesCount = 0,
  double ratingAvg = 5.0,
  int ratingCount = 0,
}) {
  return {
    'id': id,
    'full_name': fullName,
    'university_id': null,
    'campus_id': null,
    'role_mode': roleMode,
    'accepted_terms': acceptedTerms,
    'accepted_terms_at': acceptedTerms ? nowTs : null,
    'terms_version': null,
    'has_valid_license': hasValidLicense,
    'license_checked_at': hasValidLicense ? nowTs : null,
    'is_driver_verified': false,
    'strikes_count': strikesCount,
    'suspended_until': null,
    'vehicle_suspended_until': null,
    'emergency_contact': '+56912345678',
    'safety_notes': null,
    'profile_photo_url': null,
    'rating_avg': ratingAvg,
    'rating_count': ratingCount,
    'vehicle_model': roleMode == 'driver' ? 'Yaris' : null,
    'vehicle_brand': roleMode == 'driver' ? 'Toyota' : null,
    'vehicle_version': roleMode == 'driver' ? '1.5' : null,
    'vehicle_doors': roleMode == 'driver' ? 4 : null,
    'vehicle_plate': roleMode == 'driver' ? 'ABC123' : null,
    'vehicle_color': null,
    'created_at': ts(24),
  };
}

Map<String, dynamic> mockRide({
  String id = '',
  String driverId = '00000000-0000-4000-a000-000000000001',
  String universityId = '00000000-0000-4000-a000-000000000100',
  String campusId = '00000000-0000-4000-a000-000000000200',
  String originCommune = 'Las Condes',
  String meetingPoint = 'Av. Apoquindo 4500',
  bool isRadial = false,
  String direction = 'to_campus',
  String departureAt = '',
  int seatPrice = 2000,
  int platformFee = 190,
  int driverNetAmount = 1810,
  int seatsTotal = 3,
  int seatsAvailable = 3,
  String status = 'active',
  String driverName = 'Test Driver',
  double driverRating = 4.5,
  int driverRatingCount = 10,
  String universityName = 'U. del Desarrollo',
  String campusName = 'Las Condes',
}) {
  return {
    'id': id.isEmpty ? _uuid(Random().nextInt(999999)) : id,
    'driver_id': driverId,
    'university_id': universityId,
    'university_code': 'UDD',
    'campus_id': campusId,
    'origin_commune': originCommune,
    'meeting_point': meetingPoint,
    'is_radial': isRadial,
    'direction': direction,
    'departure_at': departureAt.isEmpty ? futureTs : departureAt,
    'seat_price': seatPrice,
    'platform_fee': platformFee,
    'driver_net_amount': driverNetAmount,
    'seats_total': seatsTotal,
    'seats_available': seatsAvailable,
    'status': status,
    'cancel_reason': null,
    'cancelled_at': null,
    'created_at': ts(2),
    'driver_name': driverName,
    'driver_rating': driverRating,
    'driver_rating_count': driverRatingCount,
    'university_name': universityName,
    'campus_name': campusName,
  };
}

Map<String, dynamic> mockBooking({
  String id = '',
  String rideId = '',
  String passengerId = '00000000-0000-4000-a000-000000000002',
  String driverId = '00000000-0000-4000-a000-000000000001',
  String driverName = 'Test Driver',
  double driverRating = 4.5,
  String passengerName = 'Test Passenger',
  String status = 'reserved',
  String dispatchStatus = 'reserved',
  int amountTotal = 2000,
}) {
  return {
    'id': id.isEmpty ? _uuid(Random().nextInt(999999)) : id,
    'ride_id': rideId.isEmpty ? _uuid(Random().nextInt(999999)) : rideId,
    'passenger_id': passengerId,
    'driver_id': driverId,
    'driver_name': driverName,
    'driver_rating': driverRating,
    'driver_photo_url': null,
    'driver_vehicle_plate': 'ABC123',
    'driver_vehicle_model': 'Yaris',
    'driver_emergency_contact': '+56912345678',
    'passenger_name': passengerName,
    'passenger_rating': 4.0,
    'passenger_photo_url': null,
    'passenger_vehicle_plate': null,
    'passenger_vehicle_model': null,
    'passenger_rating_count': 5,
    'driver_rating_count': 10,
    'amount_total': amountTotal,
    'status': status,
    'dispatch_status': dispatchStatus,
    'confirmed_at': null,
    'reported_no_show_at': null,
    'no_show_notes': null,
    'driver_accepted_at': null,
    'driver_arriving_at': null,
    'driver_arrived_at': null,
    'passenger_boarded_at': null,
    'trip_started_at': null,
    'trip_completed_at': null,
    'cancelled_at': null,
    'cancel_reason': null,
    'created_at': ts(1),
    'ride_origin_commune': 'Las Condes',
    'ride_departure_at': futureTs,
    'university_name': 'U. del Desarrollo',
    'campus_name': 'Las Condes',
  };
}

Map<String, dynamic> mockWallet({
  String userId = '00000000-0000-4000-a000-000000000001',
  int balanceAvailable = 50000,
  int balanceHeld = 0,
}) {
  return {
    'user_id': userId,
    'balance_available': balanceAvailable,
    'balance_held': balanceHeld,
    'updated_at': nowTs,
  };
}

Map<String, dynamic> mockTransaction({
  String id = '',
  String userId = '00000000-0000-4000-a000-000000000001',
  String bookingId = '',
  String type = 'topup',
  int amount = 10000,
  Map<String, dynamic> metadata = const {},
}) {
  return {
    'id': id.isEmpty ? _uuid(Random().nextInt(999999)) : id,
    'user_id': userId,
    'booking_id': bookingId.isEmpty ? null : bookingId,
    'type': type,
    'amount': amount,
    'metadata': metadata,
    'created_at': ts(1),
  };
}

Map<String, dynamic> mockUniversity({
  String id = '',
  String name = 'Universidad del Desarrollo',
  String code = 'UDD',
}) {
  return {
    'id': id.isEmpty ? _uuid(Random().nextInt(999999)) : id,
    'name': name,
    'code': code,
    'created_at': ts(720),
  };
}

Map<String, dynamic> mockCampus({
  String id = '',
  String universityId = '',
  String name = 'Las Condes',
}) {
  return {
    'id': id.isEmpty ? _uuid(Random().nextInt(999999)) : id,
    'university_id': universityId.isEmpty ? _uuid(100) : universityId,
    'name': name,
    'created_at': ts(720),
  };
}

Map<String, dynamic> mockReview({
  String id = '',
  String bookingId = '',
  String rideId = '',
  String reviewerId = '00000000-0000-4000-a000-000000000001',
  int stars = 5,
  String comment = 'Excelente',
  String reviewerRole = 'passenger',
  String reviewerName = 'Test Reviewer',
}) {
  return {
    'id': id.isEmpty ? _uuid(Random().nextInt(999999)) : id,
    'booking_id': bookingId.isEmpty ? _uuid(Random().nextInt(999999)) : bookingId,
    'ride_id': rideId.isEmpty ? _uuid(Random().nextInt(999999)) : rideId,
    'stars': stars,
    'comment': comment,
    'created_at': ts(1),
    'reviewer_id': reviewerId,
    'reviewer_role': reviewerRole,
    'reviewer_name': reviewerName,
    'reviewer_photo_url': null,
    'reviewer_rating_avg': 4.5,
    'reviewer_rating_count': 10,
  };
}

Map<String, dynamic> mockFavoriteUser({
  String userId = '00000000-0000-4000-a000-000000000001',
  String fullName = 'Favorite User',
  String roleMode = 'driver',
  double ratingAvg = 4.8,
  int ratingCount = 15,
}) {
  return {
    'favorite_user_id': userId,
    'full_name': fullName,
    'role_mode': roleMode,
    'rating_avg': ratingAvg,
    'rating_count': ratingCount,
    'profile_photo_url': null,
    'vehicle_model': 'Yaris',
    'vehicle_plate': 'ABC123',
    'created_at': ts(1),
  };
}
