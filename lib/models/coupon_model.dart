import 'package:flutter/foundation.dart';

@immutable
class CouponModel {
  final String id;
  final String profileId;
  final String title;
  final String category;
  final String currencyCode;
  final double balance;
  final String status;
  final DateTime createdAt;
  final DateTime updatedAt;

  const CouponModel({
    required this.id,
    required this.profileId,
    required this.title,
    required this.category,
    required this.currencyCode,
    required this.balance,
    required this.status,
    required this.createdAt,
    required this.updatedAt,
  });

  factory CouponModel.fromJson(Map<String, dynamic> json) {
    DateTime _dt(dynamic v) {
      if (v == null) return DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
      if (v is DateTime) return v;
      return DateTime.tryParse(v.toString()) ?? DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
    }

    return CouponModel(
      id: json['id']?.toString() ?? '',
      profileId: json['profile_id']?.toString() ?? '',
      title: json['title']?.toString() ?? '',
      category: json['category']?.toString() ?? '',
      currencyCode: json['currency_code']?.toString() ?? 'EUR',
      balance: (json['balance'] as num?)?.toDouble() ?? 0,
      status: json['status']?.toString() ?? 'active',
      createdAt: _dt(json['created_at']),
      updatedAt: _dt(json['updated_at']),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'profile_id': profileId,
        'title': title,
        'category': category,
        'currency_code': currencyCode,
        'balance': balance,
        'status': status,
        'created_at': createdAt.toIso8601String(),
        'updated_at': updatedAt.toIso8601String(),
      };

  CouponModel copyWith({
    String? id,
    String? profileId,
    String? title,
    String? category,
    String? currencyCode,
    double? balance,
    String? status,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return CouponModel(
      id: id ?? this.id,
      profileId: profileId ?? this.profileId,
      title: title ?? this.title,
      category: category ?? this.category,
      currencyCode: currencyCode ?? this.currencyCode,
      balance: balance ?? this.balance,
      status: status ?? this.status,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
