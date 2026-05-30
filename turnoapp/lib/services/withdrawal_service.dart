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

import '../core/supabase_client.dart';
import '../core/constants.dart';

class WithdrawalService {
  final _client = SupabaseConfig.client;

  /// Minimum withdrawal: $20.000 CLP.
  Future<void> requestWithdrawal(int amountCLP) async {
    if (amountCLP < AppConstants.minWithdrawalCLP) {
      throw Exception(
          'El monto mínimo de retiro es \$${AppConstants.minWithdrawalCLP}');
    }
    final uid = _client.auth.currentUser!.id;
    await _client.from('withdrawals').insert({
      'driver_id': uid,
      'amount': amountCLP,
      'status': 'requested',
    });
  }

  Future<List<Map<String, dynamic>>> getWithdrawals() async {
    final uid = _client.auth.currentUser!.id;
    return _client
        .from('withdrawals')
        .select()
        .eq('driver_id', uid)
        .order('requested_at', ascending: false);
  }
}
