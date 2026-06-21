import 'package:flutter/foundation.dart';

import 'package:caddymoney/models/payment_intent_model.dart';

@immutable
class PaymentIntentResolutionModel {
  final PaymentIntentModel intent;
  final String? merchantId;
  final String? merchantName;
  final List<String> merchantCategories;

  const PaymentIntentResolutionModel({required this.intent, required this.merchantId, required this.merchantName, required this.merchantCategories});

  static PaymentIntentResolutionModel fromJson(Map<String, dynamic> json) {
    final piJson = json['payment_intent'];
    if (piJson is! Map) {
      throw Exception('Invalid response: missing payment_intent');
    }

    final piMap = Map<String, dynamic>.from(piJson as Map);
    final merchantJson = piMap['merchant'];
    final merchantMap = merchantJson is Map ? Map<String, dynamic>.from(merchantJson as Map) : const <String, dynamic>{};
    final rawCategories = merchantMap['categories'];
    final categories = rawCategories is List ? rawCategories.map((e) => e.toString()).where((e) => e.trim().isNotEmpty).toList() : <String>[];

    return PaymentIntentResolutionModel(
      intent: PaymentIntentModel.fromJson(piMap),
      merchantId: merchantMap['id']?.toString(),
      merchantName: merchantMap['business_name']?.toString(),
      merchantCategories: categories,
    );
  }
}
