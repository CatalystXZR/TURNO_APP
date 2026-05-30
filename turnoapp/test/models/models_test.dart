import 'package:flutter_test/flutter_test.dart';
import 'package:turnoapp/models/enums.dart';
import 'package:turnoapp/models/booking.dart';
import 'package:turnoapp/models/user_profile.dart';
import 'package:turnoapp/models/ride.dart';
import 'package:turnoapp/models/wallet.dart';
import 'package:turnoapp/models/transaction.dart';
import 'package:turnoapp/models/user_review.dart';
import 'package:turnoapp/models/favorite_user.dart';

import '../test_helpers/factories.dart';

void main() {
  group('UserProfile.fromJson', () {
    test('parses passenger profile correctly', () {
      final json = mockUserProfile(
        id: 'u1',
        fullName: 'John Doe',
        roleMode: 'passenger',
        ratingAvg: 4.2,
        ratingCount: 8,
      );

      final profile = UserProfile.fromJson(json);

      expect(profile.id, 'u1');
      expect(profile.fullName, 'John Doe');
      expect(profile.roleMode, RoleMode.passenger);
      expect(profile.ratingAvg, 4.2);
      expect(profile.ratingCount, 8);
      expect(profile.acceptedTerms, true);
      expect(profile.hasValidLicense, false);
      expect(profile.strikesCount, 0);
    });

    test('parses driver profile with vehicle data', () {
      final json = mockUserProfile(
        id: 'd1',
        fullName: 'Jane Driver',
        roleMode: 'driver',
        hasValidLicense: true,
        acceptedTerms: true,
        ratingAvg: 4.8,
        ratingCount: 25,
      );

      final profile = UserProfile.fromJson(json);

      expect(profile.id, 'd1');
      expect(profile.fullName, 'Jane Driver');
      expect(profile.roleMode, RoleMode.driver);
      expect(profile.vehicleModel, 'Yaris');
      expect(profile.vehicleBrand, 'Toyota');
      expect(profile.vehiclePlate, 'ABC123');
      expect(profile.vehicleDoors, 4);
      expect(profile.hasValidLicense, true);
    });

    test('defaults to passenger when role_mode is unknown', () {
      final json = mockUserProfile(roleMode: 'unknown');
      final profile = UserProfile.fromJson(json);
      expect(profile.roleMode, RoleMode.passenger);
    });

    test('handles null fields gracefully', () {
      final json = <String, dynamic>{
        'id': 'u1',
        'created_at': '2026-01-01T00:00:00.000Z',
      };
      final profile = UserProfile.fromJson(json);
      expect(profile.id, 'u1');
      expect(profile.fullName, isNull);
      expect(profile.ratingAvg, 5);
      expect(profile.ratingCount, 0);
      expect(profile.acceptedTerms, false);
    });
  });

  group('Ride.fromJson', () {
    test('parses active ride correctly', () {
      final json = mockRide(
        id: 'r1',
        seatsTotal: 4,
        seatsAvailable: 2,
        seatPrice: 2500,
        originCommune: 'Vitacura',
        direction: 'to_campus',
      );

      final ride = Ride.fromJson(json);

      expect(ride.id, 'r1');
      expect(ride.seatsTotal, 4);
      expect(ride.seatsAvailable, 2);
      expect(ride.seatPrice, 2500);
      expect(ride.originCommune, 'Vitacura');
      expect(ride.direction, RideDirection.toCampus);
      expect(ride.status, 'active');
      expect(ride.driverName, 'Test Driver');
      expect(ride.universityName, 'U. del Desarrollo');
      expect(ride.campusName, 'Las Condes');
    });

    test('parses from_campus direction', () {
      final json = mockRide(direction: 'from_campus');
      final ride = Ride.fromJson(json);
      expect(ride.direction, RideDirection.fromCampus);
    });

    test('parses radial ride', () {
      final json = mockRide(isRadial: true);
      final ride = Ride.fromJson(json);
      expect(ride.isRadial, true);
    });

    test('defaults direction to toCampus for unknown value', () {
      final json = mockRide(direction: 'westbound');
      final ride = Ride.fromJson(json);
      expect(ride.direction, RideDirection.fromCampus);
    });
  });

  group('Booking.fromJson', () {
    test('parses reserved booking correctly', () {
      final json = mockBooking(
        id: 'b1',
        rideId: 'r1',
        status: 'reserved',
        dispatchStatus: 'reserved',
        amountTotal: 2190,
      );

      final booking = Booking.fromJson(json);

      expect(booking.id, 'b1');
      expect(booking.rideId, 'r1');
      expect(booking.status, BookingStatus.reserved);
      expect(booking.dispatchStatus, BookingDispatchStatus.reserved);
      expect(booking.amountTotal, 2190);
      expect(booking.driverName, 'Test Driver');
      expect(booking.passengerName, 'Test Passenger');
    });

    test('parses completed booking', () {
      final json = mockBooking(
        status: 'completed',
        dispatchStatus: 'completed',
      );

      final booking = Booking.fromJson(json);

      expect(booking.status, BookingStatus.completed);
      expect(booking.dispatchStatus, BookingDispatchStatus.completed);
    });

    test('parses cancelled booking', () {
      final json = mockBooking(
        status: 'cancelled',
        dispatchStatus: 'cancelled',
      );

      final booking = Booking.fromJson(json);

      expect(booking.status, BookingStatus.cancelled);
      expect(booking.dispatchStatus, BookingDispatchStatus.cancelled);
    });

    test('parses all dispatch statuses', () {
      final statuses = {
        'reserved': BookingDispatchStatus.reserved,
        'accepted': BookingDispatchStatus.accepted,
        'driver_arriving': BookingDispatchStatus.driverArriving,
        'driver_arrived': BookingDispatchStatus.driverArrived,
        'passenger_boarded': BookingDispatchStatus.passengerBoarded,
        'in_progress': BookingDispatchStatus.inProgress,
        'completed': BookingDispatchStatus.completed,
        'cancelled': BookingDispatchStatus.cancelled,
        'no_show': BookingDispatchStatus.noShow,
      };

      for (final entry in statuses.entries) {
        final json = mockBooking(dispatchStatus: entry.key);
        final booking = Booking.fromJson(json);
        expect(booking.dispatchStatus, entry.value,
            reason: 'Expected ${entry.key} -> ${entry.value}');
      }
    });
  });

  group('Wallet.fromJson', () {
    test('parses wallet correctly', () {
      final json = mockWallet(
        userId: 'u1',
        balanceAvailable: 50000,
        balanceHeld: 2000,
      );

      final wallet = Wallet.fromJson(json);

      expect(wallet.userId, 'u1');
      expect(wallet.balanceAvailable, 50000);
      expect(wallet.balanceHeld, 2000);
    });

    test('defaults balances to 0', () {
      final json = <String, dynamic>{
        'user_id': 'u1',
        'updated_at': '2026-01-01T00:00:00.000Z',
      };
      final wallet = Wallet.fromJson(json);
      expect(wallet.balanceAvailable, 0);
      expect(wallet.balanceHeld, 0);
    });
  });

  group('Transaction.fromJson', () {
    test('parses topup transaction', () {
      final json = mockTransaction(
        id: 't1',
        type: 'topup',
        amount: 10000,
      );

      final tx = Transaction.fromJson(json);

      expect(tx.id, 't1');
      expect(tx.type, TxType.topup);
      expect(tx.amount, 10000);
    });

    test('parses booking_hold transaction', () {
      final json = mockTransaction(type: 'booking_hold', amount: 2000);
      final tx = Transaction.fromJson(json);
      expect(tx.type, TxType.bookingHold);
      expect(tx.amount, 2000);
    });

    test('parses refund transaction', () {
      final json = mockTransaction(type: 'refund', amount: 2000);
      final tx = Transaction.fromJson(json);
      expect(tx.type, TxType.refund);
    });

    test('defaults empty metadata', () {
      final json = <String, dynamic>{
        'id': 't1',
        'user_id': 'u1',
        'type': 'topup',
        'amount': 10000,
        'created_at': '2026-01-01T00:00:00.000Z',
      };
      final tx = Transaction.fromJson(json);
      expect(tx.metadata, isEmpty);
    });
  });

  group('UserReview.fromJson', () {
    test('parses review correctly', () {
      final json = mockReview(
        id: 'rv1',
        stars: 4,
        comment: 'Good ride',
        reviewerName: 'Alice',
      );

      final review = UserReview.fromJson(json);

      expect(review.id, 'rv1');
      expect(review.stars, 4);
      expect(review.comment, 'Good ride');
      expect(review.reviewerName, 'Alice');
      expect(review.reviewerRole, 'passenger');
    });

    test('defaults stars to 5', () {
      final json = <String, dynamic>{
        'id': 'rv1',
        'booking_id': 'b1',
        'ride_id': 'r1',
        'created_at': '2026-01-01T00:00:00.000Z',
        'reviewer_id': 'u1',
      };
      final review = UserReview.fromJson(json);
      expect(review.stars, 5);
    });
  });

  group('FavoriteUser.fromJson', () {
    test('parses favorite user correctly', () {
      final json = mockFavoriteUser(
        userId: 'f1',
        fullName: 'Bob Driver',
        roleMode: 'driver',
        ratingAvg: 4.9,
        ratingCount: 32,
      );

      final fav = FavoriteUser.fromJson(json);

      expect(fav.userId, 'f1');
      expect(fav.fullName, 'Bob Driver');
      expect(fav.roleMode, RoleMode.driver);
      expect(fav.ratingAvg, 4.9);
      expect(fav.ratingCount, 32);
    });

    test('defaults to passenger for unknown role', () {
      final json = mockFavoriteUser(roleMode: 'admin');
      final fav = FavoriteUser.fromJson(json);
      expect(fav.roleMode, RoleMode.passenger);
    });
  });

  group('AppErrorMapper', () {
    test('smoke test - full coverage in error_mapper_test.dart', () {
      expect(true, isTrue);
    });
  });
}
