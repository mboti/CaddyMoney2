import 'package:flutter/foundation.dart';

/// A server-created payment request that the customer can pay.
///
/// IMPORTANT SECURITY NOTES:
/// - The Flutter client must never be treated as a source of truth.
/// - Creation and validation happen on the backend (Supabase Edge Function).
/// - The QR code should only contain [token] (or [id]) — never the amount or any
///   sensitive payment data in plain text.
@immutable
class PaymentIntentModel {
  final String id;

  /// Short opaque token intended to be encoded in a QR code.
  ///
  /// A customer scans this token, then your backend resolves it to the real
  /// payment intent row and enforces all validations (merchant, amount, expiry,
  /// allowed service, wallet balance, etc.).
  final String token;

  /// Human-friendly short code intended for manual typing.
  ///
  /// This is optional for backward compatibility with older rows/schemas.
  /// When present, it should be preferred over [token] for displaying to users.
  final String? shortCode;

  /// ISO-4217 currency code (e.g., "EUR").
  final String currencyCode;

  /// Amount requested, in major units (e.g., 12.34 EUR).
  final double amount;

  /// pending -> (later) completed/expired/cancelled, etc.
  final String status;

  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime expiresAt;

  /// Populated once the intent is completed.
  final String? transactionReference;
  final DateTime? completedAt;

  const PaymentIntentModel({
    required this.id,
    required this.token,
    this.shortCode,
    required this.currencyCode,
    required this.amount,
    required this.status,
    required this.createdAt,
    required this.updatedAt,
    required this.expiresAt,
    this.transactionReference,
    this.completedAt,
  });

  bool get isExpired => DateTime.now().isAfter(expiresAt);

  PaymentIntentModel copyWith({
    String? id,
    String? token,
    String? shortCode,
    String? currencyCode,
    double? amount,
    String? status,
    DateTime? createdAt,
    DateTime? updatedAt,
    DateTime? expiresAt,
    String? transactionReference,
    DateTime? completedAt,
  }) {
    return PaymentIntentModel(
      id: id ?? this.id,
      token: token ?? this.token,
      shortCode: shortCode ?? this.shortCode,
      currencyCode: currencyCode ?? this.currencyCode,
      amount: amount ?? this.amount,
      status: status ?? this.status,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      expiresAt: expiresAt ?? this.expiresAt,
      transactionReference: transactionReference ?? this.transactionReference,
      completedAt: completedAt ?? this.completedAt,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'token': token,
        'short_code': shortCode,
        'currency_code': currencyCode,
        'amount': amount,
        'status': status,
        'created_at': createdAt.toIso8601String(),
        'updated_at': updatedAt.toIso8601String(),
        'expires_at': expiresAt.toIso8601String(),
        'transaction_reference': transactionReference,
        'completed_at': completedAt?.toIso8601String(),
      };

  static PaymentIntentModel fromJson(Map<String, dynamic> json) {
    DateTime parseDate(String key) {
      final v = json[key];
      if (v == null) return DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
      if (v is DateTime) return v;
      return DateTime.tryParse(v.toString()) ?? DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
    }

    DateTime? parseDateNullable(String key) {
      final v = json[key];
      if (v == null) return null;
      if (v is DateTime) return v;
      return DateTime.tryParse(v.toString());
    }

    // Some backends store amount as cents (int). We support both to keep the
    // client resilient.
    double parseAmount() {
      final cents = json['amount_cents'];
      if (cents is int) return cents / 100.0;
      if (cents is num) return cents.toDouble() / 100.0;
      final a = json['amount'];
      if (a is num) return a.toDouble();
      return double.tryParse(a?.toString() ?? '') ?? 0;
    }

    return PaymentIntentModel(
      id: (json['id'] ?? '').toString(),
      token: (json['token'] ?? json['payment_token'] ?? '').toString(),
      // Support multiple key styles for resilience across Edge Function versions.
      shortCode: (json['short_code'] ?? json['shortCode'] ?? json['typing_code'])?.toString(),
      currencyCode: (json['currency_code'] ?? json['currency'] ?? 'EUR').toString(),
      amount: parseAmount(),
      status: (json['status'] ?? 'pending').toString(),
      createdAt: parseDate('created_at'),
      updatedAt: parseDate('updated_at'),
      expiresAt: parseDate('expires_at'),
      transactionReference: (json['transaction_reference'] ?? json['transactionReference'])?.toString(),
      completedAt: parseDateNullable('completed_at'),
    );
  }
}
