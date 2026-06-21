class PaymentMethodModel {
  final String id;
  final String userId;
  final String type;
  final String brand;
  final String last4;
  final int expMonth;
  final int expYear;
  final String? holderName;
  final String? nickname;
  final bool isDefault;
  final DateTime createdAt;
  final DateTime updatedAt;

  const PaymentMethodModel({
    required this.id,
    required this.userId,
    required this.type,
    required this.brand,
    required this.last4,
    required this.expMonth,
    required this.expYear,
    required this.isDefault,
    required this.createdAt,
    required this.updatedAt,
    this.holderName,
    this.nickname,
  });

  factory PaymentMethodModel.fromJson(Map<String, dynamic> json) => PaymentMethodModel(
    id: json['id']?.toString() ?? '',
    userId: json['user_id']?.toString() ?? '',
    type: json['type']?.toString() ?? 'card',
    brand: json['brand']?.toString() ?? 'visa',
    last4: json['last4']?.toString() ?? '',
    expMonth: (json['exp_month'] as num?)?.toInt() ?? 1,
    expYear: (json['exp_year'] as num?)?.toInt() ?? 2025,
    holderName: json['holder_name']?.toString(),
    nickname: json['nickname']?.toString(),
    isDefault: json['is_default'] == true,
    createdAt: DateTime.tryParse(json['created_at']?.toString() ?? '') ?? DateTime.fromMillisecondsSinceEpoch(0),
    updatedAt: DateTime.tryParse(json['updated_at']?.toString() ?? '') ?? DateTime.fromMillisecondsSinceEpoch(0),
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'user_id': userId,
    'type': type,
    'brand': brand,
    'last4': last4,
    'exp_month': expMonth,
    'exp_year': expYear,
    'holder_name': holderName,
    'nickname': nickname,
    'is_default': isDefault,
    'created_at': createdAt.toIso8601String(),
    'updated_at': updatedAt.toIso8601String(),
  };

  PaymentMethodModel copyWith({
    String? id,
    String? userId,
    String? type,
    String? brand,
    String? last4,
    int? expMonth,
    int? expYear,
    String? holderName,
    String? nickname,
    bool? isDefault,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) =>
      PaymentMethodModel(
        id: id ?? this.id,
        userId: userId ?? this.userId,
        type: type ?? this.type,
        brand: brand ?? this.brand,
        last4: last4 ?? this.last4,
        expMonth: expMonth ?? this.expMonth,
        expYear: expYear ?? this.expYear,
        holderName: holderName ?? this.holderName,
        nickname: nickname ?? this.nickname,
        isDefault: isDefault ?? this.isDefault,
        createdAt: createdAt ?? this.createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
      );
}
