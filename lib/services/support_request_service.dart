import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:caddymoney/core/config/supabase_config.dart';
import 'package:caddymoney/core/enums/support_request_status.dart';
import 'package:caddymoney/core/enums/support_requester_type.dart';
import 'package:caddymoney/models/support_request_model.dart';
import 'package:caddymoney/services/merchant_service.dart';

class SupportRequestService {
  static const String _table = 'support_requests';

  static final Map<String, String> _requesterNameCache = <String, String>{};
  final _merchantService = MerchantService();

  String _generateTicketNumber() {
    // Friendly, non-sequential-ish reference the user can copy.
    // Example: SUP-8F3K9Q
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    final r = Random.secure();
    final code = List.generate(6, (_) => chars[r.nextInt(chars.length)]).join();
    return 'SUP-$code';
  }

  Future<({SupportRequestModel? request, String? error})> createSupportRequest({
    required SupportRequesterType requesterType,
    required String subject,
    required String description,
  }) async {
    try {
      final uid = SupabaseConfig.auth.currentUser?.id;
      if (uid == null) return (request: null, error: 'You must be signed in to contact support.');

      final ticket = _generateTicketNumber();
      final payload = {
        'ticket_number': ticket,
        'requester_type': requesterType.toJson(),
        'requester_profile_id': uid,
        'subject': subject.trim(),
        'description': description.trim(),
        'status': SupportRequestStatus.newRequest.toJson(),
      };

      final rows = await SupabaseService.insert(_table, payload);
      if (rows.isEmpty) return (request: null, error: 'Support request could not be created.');

      return (request: SupportRequestModel.fromJson(rows.first), error: null);
    } catch (e) {
      debugPrint('SupportRequestService.createSupportRequest failed: $e');
      return (request: null, error: 'Failed to submit support request. Please try again.');
    }
  }

  Future<({List<SupportRequestModel> requests, String? error})> listAllRequestsForAdmin({int limit = 200}) async {
    try {
      final rows = await SupabaseService.select(
        _table,
        orderBy: 'created_at',
        ascending: false,
        limit: limit,
      );
      final items = rows.map(SupportRequestModel.fromJson).toList();
      final hydrated = await _hydrateRequesterDisplayNames(items);
      return (requests: hydrated, error: null);
    } catch (e) {
      debugPrint('SupportRequestService.listAllRequestsForAdmin failed: $e');
      return (requests: const <SupportRequestModel>[], error: 'Failed to load support requests.');
    }
  }

  Future<List<SupportRequestModel>> _hydrateRequesterDisplayNames(List<SupportRequestModel> items) async {
    try {
      final userIds = <String>{};
      final merchantProfileIds = <String>{};
      for (final r in items) {
        final id = r.requesterProfileId.trim();
        if (id.isEmpty) continue;
        final key = '${r.requesterType.toJson()}:$id';
        if (_requesterNameCache.containsKey(key)) continue;
        if (r.requesterType == SupportRequesterType.user) userIds.add(id);
        if (r.requesterType == SupportRequesterType.merchant) merchantProfileIds.add(id);
      }

      if (userIds.isNotEmpty) {
        try {
          final dynamic res = await SupabaseService.from('profiles')
              .select('id, first_name, last_name, full_name')
              .inFilter('id', userIds.toList(growable: false));
          final rows = (res is List) ? res : const <dynamic>[];
          for (final row in rows) {
            if (row is! Map) continue;
            final id = row['id']?.toString();
            if (id == null || id.trim().isEmpty) continue;
            final first = row['first_name']?.toString().trim();
            final last = row['last_name']?.toString().trim();
            final fullName = row['full_name']?.toString().trim();
            final display = [first, last].where((e) => (e ?? '').trim().isNotEmpty).join(' ').trim();
            final best = display.isNotEmpty ? display : (fullName ?? '').trim();
            if (best.isNotEmpty) _requesterNameCache['${SupportRequesterType.user.toJson()}:$id'] = best;
          }
        } catch (e) {
          debugPrint('SupportRequestService: failed to hydrate user requester names: $e');
        }
      }

      if (merchantProfileIds.isNotEmpty) {
        // We already have a robust fallback resolver in MerchantService that
        // handles `id` vs `profile_id` schemas and caches results.
        await Future.wait(
          merchantProfileIds.map((id) async {
            final name = await _merchantService.getBusinessNameByMerchantId(id);
            if (name != null && name.trim().isNotEmpty) {
              _requesterNameCache['${SupportRequesterType.merchant.toJson()}:$id'] = name.trim();
            }
          }),
        );
      }
    } catch (e) {
      debugPrint('SupportRequestService._hydrateRequesterDisplayNames failed: $e');
    }

    return items
        .map((r) {
          final key = '${r.requesterType.toJson()}:${r.requesterProfileId.trim()}';
          final name = _requesterNameCache[key];
          if (name == null || name.trim().isEmpty) return r;
          return r.copyWith(requesterDisplayName: name.trim());
        })
        .toList(growable: false);
  }

