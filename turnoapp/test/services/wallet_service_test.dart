import 'package:flutter_test/flutter_test.dart';

import 'package:turnoapp/services/wallet_service.dart';
import 'package:turnoapp/core/supabase_client.dart';

import '../test_helpers/mock_supabase.dart';

void main() {
  setUp(() {
    registerFallbacks();
    SupabaseConfig.setClientForTest(createMockSupabaseClient());
  });

  tearDown(() {
    SupabaseConfig.clearTestClient();
  });

  group('WalletService fees', () {
    test('topupFeeForAmount 0 returns 0', () {
      expect(WalletService().topupFeeForAmount(0), 0);
    });

    test('topupFeeForAmount negative returns 0', () {
      expect(WalletService().topupFeeForAmount(-1000), 0);
    });

    test('topupFeeForAmount returns 1% rounded', () {
      expect(WalletService().topupFeeForAmount(10000), 100);
      expect(WalletService().topupFeeForAmount(19900), 199);
    });

    test('topupChargedAmount adds fee', () {
      expect(WalletService().topupChargedAmount(10000), 10100);
    });
  });
}
