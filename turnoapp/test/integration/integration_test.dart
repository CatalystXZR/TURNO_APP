import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const _url = 'https://zawaevytpkvejhekyokw.supabase.co';
const _anonKey =
    'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Inphd2Fldnl0cGt2ZWpoZWt5b2t3Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzMzNzAwMjEsImV4cCI6MjA4ODk0NjAyMX0.W08CHoJ_jKSHzBvQnw-HUfjTBSdNVGBs6N89h_QPaOM';

const _passengerEmail = 'test123@turno.app';
const _driverEmail = 'testdriver@turno.app';
const _password = 'test123456';
const _driverId = '036c3e6a-dd05-44b3-896c-1a32e7a0f9c9';

void main() {
  final client = SupabaseClient(_url, _anonKey);

  test('Auth: sign in as passenger', () async {
    final response = await client.auth.signInWithPassword(
      email: _passengerEmail,
      password: _password,
    );
    expect(response.session, isNotNull);
    expect(response.user!.email, _passengerEmail);
  });

  test('Auth: sign in as driver', () async {
    final response = await client.auth.signInWithPassword(
      email: _driverEmail,
      password: _password,
    );
    expect(response.session, isNotNull);
    expect(response.user!.email, _driverEmail);
  });

  test('Profile and wallet exist after signup', () async {
    await client.auth.signInWithPassword(
      email: _passengerEmail,
      password: _password,
    );
    final uid = client.auth.currentUser!.id;

    final profile = await client
        .from('users_profile')
        .select()
        .eq('id', uid)
        .maybeSingle();
    expect(profile, isNotNull);

    final wallet = await client
        .from('wallets')
        .select()
        .eq('user_id', uid)
        .maybeSingle();
    expect(wallet, isNotNull);

    await client.auth.signOut();
  });

  test('Public data: universities and campuses', () async {
    final unis = await client.from('universities').select().order('name');
    expect(unis.length, greaterThanOrEqualTo(1));

    final campuses = await client.from('campuses').select().order('name');
    expect(campuses.length, greaterThanOrEqualTo(1));
  });

  test('Rides: create and search', () async {
    // Sign in as driver and set up profile
    await client.auth.signInWithPassword(
      email: _driverEmail,
      password: _password,
    );
    final driverUid = client.auth.currentUser!.id;

    await client.from('users_profile').upsert({
      'id': driverUid,
      'full_name': 'Test Driver',
      'role_mode': 'driver',
      'accepted_terms': true,
      'accepted_terms_at': DateTime.now().toUtc().toIso8601String(),
      'has_valid_license': true,
      'license_checked_at': DateTime.now().toUtc().toIso8601String(),
      'vehicle_brand': 'Toyota',
      'vehicle_model': 'Yaris',
      'vehicle_version': '1.5',
      'vehicle_doors': 4,
      'vehicle_plate': 'TEST01',
    });

    final uni = await client.from('universities').select('id').limit(1).single();
    final campus = await client
        .from('campuses')
        .select('id')
        .eq('university_id', uni['id'])
        .limit(1)
        .single();

    // Create ride with a valid commune
    final ride = await client.from('rides').insert({
      'driver_id': driverUid,
      'university_id': uni['id'],
      'campus_id': campus['id'],
      'origin_commune': 'Providencia',
      'meeting_point': 'Av. Providencia 2000',
      'direction': 'to_campus',
      'departure_at':
          DateTime.now().add(const Duration(days: 1)).toUtc().toIso8601String(),
      'seat_price': 2000,
      'platform_fee': 190,
      'driver_net_amount': 1810,
      'seats_total': 3,
      'seats_available': 3,
      'status': 'active',
    }).select().single();

    expect(ride['id'], isNotNull);
    expect(ride['status'], 'active');
    expect(ride['seats_available'], 3);

    // Search as passenger
    await client.auth.signOut();
    await client.auth.signInWithPassword(
      email: _passengerEmail,
      password: _password,
    );

    final results = await client
        .from('rides')
        .select('*')
        .eq('status', 'active')
        .gt('seats_available', 0)
        .order('departure_at')
        .limit(20);

    expect(results, isNotEmpty);
    expect(results.any((r) => r['id'] == ride['id']), true);

    await client.auth.signOut();
  });

  test('Wallet: sandbox_topup adds balance', () async {
    await client.auth.signInWithPassword(
      email: _passengerEmail,
      password: _password,
    );
    final uid = client.auth.currentUser!.id;

    final before = await client
        .from('wallets')
        .select('balance_available')
        .eq('user_id', uid)
        .maybeSingle();
    final initialBalance = (before?['balance_available'] as int?) ?? 0;

    await client.rpc('sandbox_topup', params: {'p_amount': 5000});

    final after = await client
        .from('wallets')
        .select('balance_available')
        .eq('user_id', uid)
        .maybeSingle();
    expect(after, isNotNull);
    expect((after!['balance_available'] as int), greaterThanOrEqualTo(initialBalance + 5000));

    await client.auth.signOut();
  });

  test('Booking: full lifecycle (create -> accept -> arrive -> board -> start -> complete)', () async {
    // Ensure no blocks between test accounts
    await client.auth.signInWithPassword(email: _passengerEmail, password: _password);
    await client.rpc('unblock_user', params: {'p_blocked_user_id': _driverId});
    await client.auth.signOut();

    // 1. Driver sets up and creates ride
    await client.auth.signInWithPassword(email: _driverEmail, password: _password);
    final driverUid = client.auth.currentUser!.id;

    // Also unblock driver side
    await client.rpc('unblock_user', params: {'p_blocked_user_id': '1e59740e-b6e8-4de8-b332-260cef4c69e9'});
    await client.auth.signOut();
    await client.auth.signInWithPassword(email: _driverEmail, password: _password);

    await client.from('users_profile').upsert({
      'id': driverUid,
      'full_name': 'Test Driver',
      'role_mode': 'driver',
      'accepted_terms': true,
      'accepted_terms_at': DateTime.now().toUtc().toIso8601String(),
      'has_valid_license': true,
      'license_checked_at': DateTime.now().toUtc().toIso8601String(),
      'vehicle_brand': 'Toyota',
      'vehicle_model': 'Yaris',
      'vehicle_version': '1.5',
      'vehicle_doors': 4,
      'vehicle_plate': 'TEST01',
    });

    final uni = await client.from('universities').select('id').limit(1).single();
    final campus = await client.from('campuses').select('id').eq('university_id', uni['id']).limit(1).single();

    final ride = await client.from('rides').insert({
      'driver_id': driverUid,
      'university_id': uni['id'],
      'campus_id': campus['id'],
      'origin_commune': 'Vitacura',
      'meeting_point': 'Test Point',
      'direction': 'to_campus',
      'departure_at': DateTime.now().add(const Duration(hours: 2)).toUtc().toIso8601String(),
      'seat_price': 2000,
      'platform_fee': 190,
      'driver_net_amount': 1810,
      'seats_total': 3,
      'seats_available': 3,
      'status': 'active',
    }).select().single();

    final rideId = ride['id'];
    expect(rideId, isNotEmpty);

    // 2. Passenger books
    await client.auth.signOut();
    await client.auth.signInWithPassword(email: _passengerEmail, password: _password);

    // Ensure balance
    await client.rpc('sandbox_topup', params: {'p_amount': 10000});

    // Create booking
    final bookingId = await client.rpc('create_booking', params: {'p_ride_id': rideId});
    expect(bookingId, isNotEmpty);

    // 3. Driver accepts, arrives
    await client.auth.signOut();
    await client.auth.signInWithPassword(email: _driverEmail, password: _password);

    await client.rpc('driver_accept_booking', params: {'p_booking_id': bookingId});
    await client.rpc('driver_mark_arriving', params: {'p_booking_id': bookingId});
    await client.rpc('driver_mark_arrived', params: {'p_booking_id': bookingId});

    // Check dispatch status
    var booking = await client.from('bookings').select().eq('id', bookingId).maybeSingle();
    expect(booking!['dispatch_status'], 'driver_arrived');

    // 4. Passenger boards
    await client.auth.signOut();
    await client.auth.signInWithPassword(email: _passengerEmail, password: _password);

    await client.rpc('confirm_boarding', params: {'p_booking_id': bookingId});

    booking = await client.from('bookings').select().eq('id', bookingId).maybeSingle();
    expect(booking!['dispatch_status'], 'passenger_boarded');

    // 5. Driver starts and completes
    await client.auth.signOut();
    await client.auth.signInWithPassword(email: _driverEmail, password: _password);

    await client.rpc('driver_start_trip', params: {'p_booking_id': bookingId});
    await client.rpc('driver_complete_trip', params: {'p_booking_id': bookingId});

    booking = await client.from('bookings').select().eq('id', bookingId).maybeSingle();
    expect(booking!['status'], 'completed');
    expect(booking['dispatch_status'], 'completed');

    await client.auth.signOut();
  });

  test('Report & Block RPCs', () async {
    await client.auth.signInWithPassword(email: _passengerEmail, password: _password);

    // Report driver
    await client.rpc('report_user', params: {
      'p_reported_user_id': _driverId,
      'p_reason_category': 'other',
      'p_details': 'Integration test',
    });

    // Block driver (RPC returns void, not boolean)
    await client.rpc('block_user', params: {
      'p_blocked_user_id': _driverId,
    });

    // Check blocked
    final isBlocked = await client.rpc('is_user_blocked', params: {
      'p_target_user_id': _driverId,
    });
    expect(isBlocked, true);

    // Unblock
    await client.rpc('unblock_user', params: {
      'p_blocked_user_id': _driverId,
    });

    // Verify unblocked
    final stillBlocked = await client.rpc('is_user_blocked', params: {
      'p_target_user_id': _driverId,
    });
    expect(stillBlocked, false);

    await client.auth.signOut();
  });
}