  Future<({List<SupportRequestModel> requests, String? error})> listMyRequests({int limit = 50, SupportRequesterType? requesterType}) async {
    try {
      final uid = SupabaseConfig.auth.currentUser?.id;
      if (uid == null) return (requests: const <SupportRequestModel>[], error: 'Not signed in.');

      final filters = <String, dynamic>{'requester_profile_id': uid};
      if (requesterType != null) filters['requester_type'] = requesterType.toJson();

      final rows = await SupabaseService.select(
        _table,
        filters: filters,
        orderBy: 'created_at',
        ascending: false,
        limit: limit,
      );
      final items = rows.map(SupportRequestModel.fromJson).toList();
      return (requests: items, error: null);
    } catch (e) {
      debugPrint('SupportRequestService.listMyRequests failed: $e');
      return (requests: const <SupportRequestModel>[], error: 'Failed to load your support requests.');
    }
  }

  Future<({SupportRequestModel? request, String? error})> getRequestById(String id) async {
    try {
      final row = await SupabaseService.selectSingle(_table, filters: {'id': id});
      if (row == null) return (request: null, error: 'Support request not found.');
      final r = SupportRequestModel.fromJson(row);
      final hydrated = await _hydrateRequesterDisplayNames([r]);
      return (request: hydrated.isEmpty ? r : hydrated.first, error: null);
    } catch (e) {
      debugPrint('SupportRequestService.getRequestById failed: $e');
      return (request: null, error: 'Failed to load support request.');
    }
  }

  Future<({SupportRequestModel? request, String? error})> updateStatus({
    required String requestId,
    required SupportRequestStatus status,
  }) async {
    try {
      final rows = await SupabaseService.update(
        _table,
        {
          'status': status.toJson(),
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        },
        filters: {'id': requestId},
      );
      if (rows.isEmpty) return (request: null, error: 'Support request could not be updated.');
      return (request: SupportRequestModel.fromJson(rows.first), error: null);
    } catch (e) {
      debugPrint('SupportRequestService.updateStatus failed: $e');
      return (request: null, error: 'Failed to update status.');
    }
  }

  Future<({SupportRequestModel? request, String? error})> respondToRequest({
    required String requestId,
    required String response,
  }) async {
    try {
      final trimmed = response.trim();
      if (trimmed.isEmpty) return (request: null, error: 'Response cannot be empty.');

      final rows = await SupabaseService.update(
        _table,
        {
          'admin_response': trimmed,
          'responded_at': DateTime.now().toUtc().toIso8601String(),
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        },
        filters: {'id': requestId},
      );
      if (rows.isEmpty) return (request: null, error: 'Support request could not be updated.');
      return (request: SupportRequestModel.fromJson(rows.first), error: null);
    } catch (e) {
      debugPrint('SupportRequestService.respondToRequest failed: $e');
      return (request: null, error: 'Failed to send response.');
    }
  }

  Future<void> markRequesterSeen(String requestId) async {
    try {
      final uid = SupabaseConfig.auth.currentUser?.id;
      if (uid == null) return;

      // Include requester_profile_id in the filter to satisfy common RLS policies.
      await SupabaseService.update(
        _table,
        {
          'requester_seen_at': DateTime.now().toUtc().toIso8601String(),
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        },
        filters: {'id': requestId, 'requester_profile_id': uid},
      );
    } catch (e) {
      debugPrint('SupportRequestService.markRequesterSeen failed: $e');
    }
  }

