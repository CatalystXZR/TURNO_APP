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
import '../models/wallet.dart';
import '../models/transaction.dart';

class WalletService {
  final _client = SupabaseConfig.client;

  int topupFeeForAmount(int amountCLP) {
    if (amountCLP <= 0) return 0;
    return ((amountCLP * 0.01)).round();
  }

  int topupChargedAmount(int amountCLP) {
    return amountCLP + topupFeeForAmount(amountCLP);
  }

  Future<void> ensureWalletExists({required String userId}) async {
    await _client.from('wallets').upsert({
      'user_id': userId,
    }, onConflict: 'user_id');
  }

  Future<Wallet?> getWallet() async {
    final uid = _client.auth.currentUser?.id;
    if (uid == null) return null;

    final data =
        await _client.from('wallets').select().eq('user_id', uid).maybeSingle();

    if (data == null) return null;
    return Wallet.fromJson(data);
  }

  Future<List<Transaction>> getTransactions({int limit = 30}) async {
    final uid = _client.auth.currentUser?.id;
    if (uid == null) return [];
    final rows = await _client
        .from('transactions')
        .select()
        .eq('user_id', uid)
        .order('created_at', ascending: false)
        .limit(limit);
    return rows.map(Transaction.fromJson).toList();
  }

  /// Calls a Supabase Edge Function that creates a Fintoc Checkout Session.
  /// Returns the `redirect_url` for the user to complete payment.
  ///
  /// The edge function builds success/cancel HTTPS URLs from APP_BASE_URL
  /// (Fintoc requires HTTPS; the app listens for those links to return).
  Future<String> createTopupIntent(int amountCLP) async {
    final response = await _client.functions.invoke(
      'create-topup-intent',
      body: {'amount': amountCLP},
    );

    if (response.data == null) {
      throw Exception('No se pudo conectar con el proveedor de pagos.');
    }

    final data = response.data as Map<String, dynamic>;

    if ((data['status'] as String?) == 'disabled') {
      throw Exception('payment_provider_disabled');
    }

    if (data.containsKey('error')) {
      throw Exception(
          data['error'] as String? ?? 'Error en el proveedor de pagos.');
    }

    final redirectUrl = data['redirect_url'];
    if (redirectUrl == null || redirectUrl is! String || redirectUrl.isEmpty) {
      throw Exception('Respuesta invalida del proveedor de pagos.');
    }

    return redirectUrl;
  }

  /// Sandbox topup - adds balance directly without external payment provider.
  Future<void> sandboxTopup(int amountCLP) async {
    if (amountCLP <= 0) {
      throw Exception('Monto inválido');
    }
    await _client.rpc('sandbox_topup', params: {
      'p_amount': amountCLP,
    });
  }

  /// Sandbox withdrawal - requests payout directly without external provider.
  Future<void> sandboxWithdraw(int amountCLP) async {
    if (amountCLP <= 0) {
      throw Exception('Monto inválido');
    }
    await _client.rpc('sandbox_withdraw', params: {
      'p_amount': amountCLP,
    });
  }

  /// Delete user account - complies with Apple App Store policy.
  Future<void> deleteUserAccount({String? reason}) async {
    final params = <String, dynamic>{};
    if (reason != null && reason.trim().isNotEmpty) {
      params['p_reason'] = reason.trim();
    }
    await _client.rpc('delete_user_account', params: params.isEmpty ? null : params);
    await _client.auth.signOut();
  }
}
