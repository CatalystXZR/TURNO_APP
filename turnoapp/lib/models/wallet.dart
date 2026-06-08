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

class Wallet {
  final String userId;
  final int balanceAvailable; // CLP
  final int balanceHeld; // CLP retenido en reservas activas
  final DateTime updatedAt;

  const Wallet({
    required this.userId,
    required this.balanceAvailable,
    required this.balanceHeld,
    required this.updatedAt,
  });

  factory Wallet.fromJson(Map<String, dynamic> json) {
    return Wallet(
      userId: json['user_id'] as String,
      balanceAvailable: (json['balance_available'] as int?) ?? 0,
      balanceHeld: (json['balance_held'] as int?) ?? 0,
      updatedAt: DateTime.parse(json['updated_at'] as String),
    );
  }

  int get totalBalance => balanceAvailable + balanceHeld;
}
