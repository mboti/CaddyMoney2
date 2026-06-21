import 'package:flutter/foundation.dart';
import 'package:caddymoney/models/transaction_model.dart';
import 'package:caddymoney/core/config/supabase_config.dart';
import 'package:caddymoney/core/enums/transaction_type.dart';
import 'package:caddymoney/core/enums/transaction_status.dart';

class TransferResult {
  final bool success;
  final String? error;
  final String? transactionId;
  final String? transactionReference;

  const TransferResult({required this.success, this.error, this.transactionId, this.transactionReference});

  factory TransferResult.fromJson(Map<String, dynamic> json) {
    return TransferResult(
      success: json['success'] == true,
      error: json['error'] as String?,
      transactionId: json['transaction_id']?.toString(),
      transactionReference: json['transaction_reference']?.toString(),
    );
  }
}

class TransactionTotals {
  final double totalReceived;
  final double totalSpentAtMerchants;
  final String? currencyCode;

  const TransactionTotals({required this.totalReceived, required this.totalSpentAtMerchants, this.currencyCode});
}

class MerchantTransactionTotals {
  final double totalReceived;
  final int transactionCount;
  final String? currencyCode;

  const MerchantTransactionTotals({required this.totalReceived, required this.transactionCount, this.currencyCode});
}

class CategoryBalance {
  final String category;
  final double balance;
  final DateTime latestAt;
  final String? currencyCode;

  const CategoryBalance({required this.category, required this.balance, required this.latestAt, this.currencyCode});
}

class TransactionService {
  static const List<String> _merchantSuccessStatuses = <String>['completed', 'paid', 'succeeded'];

  static double _round2(double v) => (v * 100).roundToDouble() / 100;

  static String _normCategory(String v) {
    final s = v.trim().toLowerCase();
    if (s.isEmpty) return '';
    // Keep only a-z/0-9 to avoid issues with dashes, spaces, accents, etc.
    final buf = StringBuffer();
    for (final r in s.runes) {
      final c = String.fromCharCode(r);
      final code = c.codeUnitAt(0);
      final isAz = code >= 97 && code <= 122;
      final is09 = code >= 48 && code <= 57;
      if (isAz || is09) buf.write(c);
    }
    return buf.toString();
  }

  static bool _isMerchantSuccessStatus(dynamic status) {
    final s = status?.toString().toLowerCase().trim();
    if (s == null || s.isEmpty) return false;
    return _merchantSuccessStatuses.contains(s);
  }

