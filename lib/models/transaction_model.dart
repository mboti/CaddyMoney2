import 'package:caddymoney/core/enums/transaction_type.dart';
import 'package:caddymoney/core/enums/transaction_status.dart';

class TransactionModel {
  final String id;
  final String transactionReference;
  final String? senderProfileId;
  final String? senderWalletId;
  final String? receiverProfileId;
  final String? receiverMerchantId;
  final String? receiverWalletId;
  /// Optional display fields (populated by joined selects).
  final String? senderFullName;
  final String? receiverFullName;
  final String? receiverMerchantBusinessName;
  final double amount;
  final String currencyCode;
  final String? note;
  final TransactionType type;
  final TransactionStatus status;
  final String? failureReason;
  final Map<String, dynamic>? metadata;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? completedAt;

  TransactionModel({
    required this.id,
    required this.transactionReference,
    this.senderProfileId,
    this.senderWalletId,
    this.receiverProfileId,
    this.receiverMerchantId,
    this.receiverWalletId,
    this.senderFullName,
    this.receiverFullName,
    this.receiverMerchantBusinessName,
    required this.amount,
    required this.currencyCode,
    this.note,
    required this.type,
    required this.status,
    this.failureReason,
    this.metadata,
    required this.createdAt,
    required this.updatedAt,
    this.completedAt,
  });

  /// Best-effort merchant identifier for UI lookups.
  ///
  /// Some backends store the merchant reference under different columns
  /// (e.g. `receiver_merchant_id`, `receiver_merchant_profile_id`) or within
  /// `metadata`. This getter normalizes the most common variants.
  String? get merchantLookupId {
    final direct = receiverMerchantId?.trim();
    if (direct != null && direct.isNotEmpty) return direct;

    final m = metadata;
    if (m == null) return null;
    final candidates = <dynamic>[m['receiver_merchant_id'], m['merchant_id'], m['merchant_profile_id'], m['receiverMerchantId']];
    for (final c in candidates) {
      final s = c?.toString().trim();
      if (s != null && s.isNotEmpty) return s;
    }
    return null;
  }

  factory TransactionModel.fromJson(Map<String, dynamic> json) {
    double readAmount(dynamic v) {
      if (v is num) return v.toDouble();
      if (v is String) return double.tryParse(v) ?? 0;
      return 0;
    }

    String? readJoinedDisplayName(String key) {
      final v = json[key];
      if (v is! Map) return null;
      final m = Map<String, dynamic>.from(v);

      final full = m['full_name']?.toString().trim();
      if (full != null && full.isNotEmpty) return full;

      final first = m['first_name']?.toString().trim();
      final last = m['last_name']?.toString().trim();
      final combined = [if (first != null && first.isNotEmpty) first, if (last != null && last.isNotEmpty) last].join(' ');
      if (combined.trim().isNotEmpty) return combined.trim();

      final username = m['username']?.toString().trim();
      if (username != null && username.isNotEmpty) return username;

      return null;
    }

    String? readJoinedValue(String key, String field) {
      final v = json[key];
      if (v is Map) return v[field]?.toString();
      return null;
    }

    String? readAnyString(List<String> keys) {
      for (final k in keys) {
        final v = json[k];
        final s = v?.toString().trim();
        if (s != null && s.isNotEmpty) return s;
      }
      return null;
    }

    return TransactionModel(
      id: json['id'] as String,
      transactionReference: json['transaction_reference'] as String,
      senderProfileId: json['sender_profile_id'] as String?,
      senderWalletId: json['sender_wallet_id'] as String?,
      receiverProfileId: json['receiver_profile_id'] as String?,
      receiverMerchantId: readAnyString(const ['receiver_merchant_id', 'receiver_merchant_profile_id', 'merchant_id', 'merchant_profile_id']),
      receiverWalletId: json['receiver_wallet_id'] as String?,
      senderFullName: readJoinedDisplayName('sender'),
      receiverFullName: readJoinedDisplayName('receiver'),
      receiverMerchantBusinessName: readJoinedValue('merchant', 'business_name') ??
          readJoinedValue('receiver_merchant', 'business_name') ??
          readJoinedValue('merchants', 'business_name') ??
          readAnyString(const ['receiver_merchant_business_name', 'merchant_business_name']),
      amount: readAmount(json['amount']),
      currencyCode: json['currency_code'] as String,
      note: json['note'] as String?,
      type: TransactionType.fromString(json['type'] as String),
      status: TransactionStatus.fromString(json['status'] as String),
      failureReason: json['failure_reason'] as String?,
      metadata: json['metadata'] as Map<String, dynamic>?,
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
      completedAt: json['completed_at'] != null ? DateTime.parse(json['completed_at'] as String) : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'transaction_reference': transactionReference,
      'sender_profile_id': senderProfileId,
      'sender_wallet_id': senderWalletId,
      'receiver_profile_id': receiverProfileId,
      'receiver_merchant_id': receiverMerchantId,
      'receiver_wallet_id': receiverWalletId,
      // joined display info is intentionally not serialized
      'amount': amount,
      'currency_code': currencyCode,
      'note': note,
      'type': type.toJson(),
      'status': status.toJson(),
      'failure_reason': failureReason,
      'metadata': metadata,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
      'completed_at': completedAt?.toIso8601String(),
    };
  }

  TransactionModel copyWith({
    String? id,
    String? transactionReference,
    String? senderProfileId,
    String? senderWalletId,
    String? receiverProfileId,
    String? receiverMerchantId,
    String? receiverWalletId,
    String? senderFullName,
    String? receiverFullName,
    String? receiverMerchantBusinessName,
    double? amount,
    String? currencyCode,
    String? note,
    TransactionType? type,
    TransactionStatus? status,
    String? failureReason,
    Map<String, dynamic>? metadata,
    DateTime? createdAt,
    DateTime? updatedAt,
    DateTime? completedAt,
  }) {
    return TransactionModel(
      id: id ?? this.id,
      transactionReference: transactionReference ?? this.transactionReference,
      senderProfileId: senderProfileId ?? this.senderProfileId,
      senderWalletId: senderWalletId ?? this.senderWalletId,
      receiverProfileId: receiverProfileId ?? this.receiverProfileId,
      receiverMerchantId: receiverMerchantId ?? this.receiverMerchantId,
      receiverWalletId: receiverWalletId ?? this.receiverWalletId,
      senderFullName: senderFullName ?? this.senderFullName,
      receiverFullName: receiverFullName ?? this.receiverFullName,
      receiverMerchantBusinessName: receiverMerchantBusinessName ?? this.receiverMerchantBusinessName,
      amount: amount ?? this.amount,
      currencyCode: currencyCode ?? this.currencyCode,
      note: note ?? this.note,
      type: type ?? this.type,
      status: status ?? this.status,
      failureReason: failureReason ?? this.failureReason,
      metadata: metadata ?? this.metadata,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      completedAt: completedAt ?? this.completedAt,
    );
  }
}
