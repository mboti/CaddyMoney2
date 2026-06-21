class WalletModel {
  final String id;
  final String ownerType;
  final String? profileId;
  final String? merchantId;
  final String currencyCode;
  final double balance;
  final bool isActive;
  final DateTime createdAt;
  final DateTime updatedAt;

  WalletModel({
    required this.id,
    required this.ownerType,
    this.profileId,
    this.merchantId,
    required this.currencyCode,
    required this.balance,
    required this.isActive,
    required this.createdAt,
    required this.updatedAt,
  });

  factory WalletModel.fromJson(Map<String, dynamic> json) {
    return WalletModel(
      id: json['id'] as String,
      ownerType: json['owner_type'] as String,
      profileId: json['profile_id'] as String?,
      merchantId: json['merchant_id'] as String?,
      currencyCode: json['currency_code'] as String,
      balance: (json['balance'] as num).toDouble(),
      isActive: json['is_active'] as bool,
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'owner_type': ownerType,
      'profile_id': profileId,
      'merchant_id': merchantId,
      'currency_code': currencyCode,
      'balance': balance,
      'is_active': isActive,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }

  WalletModel copyWith({
    String? id,
    String? ownerType,
    String? profileId,
    String? merchantId,
    String? currencyCode,
    double? balance,
    bool? isActive,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return WalletModel(
      id: id ?? this.id,
      ownerType: ownerType ?? this.ownerType,
      profileId: profileId ?? this.profileId,
      merchantId: merchantId ?? this.merchantId,
      currencyCode: currencyCode ?? this.currencyCode,
      balance: balance ?? this.balance,
      isActive: isActive ?? this.isActive,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
