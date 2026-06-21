import 'package:flutter/foundation.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:caddymoney/core/constants/app_constants.dart';
import 'package:caddymoney/models/merchant_model.dart';
import 'package:caddymoney/core/config/supabase_config.dart';
import 'package:file_selector/file_selector.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class MerchantService {
  static final Map<String, String> _businessNameCache = <String, String>{};
  static final Map<String, Future<String?>> _businessNameInFlight = <String, Future<String?>>{};

  /// Returns a merchant's business name by its merchant row id.
  ///
  /// This is used as a fallback for UI when PostgREST join data isn't available
  /// (e.g. missing FK relationship / older schema). Results are cached in-memory
  /// for the app session.
  Future<String?> getBusinessNameByMerchantId(String merchantId) {
    final id = merchantId.trim();
    if (id.isEmpty) return Future.value(null);

    final cached = _businessNameCache[id];
    if (cached != null) return Future.value(cached);

    final inflight = _businessNameInFlight[id];
    if (inflight != null) return inflight;

    final fut = () async {
      try {
        // In some schemas `transactions.receiver_merchant_id` can reference either:
        //  - merchants.id (merchant row id)
        //  - merchants.profile_id (the merchant's auth/profile id)
        // The PostgREST join may fail if FK relationships aren't configured.
        // So we attempt both lookups for maximum robustness.
        Map<String, dynamic>? row;
        try {
          row = await SupabaseService.selectSingle(
            'merchants',
            select: 'business_name',
            filters: {'id': id},
          );
        } catch (e) {
          debugPrint('MerchantService.getBusinessNameByMerchantId lookup by id failed: $e');
        }

        if (row == null) {
          try {
            row = await SupabaseService.selectSingle(
              'merchants',
              select: 'business_name',
              filters: {'profile_id': id},
            );
          } catch (e) {
            debugPrint('MerchantService.getBusinessNameByMerchantId lookup by profile_id failed: $e');
          }
        }

        final name = row?['business_name']?.toString().trim();
        if (name != null && name.isNotEmpty) _businessNameCache[id] = name;
        if (name == null || name.isEmpty) {
          debugPrint(
            'MerchantService.getBusinessNameByMerchantId: no business_name for merchantId=$id '
            '(row=${row == null ? 'null' : row.toString()}). '
            'This is often caused by merchants table RLS blocking selects for standard users.',
          );
          return null;
        }
        return name;
      } catch (e) {
        debugPrint('MerchantService.getBusinessNameByMerchantId failed: $e');
        return null;
      } finally {
        _businessNameInFlight.remove(id);
      }
    }();

    _businessNameInFlight[id] = fut;
    return fut;
  }

  Future<({bool ok, String? error, List<String>? missingFields, bool? emailSent, bool? emailSkipped})> decideMerchantReviewResult({
    required String merchantId,
    required String decision,
    String? reason,
  }) async {
    try {
      final adminId = SupabaseConfig.auth.currentUser?.id;
      if (adminId == null) {
        return (ok: false, error: 'Not signed in.', missingFields: null, emailSent: null, emailSkipped: null);
      }

      // Prefer the built-in Supabase auth forwarding for Edge Functions.
      // Only fall back to explicitly sending a Bearer token if we still get 401.
      final res = await _invokeMerchantReviewDecide(merchantId: merchantId, decision: decision, reason: reason);

      final data = res.data;
      if (data is Map && data['success'] == true) {
        return (
          ok: true,
          error: null,
          missingFields: null,
          emailSent: data['email_sent'] as bool?,
          emailSkipped: data['email_skipped'] as bool?,
        );
      }

      // Supabase functions can return a JSON map with an error field.
      if (data is Map) {
        final missing = data['missing_fields'];
        final missingFields = missing is List ? missing.map((e) => e.toString()).toList() : null;
        return (
          ok: false,
          error: (data['error'] ?? 'Request failed.').toString(),
          missingFields: missingFields,
          emailSent: null,
          emailSkipped: null,
        );
      }

      return (ok: false, error: 'Request failed.', missingFields: null, emailSent: null, emailSkipped: null);
    } on FunctionException catch (e) {
      debugPrint('MerchantService.decideMerchantReviewResult function error: $e');
      debugPrint('FunctionException status: ${e.status}; details: ${e.details}');
      _debugLogCurrentSession(context: 'merchant_review_decide/catch');

      // If the access token is expired, attempt a single refresh + retry.
      if (e.status == 401) {
        final retry = await _refreshAndRetry(merchantId: merchantId, decision: decision, reason: reason);
        if (retry != null) return retry;
      }

      final details = e.details;
      if (details is Map && details['error'] != null) {
        final missing = details['missing_fields'];
        final missingFields = missing is List ? missing.map((e) => e.toString()).toList() : null;
        return (
          ok: false,
          error: details['error'].toString(),
          missingFields: missingFields,
          emailSent: null,
          emailSkipped: null,
        );
      }
      final status = e.status;

      // If the Supabase Functions gateway rejects the token as "Invalid JWT" even
      // after refresh, the local session is likely stale/corrupted.
      final detailsMsg = details is Map ? (details['message'] ?? details['error'])?.toString() : null;
      if (status == 401 && detailsMsg != null && detailsMsg.toLowerCase().contains('invalid jwt')) {
        try {
          await SupabaseConfig.auth.signOut();
        } catch (signOutErr) {
          debugPrint('MerchantService: signOut after Invalid JWT failed: $signOutErr');
        }
        return (ok: false, error: 'Your session is invalid. Please sign in again.', missingFields: null, emailSent: null, emailSkipped: null);
      }

      final friendly = switch (status) {
        401 => 'Unauthorized. Please sign in again.',
        403 => 'Forbidden. Your account is not allowed to perform this action.',
        _ => 'Request failed ($status).',
      };
      return (ok: false, error: friendly, missingFields: null, emailSent: null, emailSkipped: null);
    } catch (e) {
      debugPrint('MerchantService.decideMerchantReviewResult failed: $e');
      return (ok: false, error: e.toString(), missingFields: null, emailSent: null, emailSkipped: null);
    }
  }

  /// Admin-only utility to update a merchant's categories.
  ///
  /// This is used from the admin review UI when a merchant selected the wrong
  /// categories and the admin wants to correct them before approval.
  Future<({bool ok, String? error})> adminUpdateMerchantCategories({required String merchantId, required List<String> categories}) async {
    try {
      final id = merchantId.trim();
      if (id.isEmpty) return (ok: false, error: 'Missing merchant id.');
      if (categories.isEmpty) return (ok: false, error: 'Select at least one category.');

      final updated = await SupabaseService.update(
        'merchants',
        {
          'categories': categories,
          'updated_at': DateTime.now().toIso8601String(),
        },
        filters: {'id': id},
      );
      if (updated.isNotEmpty) return (ok: true, error: null);
      debugPrint('MerchantService.adminUpdateMerchantCategories: update returned 0 rows for merchantId=$id');
      return (ok: false, error: 'Merchant could not be updated.');
    } catch (e) {
      debugPrint('MerchantService.adminUpdateMerchantCategories failed: $e');
      return (ok: false, error: e.toString());
    }
  }

  Future<FunctionResponse> _invokeMerchantReviewDecide({
    required String merchantId,
    required String decision,
    String? reason,
  }) async {
    final trimmedReason = (reason ?? '').trim();
    final body = {
      'merchant_id': merchantId,
      'decision': decision,
      if (trimmedReason.isNotEmpty) 'reason': trimmedReason,
    };

    // IMPORTANT:
    // Do NOT manually override Authorization headers unless strictly necessary.
    // Supabase Flutter forwards the current session automatically.
    _debugLogCurrentSession(context: 'merchant_review_decide/invoke');
    return SupabaseConfig.client.functions.invoke('merchant_review_decide', body: body);
  }

  static void _debugLogCurrentSession({required String context}) {
    try {
      final session = SupabaseConfig.auth.currentSession;
      final uid = SupabaseConfig.auth.currentUser?.id;
      final accessToken = session?.accessToken;
      final expiresAt = session?.expiresAt;
      debugPrint(
        'MerchantService: session debug [$context] user=${uid ?? 'null'} '
        'token=${accessToken == null ? 'null' : 'present(len=${accessToken.length})'} '
        'expiresAt=${expiresAt ?? 'null'}',
      );
    } catch (e) {
      debugPrint('MerchantService: session debug [$context] failed: $e');
    }
  }

  Future<({bool ok, String? error, List<String>? missingFields, bool? emailSent, bool? emailSkipped})?> _refreshAndRetry({
    required String merchantId,
    required String decision,
    String? reason,
  }) async {
    try {
      debugPrint('MerchantService: attempting auth.refreshSession() after 401...');
      await SupabaseConfig.auth.refreshSession();

      final res = await _invokeMerchantReviewDecide(merchantId: merchantId, decision: decision, reason: reason);
      final data = res.data;
      if (data is Map && data['success'] == true) {
        return (
          ok: true,
          error: null,
          missingFields: null,
          emailSent: data['email_sent'] as bool?,
          emailSkipped: data['email_skipped'] as bool?,
        );
      }
      if (data is Map) {
        final missing = data['missing_fields'];
        final missingFields = missing is List ? missing.map((e) => e.toString()).toList() : null;
        return (
          ok: false,
          error: (data['error'] ?? 'Request failed.').toString(),
          missingFields: missingFields,
          emailSent: null,
          emailSkipped: null,
        );
      }
      return (ok: false, error: 'Request failed.', missingFields: null, emailSent: null, emailSkipped: null);
    } catch (e) {
      debugPrint('MerchantService: refresh+retry failed: $e');
      return null;
    }
  }

  Future<({bool ok, String? error})> updateMyMerchantKycResult({
    required String businessType,
    String? registrationNumber,
    String? vatNumber,
    required DateTime dateOfBirth,
    required String nationality,
    required String iban,
    required String accountHolderName,
    required List<String> categories,
    String? idDocumentPath,
    String? businessRegistrationDocPath,
    String? logoPath,
    bool submitForReview = true,
    // Used only as a fallback when the merchants row doesn't exist yet.
    String? businessName,
    String? ownerFirstName,
    String? ownerLastName,
    String? businessEmail,
    String? businessPhone,
    String? addressLine1,
    String? addressLine2,
    String? city,
    String? postalCode,
    String? countryName,
  }) async {
    try {
      final uid = SupabaseConfig.auth.currentUser?.id;
      if (uid == null) return (ok: false, error: 'Not signed in.');

      String? currentStatus;
      if (submitForReview) {
        try {
          final existing = await SupabaseService.selectSingle('merchants', filters: {'profile_id': uid});
          currentStatus = existing?['status']?.toString();
        } catch (e) {
          debugPrint('MerchantService.updateMyMerchantKyc failed to read current status: $e');
        }
      }

      Future<List<dynamic>> doUpdate({required bool includeLogo}) async {
        final dobString = '${dateOfBirth.year.toString().padLeft(4, '0')}-${dateOfBirth.month.toString().padLeft(2, '0')}-${dateOfBirth.day.toString().padLeft(2, '0')}';
        final payload = <String, dynamic>{
          'business_type': businessType,
          'registration_number': registrationNumber,
          'vat_number': vatNumber,
          // Postgres column type is DATE (not timestamptz). Send YYYY-MM-DD.
          'date_of_birth': dobString,
          'nationality': nationality,
          'iban': iban,
          'account_holder_name': accountHolderName,
          'categories': categories,
          'id_document_path': idDocumentPath,
          'business_registration_doc_path': businessRegistrationDocPath,
          'profile_completed': true,
          'profile_completed_at': DateTime.now().toIso8601String(),
        };

        // Mark as pending when a merchant submits KYC, but don't downgrade approved merchants.
        if (submitForReview && (currentStatus == null || currentStatus.toLowerCase() != 'approved')) {
          payload['status'] = 'pending';
        }
        if (includeLogo && logoPath != null) payload['logo_path'] = logoPath;
        return await SupabaseService.update('merchants', payload, filters: {'profile_id': uid});
      }

      List<dynamic> updated;
      try {
        updated = await doUpdate(includeLogo: true);
      } catch (e) {
        // Backward-compatible: if the DB schema doesn't include `logo_path` yet,
        // retry without it so merchants can still submit KYC.
        if (logoPath != null) {
          debugPrint('Update with logo_path failed; retrying without logo_path. Error: $e');
          updated = await doUpdate(includeLogo: false);
        } else {
          rethrow;
        }
      }

      if (updated.isNotEmpty) return (ok: true, error: null);

      debugPrint('MerchantService.updateMyMerchantKyc: update returned 0 rows for profile_id=$uid');
      // Fallback: ensure the merchant row exists (edge function uses service role).
      final bootstrapError = await _ensurePendingMerchantRow(
        profileId: uid,
        businessName: businessName,
        ownerFirstName: ownerFirstName,
        ownerLastName: ownerLastName,
        businessEmail: businessEmail,
        businessPhone: businessPhone,
        categories: categories,
        addressLine1: addressLine1,
        addressLine2: addressLine2,
        city: city,
        postalCode: postalCode,
        countryName: countryName,
      );

      if (bootstrapError != null) {
        return (ok: false, error: bootstrapError);
      }

      // Retry update now that the row should exist.
      updated = await doUpdate(includeLogo: logoPath != null);
      if (updated.isNotEmpty) return (ok: true, error: null);
      return (
        ok: false,
        error: 'Merchant record could not be updated. This is usually caused by Supabase RLS policies. Please contact support.',
      );
    } catch (e) {
      debugPrint('MerchantService.updateMyMerchantKycResult failed: $e');
      return (ok: false, error: e.toString());
    }
  }

  Future<String?> _ensurePendingMerchantRow({
    required String profileId,
    required List<String> categories,
    String? businessName,
    String? ownerFirstName,
    String? ownerLastName,
    String? businessEmail,
    String? businessPhone,
    String? addressLine1,
    String? addressLine2,
    String? city,
    String? postalCode,
    String? countryName,
  }) async {
    try {
      // If we can already read the row, don't do anything.
      try {
        final existing = await SupabaseService.selectSingle('merchants', filters: {'profile_id': profileId});
        if (existing != null) return null;
      } catch (_) {
        // Ignore; we might not have read permissions.
      }

      final bn = (businessName ?? '').trim();
      final fn = (ownerFirstName ?? '').trim();
      final ln = (ownerLastName ?? '').trim();
      final em = (businessEmail ?? '').trim().toLowerCase();
      if (bn.isEmpty || fn.isEmpty || ln.isEmpty || em.isEmpty) {
        return 'We could not create your merchant record because some basic business details are missing. Please go back to Step 1 and ensure Business name, First name, Last name and Email are filled.';
      }

      final payload = {
        'profile_id': profileId,
        'business_name': bn,
        'owner_first_name': fn,
        'owner_last_name': ln,
        'business_email': em,
        'business_phone': (businessPhone ?? '').trim(),
        'categories': categories,
        'address_line1': (addressLine1 ?? '').trim(),
        'address_line2': (addressLine2 ?? '').trim().isEmpty ? null : (addressLine2 ?? '').trim(),
        'city': (city ?? '').trim(),
        'postal_code': (postalCode ?? '').trim(),
        'country_name': (countryName ?? '').trim(),
        'status': 'pending',
        'profile_completed': false,
      };

      final res = await SupabaseConfig.client.functions.invoke('merchant_create_pending', body: payload);
      final data = res.data;
      if (data is Map && data['success'] == true) return null;
      final err = (data is Map ? data['error'] : null)?.toString();
      debugPrint('merchant_create_pending fallback returned: $data');
      return err == null || err.isEmpty ? 'Failed to create merchant record. Please try again.' : err;
    } on FunctionException catch (e) {
      debugPrint('merchant_create_pending fallback function error: $e');
      // Edge functions often return a JSON body in `details`.
      final details = e.details;
      if (details is Map && details['error'] != null) {
        final msg = details['error'].toString().trim();
        if (msg.isNotEmpty) return msg;
      }
      return 'Failed to create merchant record (${e.status}). Please try again.';
    } catch (e) {
      debugPrint('MerchantService._ensurePendingMerchantRow failed: $e');
      return e.toString();
    }
  }
  Future<MerchantModel?> getMyMerchant() async {
    try {
      final uid = SupabaseConfig.auth.currentUser?.id;
      if (uid == null) return null;

      final row = await SupabaseService.selectSingle(
        'merchants',
        filters: {'profile_id': uid},
      );
      if (row == null) return null;
      return MerchantModel.fromJson(row);
    } catch (e) {
      debugPrint('MerchantService.getMyMerchant failed: $e');
      return null;
    }
  }

  Future<MerchantModel?> getMerchantById(String merchantId) async {
    try {
      final id = merchantId.trim();
      if (id.isEmpty) return null;
      final row = await SupabaseService.selectSingle(
        'merchants',
        filters: {'id': id},
      );
      if (row == null) return null;
      return MerchantModel.fromJson(row);
    } catch (e) {
      debugPrint('MerchantService.getMerchantById failed: $e');
      return null;
    }
  }

  Future<List<MerchantModel>> listMerchants({String? status, List<String>? statuses, bool? profileCompleted, int limit = 100}) async {
    try {
      return await _listMerchantsRaw(status: status, statuses: statuses, profileCompleted: profileCompleted, limit: limit);
    } catch (e) {
      debugPrint('MerchantService.listMerchants failed: $e');
      return [];
    }
  }

  Future<List<MerchantModel>> _listMerchantsRaw({String? status, List<String>? statuses, bool? profileCompleted, int limit = 100}) async {
    dynamic query = SupabaseService.from('merchants').select('*');
    if (status != null) {
      query = query.eq('status', status);
    }
    if (profileCompleted != null) {
      query = query.eq('profile_completed', profileCompleted);
    }
    query = query.order('created_at', ascending: false).limit(limit);
    final rows = await query;
    final safeRows = rows is List ? rows : const <dynamic>[];
    final filtered = (statuses != null && statuses.isNotEmpty)
        ? safeRows.whereType<Map>().where((m) => statuses.contains((m as Map)['status']?.toString())).toList()
        : safeRows.whereType<Map>().toList();
    return filtered.map((e) => MerchantModel.fromJson(Map<String, dynamic>.from(e as Map))).toList();
  }

  /// Admin-only: persist a merchant's coordinates.
  Future<({bool ok, String? error})> adminUpdateMerchantLocation({
    required String merchantId,
    required double latitude,
    required double longitude,
  }) async {
    try {
      final id = merchantId.trim();
      if (id.isEmpty) return (ok: false, error: 'Missing merchant id.');
      if (latitude.isNaN || longitude.isNaN) return (ok: false, error: 'Invalid coordinates.');

      final updated = await SupabaseService.update(
        'merchants',
        {
          'latitude': latitude,
          'longitude': longitude,
          'updated_at': DateTime.now().toIso8601String(),
        },
        filters: {'id': id},
      );
      if (updated.isNotEmpty) return (ok: true, error: null);
      debugPrint('MerchantService.adminUpdateMerchantLocation: update returned 0 rows for merchantId=$id');
      return (ok: false, error: 'Merchant could not be updated.');
    } catch (e) {
      debugPrint('MerchantService.adminUpdateMerchantLocation failed: $e');
      return (ok: false, error: e.toString());
    }
  }

  /// Attempts to geocode an address.
  ///
  /// - If `GOOGLE_MAPS_GEOCODING_API_KEY` is provided, uses Google Geocoding.
  /// - Otherwise, falls back to OpenStreetMap Nominatim (no API key required).
  Future<({double lat, double lng})?> geocodeAddress({
    required String address,
  }) async {
    const apiKey = String.fromEnvironment('GOOGLE_MAPS_GEOCODING_API_KEY');
    final trimmed = address.trim();
    if (trimmed.isEmpty) return null;
    try {
      // 1) Prefer Google if a key is present.
      if (apiKey.trim().isNotEmpty) {
        final uri = Uri.https(
          'maps.googleapis.com',
          '/maps/api/geocode/json',
          {'address': trimmed, 'key': apiKey},
        );
        final res = await http.get(uri);
        if (res.statusCode < 200 || res.statusCode >= 300) {
          debugPrint('MerchantService.geocodeAddress (google) failed: status=${res.statusCode} body=${res.body}');
          return null;
        }
        final decoded = jsonDecode(utf8.decode(res.bodyBytes));
        if (decoded is! Map) return null;
        final results = decoded['results'];
        if (results is! List || results.isEmpty) return null;
        final first = results.first;
        if (first is! Map) return null;
        final geometry = first['geometry'];
        if (geometry is! Map) return null;
        final location = geometry['location'];
        if (location is! Map) return null;
        final lat = location['lat'];
        final lng = location['lng'];
        if (lat is num && lng is num) return (lat: lat.toDouble(), lng: lng.toDouble());
        return null;
      }

      // 2) Otherwise, use OpenStreetMap Nominatim.
      // Nominatim usage policy requires a User-Agent.
      final uri = Uri.https(
        'nominatim.openstreetmap.org',
        '/search',
        {
          'q': trimmed,
          'format': 'json',
          'limit': '1',
        },
      );
      final res = await http.get(uri, headers: const {
        'User-Agent': 'caddymoney-admin/1.0 (Dreamflow)',
        'Accept': 'application/json',
      });
      if (res.statusCode < 200 || res.statusCode >= 300) {
        debugPrint('MerchantService.geocodeAddress (nominatim) failed: status=${res.statusCode} body=${res.body}');
        return null;
      }
      final decoded = jsonDecode(utf8.decode(res.bodyBytes));
      if (decoded is! List || decoded.isEmpty) return null;
      final first = decoded.first;
      if (first is! Map) return null;
      final latStr = first['lat'];
      final lngStr = first['lon'];
      final lat = latStr is String ? double.tryParse(latStr) : (latStr is num ? latStr.toDouble() : null);
      final lng = lngStr is String ? double.tryParse(lngStr) : (lngStr is num ? lngStr.toDouble() : null);
      if (lat == null || lng == null) return null;
      return (lat: lat, lng: lng);
    } catch (e) {
      debugPrint('MerchantService.geocodeAddress failed: $e');
      return null;
    }
  }

  Future<({List<MerchantModel> merchants, String? error})> listMerchantsResult({String? status, List<String>? statuses, bool? profileCompleted, int limit = 100}) async {
    try {
      final items = await _listMerchantsRaw(status: status, statuses: statuses, profileCompleted: profileCompleted, limit: limit);
      return (merchants: items, error: null);
    } catch (e) {
      debugPrint('MerchantService.listMerchantsResult failed: $e');
      return (merchants: const <MerchantModel>[], error: e.toString());
    }
  }

  Future<bool> approveMerchant({required String merchantId, String? reason}) async {
    try {
      final res = await decideMerchantReviewResult(merchantId: merchantId, decision: 'approve', reason: reason);
      if (res.ok) return true;
      debugPrint('MerchantService.approveMerchant failed via edge function: ${res.error}');
      return false;
    } catch (e) {
      debugPrint('MerchantService.approveMerchant failed: $e');
      return false;
    }
  }

  Future<bool> rejectMerchant({required String merchantId, required String reason}) async {
    try {
      final res = await decideMerchantReviewResult(merchantId: merchantId, decision: 'reject', reason: reason);
      if (res.ok) return true;
      debugPrint('MerchantService.rejectMerchant failed via edge function: ${res.error}');
      return false;
    } catch (e) {
      debugPrint('MerchantService.rejectMerchant failed: $e');
      return false;
    }
  }

  Future<bool> updateMyMerchantKyc({
    required String businessType,
    String? registrationNumber,
    String? vatNumber,
    required DateTime dateOfBirth,
    required String nationality,
    required String iban,
    required String accountHolderName,
    required List<String> categories,
    String? idDocumentPath,
    String? businessRegistrationDocPath,
    String? logoPath,
    bool submitForReview = true,
    String? businessName,
    String? ownerFirstName,
    String? ownerLastName,
    String? businessEmail,
    String? businessPhone,
    String? addressLine1,
    String? addressLine2,
    String? city,
    String? postalCode,
    String? countryName,
  }) async {
    final res = await updateMyMerchantKycResult(
      businessType: businessType,
      registrationNumber: registrationNumber,
      vatNumber: vatNumber,
      dateOfBirth: dateOfBirth,
      nationality: nationality,
      iban: iban,
      accountHolderName: accountHolderName,
      categories: categories,
      idDocumentPath: idDocumentPath,
      businessRegistrationDocPath: businessRegistrationDocPath,
      logoPath: logoPath,
      submitForReview: submitForReview,
      businessName: businessName,
      ownerFirstName: ownerFirstName,
      ownerLastName: ownerLastName,
      businessEmail: businessEmail,
      businessPhone: businessPhone,
      addressLine1: addressLine1,
      addressLine2: addressLine2,
      city: city,
      postalCode: postalCode,
      countryName: countryName,
    );
    if (!res.ok) debugPrint('MerchantService.updateMyMerchantKyc returning false: ${res.error}');
    return res.ok;
  }

  Future<({String? path, String? error})> uploadMerchantDocument({
    required String docType,
    required XFile file,
  }) async {
    try {
      final uid = SupabaseConfig.auth.currentUser?.id;
      if (uid == null) return (path: null, error: 'Not signed in.');

      final bytes = await file.readAsBytes();
      final name = file.name;
      final safeName = name.replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_');
      final path = 'merchant/$uid/$docType/${DateTime.now().millisecondsSinceEpoch}_$safeName';

      try {
        await SupabaseConfig.client.storage.from(AppConstants.kycStorageBucket).uploadBinary(
              path,
              bytes,
              fileOptions: FileOptions(upsert: true),
            );
      } on StorageException catch (e) {
        debugPrint('MerchantService.uploadMerchantDocument failed (storage): $e');
        final status = e.statusCode?.toString();
        if (status == '404' || e.message.toLowerCase().contains('bucket not found')) {
          return (
            path: null,
            error: 'Storage bucket not found: "${AppConstants.kycStorageBucket}". Create it in Supabase Storage or update the bucket name in AppConstants.kycStorageBucket.',
          );
        }
        if (status == '403' && e.message.toLowerCase().contains('row-level security')) {
          return (
            path: null,
            error:
                'Upload blocked by Supabase Storage RLS (403). You need an INSERT policy on storage.objects for bucket "${AppConstants.kycStorageBucket}" that allows this user to upload to: $path',
          );
        }
        return (path: null, error: e.message);
      }

      return (path: path, error: null);
    } catch (e) {
      debugPrint('MerchantService.uploadMerchantDocument failed: $e');
      return (path: null, error: e.toString());
    }
  }
}
