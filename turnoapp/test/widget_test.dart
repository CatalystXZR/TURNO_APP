import 'package:flutter_test/flutter_test.dart';

import 'test_helpers/mock_supabase.dart';
import 'test_helpers/factories.dart';

void main() {
  test('test infrastructure loads correctly', () {
    registerFallbacks();
    final client = createMockSupabaseClient();
    expect(client, isNotNull);

    final auth = client.auth;
    stubAuthUser(auth as MockGoTrueClient, uid: 'test-uid');
    expect(auth.currentUser, isNotNull);
    expect(auth.currentUser!.id, 'test-uid');
  });

  test('factories produce valid JSON', () {
    final profile = mockUserProfile(id: 'p1', fullName: 'Test');
    expect(profile['id'], 'p1');
    expect(profile['full_name'], 'Test');

    final ride = mockRide(id: 'r1', seatsTotal: 4);
    expect(ride['id'], 'r1');
    expect(ride['seats_total'], 4);

    final booking = mockBooking(id: 'b1');
    expect(booking['id'], 'b1');
    expect(booking['status'], 'reserved');

    final wallet = mockWallet(balanceAvailable: 10000);
    expect(wallet['balance_available'], 10000);

    final tx = mockTransaction(type: 'topup');
    expect(tx['type'], 'topup');
  });
}
