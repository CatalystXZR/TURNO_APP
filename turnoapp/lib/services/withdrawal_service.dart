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
import '../core/constants.dart';

class WithdrawalService {
  final _client = SupabaseConfig.client;

  Future<double> _getAvailableBalance() async {
    final uid = _client.auth.currentUser?.id;
    if (uid == null) throw Exception('Usuario no autenticado.');
    final data = await _client.from('wallets').select('balance_available').eq('user_id', uid).maybeSingle();
    if (data == null) return 0;
    return (data['balance_available'] as num).toDouble();
  }

  Future<void> requestWithdrawal(int amountCLP) async {
    if (amountCLP < AppConstants.minWithdrawalCLP) {
      throw Exception(
          'El monto minimo de retiro es \$${AppConstants.minWithdrawalCLP}');
    }
    final balance = await _getAvailableBalance();
    if (amountCLP > balance) {
      throw Exception(
          'Saldo insuficiente. Tu saldo disponible es \$${balance.toInt()}');
    }
    final uid = _client.auth.currentUser?.id;
    if (uid == null) throw Exception('Usuario no autenticado.');

    await _client.rpc('sandbox_withdraw', params: {
      'p_amount': amountCLP,
    });
  }

  Future<List<Map<String, dynamic>>> getWithdrawals() async {
    final uid = _client.auth.currentUser?.id;
    if (uid == null) return [];
    return _client
        .from('withdrawals')
        .select()
        .eq('driver_id', uid)
        .order('requested_at', ascending: false);
  }
}
