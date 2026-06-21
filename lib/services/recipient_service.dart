import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:caddymoney/models/saved_recipient_model.dart';
import 'package:caddymoney/core/config/supabase_config.dart';

class AddRecipientResult {
  final bool success;
  final String? message;
  final SavedRecipientModel? recipient;

  const AddRecipientResult({required this.success, this.message, this.recipient});
}

class RemoveRecipientResult {
  final bool success;
  final String? message;

  const RemoveRecipientResult({required this.success, this.message});
}

class RecipientService {
  String _cleanEmail(String input) => input.trim().toLowerCase().replaceAll(RegExp(r'\s+'), '');
  String _cleanIdentifier(String input) => input.trim().replaceAll(RegExp(r'\s+'), ' ');

  bool _looksLikeEmail(String input) {
    final v = input.trim();
    return v.contains('@') && v.contains('.') && !v.contains(' ');
  }

  Future<List<SavedRecipientModel>> listMyRecipients({int limit = 50}) async {
    try {
      final uid = SupabaseConfig.auth.currentUser?.id;
      if (uid == null) return [];

      // Must use RPC because profiles RLS prevents selecting recipient profile fields.
      final rows = await SupabaseConfig.client.rpc('list_my_recipients', params: {'p_limit': limit});
      final list = (rows as List)
          .whereType<Map>()
          .map((e) {
            final m = Map<String, dynamic>.from(e);
            return SavedRecipientModel(
              ownerUserId: m['owner_user_id']?.toString() ?? uid,
              recipientUserId: m['recipient_user_id']?.toString() ?? '',
              recipientEmail: m['recipient_email']?.toString() ?? '',
              recipientFullName: m['recipient_full_name']?.toString(),
              createdAt: DateTime.tryParse(m['created_at']?.toString() ?? '') ?? DateTime.now(),
            );
          })
          .where((r) => r.recipientEmail.isNotEmpty)
          .toList();
      return list;
    } catch (e) {
      debugPrint('RecipientService.listMyRecipients failed: $e');
      return [];
    }
  }

  Future<AddRecipientResult> addRecipientByEmail(String email) async {
    final uid = SupabaseConfig.auth.currentUser?.id;
    if (uid == null) return const AddRecipientResult(success: false, message: 'Not signed in');

    final identifier = _cleanIdentifier(email);
    if (identifier.isEmpty) return const AddRecipientResult(success: false, message: 'Enter a name or email');

    try {

      // Must use RPC because profiles RLS prevents looking up other users directly.
      final matches = await SupabaseConfig.client.rpc(
        'find_active_profiles',
        params: {'p_identifier': _looksLikeEmail(identifier) ? _cleanEmail(identifier) : identifier, 'p_limit': 10},
      );
      final list = (matches as List).whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
      if (list.isEmpty) return const AddRecipientResult(success: false, message: 'No matching user found.');

      final Map<String, dynamic> chosen;
      if (_looksLikeEmail(identifier)) {
        final cleaned = _cleanEmail(identifier);
        chosen = list.firstWhere(
          (m) => (m['email']?.toString().toLowerCase() ?? '') == cleaned,
          orElse: () => <String, dynamic>{},
        );
        if (chosen.isEmpty) return const AddRecipientResult(success: false, message: 'No matching user found.');
      } else {
        if (list.length > 1) {
          return AddRecipientResult(
            success: false,
            message:
                'Multiple users match that name. Please enter their email instead. (Examples: ${list.take(3).map((m) => m['email']).whereType<String>().join(', ')})',
          );
        }
        chosen = list.first;
      }

      final recipientUserId = chosen['id']?.toString() ?? '';
      final recipientEmail = chosen['email']?.toString() ?? '';
      final recipientFullName = chosen['full_name']?.toString();
      if (recipientUserId.isEmpty || recipientEmail.isEmpty) return const AddRecipientResult(success: false, message: 'No matching user found.');

      if (recipientUserId == uid) {
        return const AddRecipientResult(success: false, message: 'You cannot add yourself.');
      }

      // Prevent duplicates: rely on DB unique constraint, but also check client-side for a nicer message.
      final existing = await SupabaseConfig.client
          .from('user_recipients')
          .select('owner_user_id, recipient_user_id')
          .eq('owner_user_id', uid)
          .eq('recipient_user_id', recipientUserId)
          .maybeSingle();
      if (existing != null && existing.isNotEmpty) {
        return const AddRecipientResult(success: false, message: 'Recipient already added.');
      }

      final inserted = await SupabaseConfig.client
          .from('user_recipients')
          .insert({'owner_user_id': uid, 'recipient_user_id': recipientUserId})
          .select();

      final row = inserted.isNotEmpty ? inserted.first : <String, dynamic>{};

      final model = SavedRecipientModel(
        ownerUserId: uid,
        recipientUserId: recipientUserId,
        recipientEmail: recipientEmail,
        recipientFullName: recipientFullName,
        createdAt: DateTime.tryParse(row['created_at']?.toString() ?? '') ?? DateTime.now(),
      );

      return AddRecipientResult(success: true, message: 'Recipient added.', recipient: model);
    } on PostgrestException catch (e) {
      debugPrint('RecipientService.addRecipientByEmail PostgrestException: ${e.message}');
      if (e.code == '23505') {
        return const AddRecipientResult(success: false, message: 'Recipient already added.');
      }
      return AddRecipientResult(success: false, message: e.message);
    } catch (e) {
      debugPrint('RecipientService.addRecipientByEmail failed: $e');
      return const AddRecipientResult(success: false, message: 'Failed to add recipient');
    }
  }

  Future<RemoveRecipientResult> removeRecipient({required String recipientUserId}) async {
    final uid = SupabaseConfig.auth.currentUser?.id;
    if (uid == null) return const RemoveRecipientResult(success: false, message: 'Not signed in');
    if (recipientUserId.trim().isEmpty) {
      return const RemoveRecipientResult(success: false, message: 'Missing recipient');
    }

    try {
      await SupabaseConfig.client
          .from('user_recipients')
          .delete()
          .eq('owner_user_id', uid)
          .eq('recipient_user_id', recipientUserId);
      return const RemoveRecipientResult(success: true, message: 'Recipient removed.');
    } on PostgrestException catch (e) {
      debugPrint('RecipientService.removeRecipient PostgrestException: ${e.message}');
      return RemoveRecipientResult(success: false, message: e.message);
    } catch (e) {
      debugPrint('RecipientService.removeRecipient failed: $e');
      return const RemoveRecipientResult(success: false, message: 'Failed to remove recipient');
    }
  }
}
