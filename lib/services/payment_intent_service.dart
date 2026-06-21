import 'package:flutter/foundation.dart';
import 'package:caddymoney/core/config/supabase_config.dart';
import 'package:caddymoney/models/payment_intent_model.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

/// Service responsible for creating and reading Payment Intents.
///
/// SECURITY:
/// - Creation MUST go through a secure backend (Edge Function) so the server
///   can enforce validation rules (merchant status, amount bounds, expiry,
///   allowed services, etc.).
/// - The merchant app never finalizes the payment — it only creates requests.
class PaymentIntentService {
  static String _normalizeTypingCode(String input) => input.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '').toUpperCase();

  static String _friendlyRpcFailure(Map<String, dynamic> m) {
    final err = (m['error'] ?? 'Payment failed.').toString().trim();
    final code = m['code']?.toString().trim();
    final detail = m['detail']?.toString().trim();

    final combined = <String>[err];
    if (code != null && code.isNotEmpty) combined.add('(code: $code)');
    if (detail != null && detail.isNotEmpty) combined.add(detail);
    final raw = combined.join(' ');

    // A few high-signal server misconfig cases we can translate.
    final lower = raw.toLowerCase();
    if (lower.contains('uuid_generate_v4') && lower.contains('does not exist')) {
      // Supabase can generate UUIDs via either:
      // - uuid-ossp extension: uuid_generate_v4()
      // - pgcrypto extension: gen_random_uuid()
      // This message used to point only at uuid-ossp, but that can be misleading.
      return 'Server cannot generate UUIDs (missing uuid-ossp/pgcrypto). Please ask an admin to enable UUID generation.';
    }
    return raw;
  }

  static String _friendlySupabaseError(Object error) {
    if (error is PostgrestException) {
      final base = error.message.trim().isEmpty ? 'Payment failed.' : error.message.trim();

      // Try to map common validation failures to a user-friendly copy.
      final msgLower = base.toLowerCase();
      if (msgLower.contains('insufficient') && msgLower.contains('balance')) return 'Insufficient coupon balance for this payment.';
      if (msgLower.contains('category') && (msgLower.contains('not') || msgLower.contains('mismatch'))) {
        return 'This coupon is not eligible for this merchant category.';
      }
      if (msgLower.contains('already paid') || msgLower.contains('already_paid')) return 'This QR code was already paid.';
      if (msgLower.contains('expired')) return 'This payment request has expired.';
      if (msgLower.contains('not found')) return 'Payment intent not found (it may have expired).';
      if (msgLower.contains('unauthorized') || msgLower.contains('jwt') || msgLower.contains('not authenticated')) {
        return 'Unauthorized. Please sign in again.';
      }

      return base;
    }

    final s = error.toString();
    if (s.contains('Not authenticated')) return 'Unauthorized. Please sign in again.';
    return 'Payment failed. Please try again.';
  }

  static String? _categoryFromSyntheticCouponId(String couponId) {
    final trimmed = couponId.trim();
    if (!trimmed.startsWith('category:')) return null;
    final key = trimmed.substring('category:'.length).trim();
    if (key.isEmpty) return null;
    return key;
  }

  Future<({bool success, String? error, String? transactionId, String? transactionReference, bool alreadyPaid})> confirmPaymentWithCoupon({
    required String paymentIntentId,
    required String couponId,
  }) async {
    try {
      final session = SupabaseConfig.client.auth.currentSession;
      if (session == null) {
        return (success: false, error: 'Unauthorized. Please sign in again.', transactionId: null, transactionReference: null, alreadyPaid: false);
      }

      debugPrint('PaymentIntentService.confirmPaymentWithCoupon start intent=$paymentIntentId coupon=$couponId');

      // Some deployments store category budgets in the transactions ledger (not public.coupons).
      // In that case CouponService synthesizes ids like "category:healthcare".
      // We route those to a backend function that validates atomically.
      final categoryKey = _categoryFromSyntheticCouponId(couponId);
      if (categoryKey != null) {
        final res = await SupabaseConfig.client.rpc(
          'pay_payment_intent_with_category',
          params: {
            'p_payment_intent_id': paymentIntentId,
            'p_category_key': categoryKey,
          },
        );

        debugPrint('PaymentIntentService.confirmPaymentWithCoupon(category) rpc resultType=${res.runtimeType}');

        if (res is Map) {
          final m = Map<String, dynamic>.from(res);
          debugPrint('PaymentIntentService.confirmPaymentWithCoupon(category) rpc keys=${m.keys.toList()}');
          // Safe-ish: do not log any JWTs. This is server-returned metadata only.
          // Truncate very large strings just in case.
          try {
            final encoded = jsonEncode(m);
            debugPrint(
              'PaymentIntentService.confirmPaymentWithCoupon(category) rpc json=${encoded.length > 1500 ? '${encoded.substring(0, 1500)}…' : encoded}',
            );
          } catch (_) {}
          final ok = m['success'] == true;
          if (!ok) {
            return (success: false, error: _friendlyRpcFailure(m), transactionId: null, transactionReference: null, alreadyPaid: false);
          }
          return (
            success: true,
            error: null,
            transactionId: m['transaction_id']?.toString(),
            transactionReference: m['transaction_reference']?.toString(),
            alreadyPaid: m['already_paid'] == true,
          );
        }

        return (success: false, error: 'Unexpected server response.', transactionId: null, transactionReference: null, alreadyPaid: false);
      }

      final res = await SupabaseConfig.client.rpc(
        'pay_payment_intent_with_coupon',
        params: {
          'p_payment_intent_id': paymentIntentId,
          'p_coupon_id': couponId,
        },
      );

      debugPrint('PaymentIntentService.confirmPaymentWithCoupon(coupon) rpc resultType=${res.runtimeType}');

      if (res is Map) {
        final m = Map<String, dynamic>.from(res);
        debugPrint('PaymentIntentService.confirmPaymentWithCoupon(coupon) rpc keys=${m.keys.toList()}');
        try {
          final encoded = jsonEncode(m);
          debugPrint(
            'PaymentIntentService.confirmPaymentWithCoupon(coupon) rpc json=${encoded.length > 1500 ? '${encoded.substring(0, 1500)}…' : encoded}',
          );
        } catch (_) {}
        final ok = m['success'] == true;
        if (!ok) {
          return (success: false, error: _friendlyRpcFailure(m), transactionId: null, transactionReference: null, alreadyPaid: false);
        }
        return (
          success: true,
          error: null,
          transactionId: m['transaction_id']?.toString(),
          transactionReference: m['transaction_reference']?.toString(),
          alreadyPaid: m['already_paid'] == true,
        );
      }

      return (success: false, error: 'Unexpected server response.', transactionId: null, transactionReference: null, alreadyPaid: false);
    } on PostgrestException catch (e) {
      debugPrint('PaymentIntentService.confirmPaymentWithCoupon PostgrestException: message="${e.message}" code=${e.code} details=${e.details} hint=${e.hint}');
      return (success: false, error: _friendlySupabaseError(e), transactionId: null, transactionReference: null, alreadyPaid: false);
    } on AuthException catch (e) {
      debugPrint('PaymentIntentService.confirmPaymentWithCoupon AuthException: ${e.message}');
      return (success: false, error: 'Unauthorized. Please sign in again.', transactionId: null, transactionReference: null, alreadyPaid: false);
    } catch (e) {
      debugPrint('PaymentIntentService.confirmPaymentWithCoupon failed: $e');
      return (success: false, error: _friendlySupabaseError(e), transactionId: null, transactionReference: null, alreadyPaid: false);
    }
  }

  /// Creates a new payment intent via Supabase Edge Function.
  ///
  /// The returned intent contains a short [PaymentIntentModel.token] which should
  /// be encoded in the QR code.
  Future<({PaymentIntentModel? intent, String? error})> createPaymentIntent({
    required double amount,
    String currencyCode = 'EUR',
  }) async {
    final body = {
      'amount': amount,
      'currency_code': currencyCode,
    };
    try {
      if (amount.isNaN || amount.isInfinite || amount <= 0) {
        return (intent: null, error: 'Please enter a valid amount.');
      }

      final session = SupabaseConfig.client.auth.currentSession;
      if (session == null) {
        return (intent: null, error: 'Unauthorized. Please sign in again.');
      }

      // Use a direct HTTP call to the Edge Function endpoint.
      // This avoids any SDK/platform quirks around header forwarding.
      final data = await _callCreatePaymentIntentHttp(body, accessToken: session.accessToken);

      if (data is Map && data['success'] == true && data['payment_intent'] is Map) {
        final piJson = Map<String, dynamic>.from(data['payment_intent'] as Map);
        debugPrint('PaymentIntentService.createPaymentIntent payment_intent keys=${piJson.keys.toList()}');
        final pi = PaymentIntentModel.fromJson(piJson);
        if ((pi.shortCode ?? '').trim().isEmpty) {
          debugPrint('PaymentIntentService.createPaymentIntent: short_code missing; using QR-only flow.');
        }
        return (intent: pi, error: null);
      }

      if (data is Map) {
        return (intent: null, error: (data['error'] ?? 'Request failed.').toString());
      }

      return (intent: null, error: 'Request failed.');
    } on http.ClientException catch (e) {
      debugPrint('PaymentIntentService.createPaymentIntent http error: $e');
      return (intent: null, error: 'Network error. Please try again.');
    } catch (e) {
      debugPrint('PaymentIntentService.createPaymentIntent failed: $e');
      return (intent: null, error: e.toString());
    }
  }

  /// Fetches the latest state of a payment intent by id.
  ///
  /// This is used as a fallback when realtime subscriptions are not available
  /// (e.g. Realtime not enabled for the table) so the UI can still react to
  /// successful/expired payments.
  Future<PaymentIntentModel?> getPaymentIntentById(String id) async {
    try {
      final rows = await SupabaseConfig.client.from('payment_intents').select().eq('id', id).limit(1);
      if (rows is List && rows.isNotEmpty) {
        final first = rows.first;
        if (first is Map) return PaymentIntentModel.fromJson(Map<String, dynamic>.from(first));
      }
      return null;
    } on PostgrestException catch (e) {
      debugPrint('PaymentIntentService.getPaymentIntentById PostgrestException: message="${e.message}" code=${e.code} details=${e.details} hint=${e.hint}');
      return null;
    } catch (e) {
      debugPrint('PaymentIntentService.getPaymentIntentById failed: $e');
      return null;
    }
  }

  Future<dynamic> _callCreatePaymentIntentHttp(
    Map<String, dynamic> body, {
    required String accessToken,
  }) async {
    final jwt = accessToken.trim().replaceAll(RegExp(r'\s+'), '');

    // Avoid logging the token itself; just confirm it looks present.
    debugPrint('PaymentIntentService.invoke: accessToken.len=${accessToken.length}');
    if (jwt.length != accessToken.length) debugPrint('PaymentIntentService.invoke: sanitizedJwt.len=${jwt.length}');
    debugPrint('PaymentIntentService.invoke: jwtInfo=${_describeJwt(jwt)}');

    final uri = Uri.parse('${SupabaseConfig.supabaseUrl}/functions/v1/payment_intent_create');
    final res = await http.post(
      uri,
      headers: {
        // The Functions gateway can be picky; send both casings.
        'Authorization': 'Bearer $jwt',
        'authorization': 'Bearer $jwt',
        // Supabase functions gateway also expects apikey.
        'apikey': SupabaseConfig.anonKey,
        // Helps mimic official clients (and can be useful in logs).
        'x-client-info': 'caddymoney-flutter',
        'Content-Type': 'application/json',
        'Accept': 'application/json',
      },
      body: jsonEncode(body),
    );

    // Attempt to decode response as JSON for better error messages.
    dynamic decoded;
    try {
      decoded = jsonDecode(utf8.decode(res.bodyBytes));
    } catch (_) {
      decoded = res.body;
    }

    if (res.statusCode == 401) {
      debugPrint('PaymentIntentService.invoke 401: headers=${_safeHeaders(res.headers)}');
      debugPrint('PaymentIntentService.invoke 401: body=$decoded');

      // Probe auth endpoint with the same JWT to confirm the token is valid for this project.
      await _probeAuthUser(jwt);

      // Refresh once and retry.
      final retry = await _refreshAndRetryHttp(body);
      if (retry != null) return retry;
    }

    if (res.statusCode < 200 || res.statusCode >= 300) {
      final message = decoded is Map
          ? (decoded['message'] ?? decoded['error'] ?? 'Request failed.').toString()
          : 'Request failed.';
      throw Exception('Edge Function error (${res.statusCode}): $message');
    }

    return decoded;
  }

  /// Resolves a QR token (or payment intent id) to server-authoritative details.
  ///
  /// SECURITY: the QR string is NOT treated as proof — the backend is the source
  /// of truth.
  Future<({PaymentIntentModel? intent, String? merchantName, List<String> merchantCategories, String? error, int? statusCode})> resolvePaymentIntent({
    required String tokenOrId,
  }) async {
    final trimmed = tokenOrId.trim();
    if (trimmed.isEmpty) return (intent: null, merchantName: null, merchantCategories: const <String>[], error: 'Invalid QR code.', statusCode: 400);

    // If the user typed the short code (often shown as XXXX-XXXX), normalize it to the
    // stored format (8 alnum, uppercase) before sending to the backend.
    final normalized = _normalizeTypingCode(trimmed);
    final tokenOrIdToSend = normalized.length == 8 ? normalized : trimmed;

    try {
      final session = SupabaseConfig.client.auth.currentSession;
      if (session == null) {
        return (intent: null, merchantName: null, merchantCategories: const <String>[], error: 'Unauthorized. Please sign in again.', statusCode: 401);
      }

      final data = await _callResolvePaymentIntentHttp({'token_or_id': tokenOrIdToSend}, accessToken: session.accessToken);

      if (data is Map && data['success'] == true && data['payment_intent'] is Map) {
        final piMap = Map<String, dynamic>.from(data['payment_intent'] as Map);
        final merchant = piMap['merchant'];
        final merchantName = merchant is Map ? merchant['business_name']?.toString() : null;
        final rawCategories = merchant is Map ? merchant['categories'] : null;
        final categories = rawCategories is List ? rawCategories.map((e) => e.toString()).where((e) => e.trim().isNotEmpty).toList() : <String>[];
        final pi = PaymentIntentModel.fromJson(piMap);
        return (intent: pi, merchantName: merchantName, merchantCategories: categories, error: null, statusCode: 200);
      }

      if (data is Map) {
        return (intent: null, merchantName: null, merchantCategories: const <String>[], error: (data['error'] ?? data['message'] ?? 'Request failed.').toString(), statusCode: null);
      }
      return (intent: null, merchantName: null, merchantCategories: const <String>[], error: 'Request failed.', statusCode: null);
    } on http.ClientException catch (e) {
      debugPrint('PaymentIntentService.resolvePaymentIntent http error: $e');
      return (intent: null, merchantName: null, merchantCategories: const <String>[], error: 'Network error. Please try again.', statusCode: null);
    } catch (e) {
      debugPrint('PaymentIntentService.resolvePaymentIntent failed: $e');
      // Parse the thrown message from _callResolvePaymentIntentHttp so we can surface a
      // user-friendly message for common HTTP status codes.
      final msg = e.toString();
      final m = RegExp(r'Edge Function error \((\d+)\):').firstMatch(msg);
      final code = int.tryParse(m?.group(1) ?? '');
      if (code == 404) {
        return (intent: null, merchantName: null, merchantCategories: const <String>[], error: 'Payment request not found.', statusCode: 404);
      }
      if (code == 401) {
        return (intent: null, merchantName: null, merchantCategories: const <String>[], error: 'Unauthorized. Please sign in again.', statusCode: 401);
      }
      return (intent: null, merchantName: null, merchantCategories: const <String>[], error: msg, statusCode: code);
    }
  }

  Future<dynamic> _callResolvePaymentIntentHttp(
    Map<String, dynamic> body, {
    required String accessToken,
  }) async {
    final jwt = accessToken.trim().replaceAll(RegExp(r'\s+'), '');

    final uri = Uri.parse('${SupabaseConfig.supabaseUrl}/functions/v1/payment_intent_resolve');
    final res = await http.post(
      uri,
      headers: {
        'Authorization': 'Bearer $jwt',
        'authorization': 'Bearer $jwt',
        'apikey': SupabaseConfig.anonKey,
        'x-client-info': 'caddymoney-flutter',
        'Content-Type': 'application/json',
        'Accept': 'application/json',
      },
      body: jsonEncode(body),
    );

    dynamic decoded;
    try {
      decoded = jsonDecode(utf8.decode(res.bodyBytes));
    } catch (_) {
      decoded = res.body;
    }

    if (res.statusCode < 200 || res.statusCode >= 300) {
      String message;
      if (decoded is Map) {
        final base = (decoded['message'] ?? decoded['error'] ?? 'Request failed.').toString();
        final supabase = decoded['supabase'];
        if (supabase is Map) {
          final sbMsg = (supabase['message'] ?? '').toString().trim();
          final code = (supabase['code'] ?? '').toString().trim();
          final hint = (supabase['hint'] ?? '').toString().trim();
          final details = (supabase['details'] ?? '').toString().trim();
          final extras = [
            if (code.isNotEmpty) 'code=$code',
            if (sbMsg.isNotEmpty) 'message=$sbMsg',
            if (hint.isNotEmpty) 'hint=$hint',
            if (details.isNotEmpty) 'details=$details',
          ].join(' | ');
          message = extras.isEmpty ? base : '$base ($extras)';
        } else {
          message = base;
        }
      } else {
        message = 'Request failed.';
      }
      throw Exception('Edge Function error (${res.statusCode}): $message');
    }

    return decoded;
  }

  /// Decodes a JWT payload for debugging without logging the token itself.
  ///
  /// This helps confirm whether the access token belongs to the same Supabase
  /// project (ref/iss) as the Edge Function endpoint.
  static String _describeJwt(String token) {
    try {
      final parts = token.split('.');
      if (parts.length != 3) return '{not_jwt:true, parts:${parts.length}}';

      final payloadB64 = parts[1];
      final normalized = base64Url.normalize(payloadB64);
      final payloadJson = utf8.decode(base64Url.decode(normalized));
      final payload = jsonDecode(payloadJson);
      if (payload is! Map) return '{payload_not_map:true}';

      final safe = <String, dynamic>{
        'iss': payload['iss'],
        'sub': payload['sub'],
        'aud': payload['aud'],
        'exp': payload['exp'],
        'iat': payload['iat'],
        'role': payload['role'],
        'email': payload['email'],
        'ref': payload['ref'],
      };
      return jsonEncode(safe);
    } catch (e) {
      return '{jwt_decode_error:${e.runtimeType}}';
    }
  }

  static Map<String, String> _safeHeaders(Map<String, String> headers) {
    // Avoid logging cookies or authorization headers if any proxy adds them.
    final safe = <String, String>{};
    for (final entry in headers.entries) {
      final k = entry.key.toLowerCase();
      if (k == 'set-cookie' || k == 'cookie' || k == 'authorization') continue;
      safe[entry.key] = entry.value;
    }
    return safe;
  }

  Future<void> _probeAuthUser(String jwt) async {
    try {
      final uri = Uri.parse('${SupabaseConfig.supabaseUrl}/auth/v1/user');
      final res = await http.get(
        uri,
        headers: {
          'Authorization': 'Bearer $jwt',
          'apikey': SupabaseConfig.anonKey,
          'Accept': 'application/json',
        },
      );
      debugPrint('PaymentIntentService.authProbe: status=${res.statusCode}');
      final body = utf8.decode(res.bodyBytes);
      // Body may include PII; keep it short.
      debugPrint('PaymentIntentService.authProbe: bodyPrefix=${body.substring(0, body.length.clamp(0, 180))}');
    } catch (e) {
      debugPrint('PaymentIntentService.authProbe failed: $e');
    }
  }

  Future<dynamic> _refreshAndRetryHttp(Map<String, dynamic> body) async {
    try {
      final refreshed = await SupabaseConfig.auth.refreshSession();
      final accessToken = refreshed.session?.accessToken ?? SupabaseConfig.client.auth.currentSession?.accessToken;
      if (accessToken == null) return null;
      final jwt = accessToken.trim().replaceAll(RegExp(r'\s+'), '');

      final uri = Uri.parse('${SupabaseConfig.supabaseUrl}/functions/v1/payment_intent_create');
      final res = await http.post(
        uri,
        headers: {
          'Authorization': 'Bearer $jwt',
          'authorization': 'Bearer $jwt',
          'apikey': SupabaseConfig.anonKey,
          'x-client-info': 'caddymoney-flutter',
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
        body: jsonEncode(body),
      );

      dynamic decoded;
      try {
        decoded = jsonDecode(utf8.decode(res.bodyBytes));
      } catch (_) {
        decoded = res.body;
      }

      if (res.statusCode < 200 || res.statusCode >= 300) {
        debugPrint('PaymentIntentService.refresh+retry failed: status=${res.statusCode}; body=$decoded');
        return null;
      }

      return decoded;
    } catch (e) {
      debugPrint('PaymentIntentService.refresh+retry failed: $e');
      return null;
    }
  }
}
