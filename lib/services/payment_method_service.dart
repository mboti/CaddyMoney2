import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:caddymoney/models/payment_method_model.dart';
import 'package:caddymoney/core/config/supabase_config.dart';

class AddCardResult {
  final bool success;
  final String? message;
  final PaymentMethodModel? method;

  const AddCardResult({required this.success, this.message, this.method});
}

class PaymentMethodService {
  static const String _table = 'payment_methods';

  /// Normalizes common localized digits to ASCII 0-9, then strips non-digits.
  ///
  /// This prevents false “invalid card number” errors on keyboards that output
  /// Arabic-Indic / Eastern Arabic-Indic / Fullwidth digits.
  String _cleanDigits(String input) {
    final normalized = input
        // Arabic-Indic digits (U+0660..U+0669)
        .replaceAll('٠', '0')
        .replaceAll('١', '1')
        .replaceAll('٢', '2')
        .replaceAll('٣', '3')
        .replaceAll('٤', '4')
        .replaceAll('٥', '5')
        .replaceAll('٦', '6')
        .replaceAll('٧', '7')
        .replaceAll('٨', '8')
        .replaceAll('٩', '9')
        // Eastern Arabic-Indic digits (U+06F0..U+06F9)
        .replaceAll('۰', '0')
        .replaceAll('۱', '1')
        .replaceAll('۲', '2')
        .replaceAll('۳', '3')
        .replaceAll('۴', '4')
        .replaceAll('۵', '5')
        .replaceAll('۶', '6')
        .replaceAll('۷', '7')
        .replaceAll('۸', '8')
        .replaceAll('۹', '9')
        // Fullwidth digits (U+FF10..U+FF19)
        .replaceAll('０', '0')
        .replaceAll('１', '1')
        .replaceAll('２', '2')
        .replaceAll('３', '3')
        .replaceAll('４', '4')
        .replaceAll('５', '5')
        .replaceAll('６', '6')
        .replaceAll('７', '7')
        .replaceAll('８', '8')
        .replaceAll('９', '9');

    return normalized.replaceAll(RegExp(r'[^0-9]'), '');
  }

  String _detectBrand(String digits) {
    if (digits.startsWith('4')) return 'visa';
    if (digits.startsWith('5')) return 'mastercard';
    if (digits.startsWith('34') || digits.startsWith('37')) return 'amex';
    return 'card';
  }

  bool _luhnIsValid(String digits) {
    if (digits.length < 12) return false;
    var sum = 0;
    var alternate = false;
    for (var i = digits.length - 1; i >= 0; i--) {
      var n = int.tryParse(digits[i]) ?? 0;
      if (alternate) {
        n *= 2;
        if (n > 9) n -= 9;
      }
      sum += n;
      alternate = !alternate;
    }
    return sum % 10 == 0;
  }

  Future<List<PaymentMethodModel>> listMyPaymentMethods() async {
    try {
      final uid = SupabaseConfig.auth.currentUser?.id;
      if (uid == null) return [];

      final rows = await SupabaseService.select(
        _table,
        filters: {'user_id': uid},
        orderBy: 'created_at',
        ascending: false,
      );
      final list = rows.map(PaymentMethodModel.fromJson).where((m) => m.id.isNotEmpty).toList();
      list.sort((a, b) {
        if (a.isDefault == b.isDefault) return 0;
        return a.isDefault ? -1 : 1;
      });
      return list;
    } catch (e) {
      debugPrint('PaymentMethodService.listMyPaymentMethods failed: $e');
      return [];
    }
  }

  Future<AddCardResult> addCard({
    required String cardNumber,
    required int expMonth,
    required int expYear,
    String? holderName,
    String? nickname,
    bool makeDefault = true,
  }) async {
    final uid = SupabaseConfig.auth.currentUser?.id;
    if (uid == null) return const AddCardResult(success: false, message: 'Not signed in');

    final digits = _cleanDigits(cardNumber);
    if (digits.length < 12) return const AddCardResult(success: false, message: 'Enter a valid card number');
    if (!_luhnIsValid(digits)) return const AddCardResult(success: false, message: 'Card number looks invalid');
    if (expMonth < 1 || expMonth > 12) return const AddCardResult(success: false, message: 'Expiry month must be 1-12');
    if (expYear < 2020 || expYear > 2100) return const AddCardResult(success: false, message: 'Expiry year looks invalid');

    final last4 = digits.substring(digits.length - 4);
    final brand = _detectBrand(digits);

    try {
      if (makeDefault) {
        await SupabaseService.update(
          _table,
          {'is_default': false},
          filters: {'user_id': uid},
        );
      }

      final inserted = await SupabaseService.insert(
        _table,
        {
          'user_id': uid,
          'type': 'card',
          'brand': brand,
          'last4': last4,
          'exp_month': expMonth,
          'exp_year': expYear,
          'holder_name': holderName,
          'nickname': nickname,
          'is_default': makeDefault,
        },
      );
      final row = inserted.isNotEmpty ? inserted.first : <String, dynamic>{};
      final method = row.isNotEmpty ? PaymentMethodModel.fromJson(row) : null;
      return AddCardResult(success: method != null, message: method != null ? 'Card saved.' : 'Failed to save card', method: method);
    } on PostgrestException catch (e) {
      debugPrint('PaymentMethodService.addCard PostgrestException: ${e.message}');
      if (e.code == '23505') {
        return const AddCardResult(success: false, message: 'You already have a default card.');
      }
      return AddCardResult(success: false, message: e.message);
    } catch (e) {
      debugPrint('PaymentMethodService.addCard failed: $e');
      return const AddCardResult(success: false, message: 'Failed to save card');
    }
  }

  Future<bool> setDefault(String paymentMethodId) async {
    final uid = SupabaseConfig.auth.currentUser?.id;
    if (uid == null) return false;
    try {
      await SupabaseService.update(
        _table,
        {'is_default': false},
        filters: {'user_id': uid},
      );
      await SupabaseService.update(
        _table,
        {'is_default': true},
        filters: {'id': paymentMethodId, 'user_id': uid},
      );
      return true;
    } catch (e) {
      debugPrint('PaymentMethodService.setDefault failed: $e');
      return false;
    }
  }

  Future<bool> deletePaymentMethod(String paymentMethodId) async {
    final uid = SupabaseConfig.auth.currentUser?.id;
    if (uid == null) return false;
    try {
      await SupabaseService.delete(
        _table,
        filters: {'id': paymentMethodId, 'user_id': uid},
      );
      return true;
    } catch (e) {
      debugPrint('PaymentMethodService.deletePaymentMethod failed: $e');
      return false;
    }
  }
}