  static double _readAmount(dynamic v) {
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v) ?? 0;
    return 0;
  }

  Future<List<TransactionModel>> listMerchantTransactions({
    required String merchantId,
    int limit = 50,
    bool completedOnly = true,
  }) async {
    try {
      if (kDebugMode) debugPrint('TransactionService.listMerchantTransactions merchantId=$merchantId completedOnly=$completedOnly');

      dynamic query = SupabaseService.from('transactions')
          .select(
            '*, '
            'sender:sender_profile_id(full_name,first_name,last_name,username),'
            'receiver:receiver_profile_id(full_name,first_name,last_name,username),'
            'merchant:receiver_merchant_id(business_name)',
          )
          .eq('receiver_merchant_id', merchantId)
          .order('created_at', ascending: false)
          .limit(limit);

       // Some older `postgrest` versions (used by Dreamflow on web) don't expose
       // the usual `in_()` / `or()` / `filter()` helpers.
       // To stay compatible, we fetch recent rows and filter success statuses in Dart.
       final rows = await query.limit((completedOnly ? (limit * 3) : limit)) as List;
       if (kDebugMode) debugPrint('TransactionService.listMerchantTransactions rows=${rows.length}');
       final filtered = completedOnly
           ? rows.whereType<Map>().where((m) => _isMerchantSuccessStatus((m as Map)['status'])).toList()
           : rows.whereType<Map>().toList();
       return filtered
           .take(limit)
           .map((e) => TransactionModel.fromJson(Map<String, dynamic>.from(e as Map)))
           .toList();
    } catch (e) {
      debugPrint('TransactionService.listMerchantTransactions failed: $e');
      return [];
    }
  }

  Future<MerchantTransactionTotals> getMerchantTotals({required String merchantId, int limit = 2000}) async {
    try {
       dynamic query = SupabaseService.from('transactions')
          .select('amount,currency_code,status')
          .eq('receiver_merchant_id', merchantId)
          .order('created_at', ascending: false)
           .limit(limit);

       final rows = await query as List;
      double total = 0;
      String? currency;
       final filtered = rows.whereType<Map>().where((m) => _isMerchantSuccessStatus((m as Map)['status']));
       for (final r in filtered) {
        final m = Map<String, dynamic>.from(r);
        total += _readAmount(m['amount']);
        currency ??= m['currency_code']?.toString();
      }

      if (kDebugMode) {
        debugPrint(
          'TransactionService.getMerchantTotals merchantId=$merchantId rows=${rows.length} total=$total currency=$currency',
        );
      }

       final count = filtered.length;
       return MerchantTransactionTotals(totalReceived: total, transactionCount: count, currencyCode: currency);
    } catch (e) {
      debugPrint('TransactionService.getMerchantTotals failed: $e');
      return const MerchantTransactionTotals(totalReceived: 0, transactionCount: 0);
    }
  }

  Future<String?> findActiveUserIdByEmail(String email) async {
    try {
      final cleaned = email.trim().toLowerCase().replaceAll(RegExp(r'\s+'), '');
      if (cleaned.isEmpty) return null;

      final matches = await SupabaseConfig.client.rpc(
        'find_active_profiles',
        params: {'p_identifier': cleaned, 'p_limit': 10},
      );
      final list = (matches as List).whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
      if (list.isEmpty) return null;

      final chosen = list.firstWhere(
        (m) => (m['email']?.toString().toLowerCase() ?? '') == cleaned,
        orElse: () => <String, dynamic>{},
      );
      final id = chosen['id']?.toString();
      return (id == null || id.isEmpty) ? null : id;
    } catch (e) {
      debugPrint('TransactionService.findActiveUserIdByEmail failed: $e');
      return null;
    }
  }

  Future<List<TransactionModel>> listMyTransactions({int limit = 50}) async {
    try {
      final uid = SupabaseConfig.auth.currentUser?.id;
      if (uid == null) return [];

      // Covers: sent user->user, received user->user, sent user->merchant.
      dynamic query = SupabaseService.from('transactions')
          // Also fetch related display info (names) for UI.
          .select(
            '*,'
            'sender:sender_profile_id(full_name,first_name,last_name,username),'
            'receiver:receiver_profile_id(full_name,first_name,last_name,username),'
            'merchant:receiver_merchant_id(business_name)',
          )
          .or('sender_profile_id.eq.$uid,receiver_profile_id.eq.$uid')
          .order('created_at', ascending: false)
          .limit(limit);

      final rows = await query as List;
      if (kDebugMode && rows.isNotEmpty) {
        final first = rows.first;
        if (first is Map) {
          final m = Map<String, dynamic>.from(first);
          debugPrint(
            'TransactionService.listMyTransactions sample row keys=${first.keys.toList()} '
            'sender=${m['sender']} receiver=${m['receiver']} '
            'receiver_merchant_id=${m['receiver_merchant_id']} receiver_merchant_profile_id=${m['receiver_merchant_profile_id']} '
            'merchant_join=${m['merchant']}',
          );
        } else {
          debugPrint('TransactionService.listMyTransactions first row is not a Map: ${first.runtimeType}');
        }
      }
      return rows
          .whereType<Map>()
          .map((e) => TransactionModel.fromJson(Map<String, dynamic>.from(e)))
          .toList();
    } catch (e) {
      debugPrint('TransactionService.listMyTransactions failed: $e');
      return [];
    }
  }

  /// Returns a simple breakdown of the user's completed flows:
  /// - totalReceived: completed user->user where *I am receiver*
  /// - totalSpentAtMerchants: completed user->merchant where *I am sender*
  ///
  /// This is meant as a UI/debug breakdown to validate the wallet balance.
  Future<TransactionTotals> getMyReceivedAndMerchantSpendTotals({int limit = 1000}) async {
    try {
      final uid = SupabaseConfig.auth.currentUser?.id;
      if (uid == null) return const TransactionTotals(totalReceived: 0, totalSpentAtMerchants: 0);

      final rows = await SupabaseService.from('transactions')
          .select('amount,currency_code,type,status,sender_profile_id,receiver_profile_id')
          .eq('status', 'completed')
          .or('sender_profile_id.eq.$uid,receiver_profile_id.eq.$uid')
          .order('created_at', ascending: false)
          .limit(limit) as List;

      double received = 0;
      double spent = 0;
      String? currency;

      for (final r in rows.whereType<Map>()) {
        final m = Map<String, dynamic>.from(r);
        final typeRaw = m['type']?.toString() ?? '';
        final statusRaw = m['status']?.toString() ?? '';
        final type = TransactionType.fromString(typeRaw);
        final status = TransactionStatus.fromString(statusRaw);
        final amount = (m['amount'] as num?)?.toDouble() ?? 0;
        final senderId = m['sender_profile_id']?.toString();
        final receiverId = m['receiver_profile_id']?.toString();
        currency ??= m['currency_code']?.toString();

        // Keep this in sync with how we display/interpret transactions elsewhere.
        // Your DB currently stores types as camelCase (e.g. userToUser), while some
        // legacy code expects snake_case. Using the enum parser avoids mismatches.
        final isIncomingUserTransfer = status == TransactionStatus.completed && type == TransactionType.userToUser && receiverId == uid;
        final isMerchantSpend = status == TransactionStatus.completed && type == TransactionType.userToMerchant && senderId == uid;

        if (isIncomingUserTransfer) received += amount;
        if (isMerchantSpend) spent += amount;
      }

      if (kDebugMode) {
        debugPrint(
          'TransactionService.getMyReceivedAndMerchantSpendTotals rows=${rows.length} '
          'received=$received spent=$spent currency=$currency',
        );
      }

      return TransactionTotals(totalReceived: received, totalSpentAtMerchants: spent, currencyCode: currency);
    } catch (e) {
      debugPrint('TransactionService.getMyReceivedAndMerchantSpendTotals failed: $e');
      return const TransactionTotals(totalReceived: 0, totalSpentAtMerchants: 0);
    }
  }

  /// Computes a category/service balance for the current user.
  ///
  /// Balance is the net of:
  /// - Incoming user->user transfers (receiver == me): +amount
  /// - Merchant spends (sender == me): -amount
  /// - Refunds/adjustments: treated as incoming if receiver == me, otherwise outgoing.
  ///
  /// This is used by the User Home screen “Available amounts by service” section.
  Future<List<CategoryBalance>> getMyCategoryBalances({int limit = 5000}) async {
    try {
      final uid = SupabaseConfig.auth.currentUser?.id;
      if (uid == null) return const [];

      final rows = await SupabaseService.from('transactions')
          .select('amount,currency_code,type,status,sender_profile_id,receiver_profile_id,metadata,created_at')
          // IMPORTANT: keep this consistent with totals (we only want finalized flows).
          .eq('status', 'completed')
          .or('sender_profile_id.eq.$uid,receiver_profile_id.eq.$uid')
          .order('created_at', ascending: false)
          .limit(limit) as List;

      final Map<String, CategoryBalance> map = {};
      String? currency;

      for (final r in rows.whereType<Map>()) {
        final m = Map<String, dynamic>.from(r);
        final amount = _round2((m['amount'] as num?)?.toDouble() ?? 0);
        final type = TransactionType.fromString(m['type']?.toString() ?? '');
        final status = TransactionStatus.fromString(m['status']?.toString() ?? '');
        if (status != TransactionStatus.completed) continue;

        final senderId = m['sender_profile_id']?.toString();
        final receiverId = m['receiver_profile_id']?.toString();
        final createdAtRaw = m['created_at'];
        final createdAt = createdAtRaw is String ? DateTime.tryParse(createdAtRaw) : null;
        final createdAtSafe = (createdAt ?? DateTime.now()).toUtc();

        currency ??= m['currency_code']?.toString();

        final meta = m['metadata'];
        final category = (meta is Map ? meta['category'] : null)?.toString().trim();
        final key = (category == null || category.isEmpty) ? 'Other' : category;

        double signed;
        if (type == TransactionType.userToUser) {
          signed = (receiverId == uid) ? amount : -amount;
        } else if (type == TransactionType.userToMerchant) {
          signed = (senderId == uid) ? -amount : amount;
        } else {
          // Refund / adjustment: interpret direction relative to current user.
          signed = (receiverId == uid) ? amount : -amount;
        }

        signed = _round2(signed);

        final existing = map[key];
        if (existing == null) {
          map[key] = CategoryBalance(category: key, balance: signed, latestAt: createdAtSafe, currencyCode: currency);
        } else {
          map[key] = CategoryBalance(
            category: existing.category,
            balance: _round2(existing.balance + signed),
            latestAt: createdAtSafe.isAfter(existing.latestAt) ? createdAtSafe : existing.latestAt,
            currencyCode: existing.currencyCode ?? currency,
          );
        }
      }

      final list = map.values.toList(growable: false);
      list.sort((a, b) => b.latestAt.compareTo(a.latestAt));
      return list;
    } catch (e) {
      debugPrint('TransactionService.getMyCategoryBalances failed: $e');
      return const [];
    }
  }

  /// Groups **received coupons** (Transactions → Coupon) by category and sums them.
  ///
  /// Important: this intentionally **does not** include coupons the user sent to
  /// other users.
  ///
  /// A coupon is interpreted as a completed `userToUser` transfer where the
  /// current user is the receiver.
  Future<List<CategoryBalance>> getMyReceivedCouponCategoryTotals({int limit = 5000}) async {
    try {
      final uid = SupabaseConfig.auth.currentUser?.id;
      if (uid == null) return const [];

      final rows = await SupabaseService.from('transactions')
          .select('amount,currency_code,type,status,sender_profile_id,receiver_profile_id,metadata,created_at')
          .eq('status', 'completed')
          .or('sender_profile_id.eq.$uid,receiver_profile_id.eq.$uid')
          .order('created_at', ascending: false)
          .limit(limit) as List;

      final Map<String, CategoryBalance> map = {};
      String? currency;

      for (final r in rows.whereType<Map>()) {
        final m = Map<String, dynamic>.from(r);
        final amount = _round2((m['amount'] as num?)?.toDouble() ?? 0);
        final type = TransactionType.fromString(m['type']?.toString() ?? '');
        final status = TransactionStatus.fromString(m['status']?.toString() ?? '');
        if (status != TransactionStatus.completed) continue;

        final receiverId = m['receiver_profile_id']?.toString();
        if (type != TransactionType.userToUser || receiverId != uid) continue;

        final createdAtRaw = m['created_at'];
        final createdAt = createdAtRaw is String ? DateTime.tryParse(createdAtRaw) : null;
        final createdAtSafe = (createdAt ?? DateTime.now()).toUtc();
        currency ??= m['currency_code']?.toString();

        final meta = m['metadata'];
        final category = (meta is Map ? meta['category'] : null)?.toString().trim();
        final key = (category == null || category.isEmpty) ? 'Other' : category;

        final existing = map[key];
        if (existing == null) {
          map[key] = CategoryBalance(category: key, balance: amount, latestAt: createdAtSafe, currencyCode: currency);
        } else {
          map[key] = CategoryBalance(
            category: existing.category,
            balance: _round2(existing.balance + amount),
            latestAt: createdAtSafe.isAfter(existing.latestAt) ? createdAtSafe : existing.latestAt,
            currencyCode: existing.currencyCode ?? currency,
          );
        }
      }

      final list = map.values.toList(growable: false);
      list.sort((a, b) => b.latestAt.compareTo(a.latestAt));
      return list;
    } catch (e) {
      debugPrint('TransactionService.getMyReceivedCouponCategoryTotals failed: $e');
      return const [];
    }
  }

  /// Home screen: groups coupons the user **received** (Transactions → Coupon)
  /// by category and returns the **remaining** balance per category:
  ///
  /// `remaining = receivedCoupons(category) - merchantSpendByMe(category)`
  ///
  /// Notes:
  /// - Received coupons are interpreted as completed `userToUser` rows where the
  ///   current user is the receiver.
  /// - Spent amounts are interpreted as successful `userToMerchant` rows where
  ///   the current user is the sender.
  /// - Categories are matched using a normalized key (letters+digits only) so
  ///   strings like "Food & Beverage" and "foodbeverage" align.
  Future<List<CategoryBalance>> getMyRemainingCouponCategoryBalances({int limit = 5000}) async {
    try {
      final uid = SupabaseConfig.auth.currentUser?.id;
      if (uid == null) return const [];

      final rows = await SupabaseService.from('transactions')
          .select('amount,currency_code,type,status,sender_profile_id,receiver_profile_id,metadata,created_at,updated_at')
          // We only need rows that involve me.
          .or('sender_profile_id.eq.$uid,receiver_profile_id.eq.$uid')
          .order('created_at', ascending: false)
          .limit(limit) as List;

      final Map<String, ({String display, double received, double spent, DateTime latest, String? currency})> byCategory = {};

      for (final r in rows.whereType<Map>()) {
        final m = Map<String, dynamic>.from(r);
        final type = TransactionType.fromString(m['type']?.toString() ?? '');
        final statusRaw = m['status'];
        final status = TransactionStatus.fromString(statusRaw?.toString() ?? '');
        final isCompleted = status == TransactionStatus.completed;
        final isMerchantSuccess = _isMerchantSuccessStatus(statusRaw);

        // Coupons received should follow Transactions → Coupon source of truth.
        final receiverId = m['receiver_profile_id']?.toString();
        final senderId = m['sender_profile_id']?.toString();

        final isReceivedCoupon = isCompleted && type == TransactionType.userToUser && receiverId == uid;
        final isMyMerchantSpend = (isCompleted || isMerchantSuccess) && type == TransactionType.userToMerchant && senderId == uid;
        if (!isReceivedCoupon && !isMyMerchantSpend) continue;

        final meta = m['metadata'];
        final rawCategory = (meta is Map ? meta['category'] : null)?.toString();
        if (rawCategory == null || rawCategory.trim().isEmpty) continue;
        final display = rawCategory.trim();
        final key = _normCategory(display);
        if (key.isEmpty) continue;

        final amount = _round2(_readAmount(m['amount']));
        if (amount <= 0) continue;

        final rowCurrency = m['currency_code']?.toString();

        DateTime latest;
        try {
          latest = DateTime.parse((m['updated_at'] ?? m['created_at']).toString()).toUtc();
        } catch (_) {
          latest = DateTime.now().toUtc();
        }

        final existing = byCategory[key];
        if (existing == null) {
          byCategory[key] = (
            display: display,
            received: isReceivedCoupon ? amount : 0,
            spent: isMyMerchantSpend ? amount : 0,
            latest: latest,
            currency: rowCurrency,
          );
        } else {
          byCategory[key] = (
            display: existing.display,
            received: _round2(existing.received + (isReceivedCoupon ? amount : 0)),
            spent: _round2(existing.spent + (isMyMerchantSpend ? amount : 0)),
            latest: latest.isAfter(existing.latest) ? latest : existing.latest,
            currency: existing.currency ?? rowCurrency,
          );
        }
      }

      final list = byCategory.values
          .map((v) {
            final remaining = _round2(v.received - v.spent);
            return CategoryBalance(category: v.display, balance: remaining, latestAt: v.latest, currencyCode: v.currency);
          })
          .where((b) => b.balance > 0)
          .toList(growable: false);

      list.sort((a, b) => b.latestAt.compareTo(a.latestAt));
      return list;
    } catch (e) {
      debugPrint('TransactionService.getMyRemainingCouponCategoryBalances failed: $e');
      return const [];
    }
  }

  Future<TransferResult> transferUserToUser({
    required String receiverUserId,
    required double amount,
    String? note,
    String? transferCategory,
    String? paymentMethodId,
  }) async {
    try {
      final res = await SupabaseService.rpc(
        'transfer_user_to_user',
        params: {
          'receiver_user_id': receiverUserId,
          'transfer_amount': amount,
          'transfer_note': note,
          'transfer_category': transferCategory,
          'payment_method_id': paymentMethodId,
        },
      );

      if (res is Map) return TransferResult.fromJson(Map<String, dynamic>.from(res));
      return const TransferResult(success: false, error: 'Unexpected RPC response');
    } catch (e) {
      debugPrint('TransactionService.transferUserToUser failed: $e');
      return TransferResult(success: false, error: e.toString());
    }
  }

  Future<TransferResult> transferUserToMerchant({
    required String merchantUniqueId,
    required double amount,
    String? note,
    String? transferCategory,
    String? paymentMethodId,
  }) async {
    try {
      final res = await SupabaseService.rpc(
        'transfer_user_to_merchant',
        params: {
          'merchant_unique_id': merchantUniqueId,
          'transfer_amount': amount,
          'transfer_note': note,
          'transfer_category': transferCategory,
          'payment_method_id': paymentMethodId,
        },
      );

      if (res is Map) return TransferResult.fromJson(Map<String, dynamic>.from(res));
      return const TransferResult(success: false, error: 'Unexpected RPC response');
    } catch (e) {
      debugPrint('TransactionService.transferUserToMerchant failed: $e');
      return TransferResult(success: false, error: e.toString());
    }
  }
}
