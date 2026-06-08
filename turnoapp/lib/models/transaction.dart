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

import 'enums.dart';

class Transaction {
  final String id;
  final String userId;
  final String? bookingId;
  final TxType type;
  final int amount; // positive or negative
  final Map<String, dynamic> metadata;
  final DateTime createdAt;

  const Transaction({
    required this.id,
    required this.userId,
    this.bookingId,
    required this.type,
    required this.amount,
    required this.metadata,
    required this.createdAt,
  });

  factory Transaction.fromJson(Map<String, dynamic> json) {
    TxType parseType(String t) {
      switch (t) {
        case 'topup':
          return TxType.topup;
        case 'booking_hold':
          return TxType.bookingHold;
        case 'release_to_driver':
          return TxType.releaseToDriver;
        case 'platform_fee':
          return TxType.platformFee;
        case 'refund':
          return TxType.refund;
        case 'withdrawal_request':
          return TxType.withdrawalRequest;
        case 'withdrawal_paid':
          return TxType.withdrawalPaid;
        case 'penalty':
          return TxType.penalty;
        default:
          return TxType.topup;
      }
    }

    return Transaction(
      id: json['id'] as String,
      userId: json['user_id'] as String,
      bookingId: json['booking_id'] as String?,
      type: parseType((json['type'] as String?) ?? 'topup'),
      amount: (json['amount'] as int?) ?? 0,
      metadata: (json['metadata'] as Map<String, dynamic>?) ?? {},
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }

  String get typeLabel {
    switch (type) {
      case TxType.topup:
        return 'Recarga';
      case TxType.bookingHold:
        return 'Reserva';
      case TxType.releaseToDriver:
        return 'Pago liberado';
      case TxType.platformFee:
        return 'Comisión';
      case TxType.refund:
        return 'Reembolso';
      case TxType.withdrawalRequest:
        return 'Solicitud retiro';
      case TxType.withdrawalPaid:
        return 'Retiro pagado';
      case TxType.penalty:
        return 'Penalidad';
    }
  }

  bool get isCredit => amount > 0;
}