  /// Marks all support requests as seen for the current requester where an
  /// admin response exists.
  ///
  /// This prevents the notification dot from re-appearing on reconnect if the
  /// user already opened the inbox.
  Future<void> markAllMyAdminResponsesSeen({required SupportRequesterType requesterType}) async {
    try {
      final uid = SupabaseConfig.auth.currentUser?.id;
      if (uid == null) return;

      // NOTE:
      // We previously relied on PostgREST `not/is null` filters directly in the
      // update query. Depending on the Supabase SDK version + column type, this
      // can be surprisingly brittle and result in *zero rows updated* even
      // though unread rows exist.
      //
      // To make this rock-solid, we:
      // 1) Select candidate rows (same criteria as the badge counter).
      // 2) Update by explicit ids.
      final rows = await SupabaseService.select(
        _table,
        select: 'id, admin_response, responded_at, requester_seen_at',
        filters: {
          'requester_profile_id': uid,
          'requester_type': requesterType.toJson(),
        },
        orderBy: 'updated_at',
        ascending: false,
        limit: 200,
      );

      final idsToMark = <String>[];
      for (final r in rows) {
        final id = r['id']?.toString();
        if (id == null || id.trim().isEmpty) continue;
        final hasResponse = r['admin_response'] != null && r['admin_response'].toString().trim().isNotEmpty;
        final hasRespondedAt = r['responded_at'] != null && r['responded_at'].toString().trim().isNotEmpty;
        final isSeen = r['requester_seen_at'] != null && r['requester_seen_at'].toString().trim().isNotEmpty;
        if ((hasResponse || hasRespondedAt) && !isSeen) idsToMark.add(id);
      }

      if (idsToMark.isEmpty) return;

      final now = DateTime.now().toUtc().toIso8601String();
      final dynamic updated = await SupabaseConfig.client
          .from(_table)
          .update({'requester_seen_at': now, 'updated_at': now})
          .eq('requester_profile_id', uid)
          .eq('requester_type', requesterType.toJson())
          .inFilter('id', idsToMark)
          .select('id');

      final updatedCount = (updated is List) ? updated.length : 0;
      debugPrint('SupportRequestService.markAllMyAdminResponsesSeen: marked $updatedCount rows seen (candidate=${idsToMark.length}).');
    } catch (e) {
      debugPrint('SupportRequestService.markAllMyAdminResponsesSeen failed: $e');
    }
  }

  Future<int> countUnreadAdminResponses({
    SupportRequesterType? requesterType,
    int limit = 200,
  }) async {
    try {
      final uid = SupabaseConfig.auth.currentUser?.id;
      if (uid == null) return 0;

      // Use the shared helper to avoid subtle type differences between
      // Postgrest builders (some `select()` signatures return a TransformBuilder
      // that doesn't support `.eq()` chaining in newer SDK versions).
      final filters = <String, dynamic>{'requester_profile_id': uid};
      if (requesterType != null) filters['requester_type'] = requesterType.toJson();

      final rows = await SupabaseService.select(
        _table,
        select: 'admin_response, requester_seen_at',
        filters: filters,
        orderBy: 'updated_at',
        ascending: false,
        limit: limit,
      );
      var unread = 0;
      for (final r in rows) {
        if (r is! Map) continue;
        final hasResponse = r['admin_response'] != null && r['admin_response'].toString().trim().isNotEmpty;
        final isSeen = r['requester_seen_at'] != null && r['requester_seen_at'].toString().trim().isNotEmpty;
        if (hasResponse && !isSeen) unread++;
      }
      return unread;
    } catch (e) {
      debugPrint('SupportRequestService.countUnreadAdminResponses failed: $e');
      return 0;
    }
  }

  /// Count support requests that are still "new" (i.e. not triaged yet).
  ///
  /// Used to show an admin red-dot notification on the bell.
  Future<int> countNewRequestsForAdmin({int limit = 200}) async {
    try {
      final dynamic result = await SupabaseService.from(_table)
          .select('id, status')
          .eq('status', SupportRequestStatus.newRequest.toJson())
          .order('created_at', ascending: false)
          .limit(limit);
      final rows = (result is List) ? result : const <dynamic>[];
      return rows.length;
    } catch (e) {
      debugPrint('SupportRequestService.countNewRequestsForAdmin failed: $e');
      return 0;
    }
  }
}
