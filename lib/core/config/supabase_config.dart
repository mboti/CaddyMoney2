import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Canonical Supabase configuration for the app.
///
/// IMPORTANT: Do NOT change `supabaseUrl` or `anonKey` here. These are generated
/// for your connected Supabase project.
class SupabaseConfig {
  static const String supabaseUrl = 'https://fuaqlnmulvxzkwzoeqwg.supabase.co';
  static const String anonKey =
      'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImZ1YXFsbm11bHZ4emt3em9lcXdnIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzM2MDU3MjUsImV4cCI6MjA4OTE4MTcyNX0.-hsEjCu0XmSq1J90ZCmpYVGk2Om3GZWgfB69bFCkaMY';

  static Future<void> initialize() async {
    await Supabase.initialize(url: supabaseUrl, anonKey: anonKey, debug: kDebugMode);
  }

  static SupabaseClient get client => Supabase.instance.client;
  static GoTrueClient get auth => client.auth;
}

/// Generic database service for CRUD operations.
class SupabaseService {
  static Exception _dbException(String operation, String table, Object error) {
    final message = error is PostgrestException
        ? 'Supabase $operation failed for "$table": ${error.message}'
        : 'Supabase $operation failed for "$table": $error';
    debugPrint(message);
    return Exception(message);
  }

  /// Select multiple records from a table.
  static Future<List<Map<String, dynamic>>> select(
    String table, {
    String? select,
    Map<String, dynamic>? filters,
    String? orderBy,
    bool ascending = true,
    int? limit,
  }) async {
    try {
      dynamic query = SupabaseConfig.client.from(table).select(select ?? '*');

      if (filters != null) {
        for (final entry in filters.entries) {
          query = query.eq(entry.key, entry.value);
        }
      }

      if (orderBy != null) {
        query = query.order(orderBy, ascending: ascending);
      }

      if (limit != null) {
        query = query.limit(limit);
      }

      return await query;
    } catch (e) {
      throw _dbException('select', table, e);
    }
  }

  /// Select a single record from a table.
  static Future<Map<String, dynamic>?> selectSingle(
    String table, {
    String? select,
    required Map<String, dynamic> filters,
  }) async {
    try {
      dynamic query = SupabaseConfig.client.from(table).select(select ?? '*');

      for (final entry in filters.entries) {
        query = query.eq(entry.key, entry.value);
      }

      return await query.maybeSingle();
    } catch (e) {
      throw _dbException('selectSingle', table, e);
    }
  }

  /// Insert a record into a table.
  static Future<List<Map<String, dynamic>>> insert(String table, Map<String, dynamic> data) async {
    try {
      return await SupabaseConfig.client.from(table).insert(data).select();
    } catch (e) {
      throw _dbException('insert', table, e);
    }
  }

  /// Insert multiple records into a table.
  static Future<List<Map<String, dynamic>>> insertMultiple(
    String table,
    List<Map<String, dynamic>> data,
  ) async {
    try {
      return await SupabaseConfig.client.from(table).insert(data).select();
    } catch (e) {
      throw _dbException('insertMultiple', table, e);
    }
  }

  /// Update records in a table.
  static Future<List<Map<String, dynamic>>> update(
    String table,
    Map<String, dynamic> data, {
    required Map<String, dynamic> filters,
  }) async {
    try {
      dynamic query = SupabaseConfig.client.from(table).update(data);

      for (final entry in filters.entries) {
        query = query.eq(entry.key, entry.value);
      }

      return await query.select();
    } catch (e) {
      throw _dbException('update', table, e);
    }
  }

  /// Delete records from a table.
  static Future<void> delete(String table, {required Map<String, dynamic> filters}) async {
    try {
      dynamic query = SupabaseConfig.client.from(table).delete();

      for (final entry in filters.entries) {
        query = query.eq(entry.key, entry.value);
      }

      await query;
    } catch (e) {
      throw _dbException('delete', table, e);
    }
  }

  /// Call an RPC function.
  ///
  /// Returns the decoded JSON response (if any).
  static Future<dynamic> rpc(String functionName, {Map<String, dynamic>? params}) async {
    try {
      return await SupabaseConfig.client.rpc(functionName, params: params);
    } catch (e) {
      debugPrint('Supabase rpc failed for "$functionName": $e');
      rethrow;
    }
  }

  /// Get direct table reference for complex queries.
  static SupabaseQueryBuilder from(String table) => SupabaseConfig.client.from(table);
}
