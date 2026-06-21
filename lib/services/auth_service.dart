import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:caddymoney/models/user_model.dart';
import 'package:caddymoney/core/enums/app_role.dart';
import 'package:caddymoney/core/config/supabase_config.dart';

class AuthService {
  SupabaseClient get _supabase => SupabaseConfig.client;

  User? get currentUser => _supabase.auth.currentUser;
  
  Stream<AuthState> get authStateChanges => _supabase.auth.onAuthStateChange;

  Future<UserModel?> getCurrentUserProfile() async {
    try {
      final user = currentUser;
      if (user == null) return null;

      final response = await SupabaseService.selectSingle(
        'profiles',
        filters: {'id': user.id},
      );
      if (response == null) return null;
      return UserModel.fromJson(response);
    } catch (e) {
      debugPrint('Error fetching user profile: $e');
      return null;
    }
  }

  Future<Map<String, dynamic>> signInWithEmail({
    required String email,
    required String password,
  }) async {
    try {
      final cleanedEmail = _cleanEmail(email);
      final cleanedPassword = _cleanPassword(password);
      final response = await _supabase.auth.signInWithPassword(
        email: cleanedEmail,
        password: cleanedPassword,
      );

      if (response.user == null) {
        return {'success': false, 'error': 'Sign in failed'};
      }

      final profile = await getCurrentUserProfile();
      if (profile == null) {
        // This usually means the profile trigger failed or RLS prevents reads.
        // Treat it as a failure because the app relies on profile + role.
        return {
          'success': false,
          'error': 'Profile not found. Please contact support or try again.',
        };
      }
      return {'success': true, 'profile': profile};
    } on AuthException catch (e) {
      debugPrint('Auth error: ${e.message}');
      return {
        'success': false,
        'error': e.message,
        'code': e.statusCode,
        'isEmailNotConfirmed': _looksLikeEmailNotConfirmed(e.message),
      };
    } catch (e) {
      debugPrint('Sign in error: $e');
      return {'success': false, 'error': 'An error occurred during sign in'};
    }
  }

  Future<Map<String, dynamic>> signUpUser({
    required String email,
    required String password,
    required String firstName,
    required String lastName,
    String? phone,
  }) async {
    try {
      final cleanedEmail = _cleanEmail(email);
      final cleanedPassword = _cleanPassword(password);
      final fullName = '${firstName.trim()} ${lastName.trim()}'.trim();
      final response = await _supabase.auth.signUp(
        email: cleanedEmail,
        password: cleanedPassword,
        data: {
          'full_name': fullName,
          'first_name': firstName.trim(),
          'last_name': lastName.trim(),
          'phone': phone,
          'role': AppRole.standardUser.toJson(),
        },
      );

      if (response.user == null) {
        return {'success': false, 'error': 'Sign up failed'};
      }

      // If email confirmations are enabled in Supabase Auth,
      // signUp returns a user but no active session until the user confirms.
      final needsEmailConfirmation = response.session == null;
      return {
        'success': true,
        'user': response.user,
        'needsEmailConfirmation': needsEmailConfirmation,
        'email': cleanedEmail,
      };
    } on AuthException catch (e) {
      debugPrint('Auth error: ${e.message}');
      return {'success': false, 'error': e.message};
    } catch (e) {
      debugPrint('Sign up error: $e');
      return {'success': false, 'error': 'An error occurred during sign up'};
    }
  }

  Future<Map<String, dynamic>> signUpMerchant({
    required String email,
    required String password,
    required String businessName,
    required String firstName,
    required String lastName,
    required String phone,
    required String addressLine1,
    String? addressLine2,
    required String city,
    required String postalCode,
    required String countryName,
    required List<String> categories,
  }) async {
    try {
      final cleanedEmail = _cleanEmail(email);
      final cleanedPassword = _cleanPassword(password);
      final authResponse = await _supabase.auth.signUp(
        email: cleanedEmail,
        password: cleanedPassword,
        data: {
          'full_name': '$firstName $lastName'.trim(),
          'first_name': firstName,
          'last_name': lastName,
          'phone': phone,
          'role': AppRole.merchant.toJson(),
        },
      );

      if (authResponse.user == null) {
        return {'success': false, 'error': 'Merchant registration failed'};
      }

      final merchantData = {
        'profile_id': authResponse.user!.id,
        'business_name': businessName,
        'owner_first_name': firstName,
        'owner_last_name': lastName,
        'business_email': cleanedEmail,
        'business_phone': phone,
        'categories': categories,
        'address_line1': addressLine1,
        'address_line2': addressLine2,
        'city': city,
        'postal_code': postalCode,
        'country_name': countryName,
        'status': 'pending',
        'profile_completed': false,
      };

      // IMPORTANT: When email confirmations are enabled in Supabase Auth,
      // signUp() returns `session == null` until the user confirms.
      // That means client-side inserts into RLS-protected tables often fail.
      // We create the pending merchant row server-side via an Edge Function.
      try {
        final res = await _supabase.functions.invoke(
          'merchant_create_pending',
          body: merchantData,
        );

        final data = res.data;
        if (data is Map && data['success'] == true) {
          // ok
        } else if (data is Map && data['error'] != null) {
          debugPrint('merchant_create_pending returned error: ${data['error']}');
        } else {
          debugPrint('merchant_create_pending returned unexpected payload: $data');
        }
      } on FunctionException catch (e) {
        // Non-fatal: the auth user may still have been created successfully.
        debugPrint('merchant_create_pending function error: ${e.toString()}');
      } catch (e) {
        debugPrint('merchant_create_pending unknown error: $e');
      }

      final needsEmailConfirmation = authResponse.session == null;
      return {
        'success': true,
        'user': authResponse.user,
        'needsEmailConfirmation': needsEmailConfirmation,
        'email': cleanedEmail,
      };
    } on AuthException catch (e) {
      debugPrint('Auth error: ${e.message}');
      return {'success': false, 'error': e.message};
    } catch (e) {
      debugPrint('Merchant registration error: $e');
      return {'success': false, 'error': 'An error occurred during registration'};
    }
  }

  Future<Map<String, dynamic>> resendSignupConfirmationEmail(String email) async {
    try {
      final cleanedEmail = _cleanEmail(email);
      await _supabase.auth.resend(type: OtpType.signup, email: cleanedEmail);
      return {'success': true};
    } on AuthException catch (e) {
      debugPrint('Resend confirmation auth error: ${e.message}');
      return {'success': false, 'error': _mapAuthException(e.message)};
    } catch (e) {
      debugPrint('Resend confirmation error: $e');
      return {'success': false, 'error': 'Failed to resend confirmation email'};
    }
  }

  String _mapAuthException(String message) {
    final m = message.toLowerCase();
    if (m.contains('rate limit') || m.contains('too many requests')) {
      return 'Too many attempts. Please wait a bit and try again.';
    }
    return message;
  }

  String _cleanEmail(String input) => input.trim().toLowerCase().replaceAll(RegExp(r'\s+'), '');

  String _cleanPassword(String input) => input.trim();

  Future<void> signOut() async {
    try {
      await _supabase.auth.signOut();
    } catch (e) {
      debugPrint('Sign out error: $e');
      rethrow;
    }
  }

  Future<bool> resetPassword(String email) async {
    try {
      await _supabase.auth.resetPasswordForEmail(email);
      return true;
    } catch (e) {
      debugPrint('Password reset error: $e');
      return false;
    }
  }

  bool _looksLikeEmailNotConfirmed(String message) {
    final m = message.toLowerCase();
    return m.contains('email not confirmed') ||
        m.contains('email address not confirmed') ||
        m.contains('not confirmed');
  }

  Future<Map<String, dynamic>> createAdminFromBootstrap({
    required String email,
    required String password,
    required String fullName,
    required String bootstrapToken,
  }) async {
    try {
      final cleanedEmail = _cleanEmail(email);
      final cleanedPassword = _cleanPassword(password);
      final cleanedName = fullName.trim();

      final res = await _supabase.functions.invoke(
        'admin_create_admin',
        body: {
          'email': cleanedEmail,
          'password': cleanedPassword,
          'full_name': cleanedName,
          'bootstrap_token': bootstrapToken.trim(),
        },
      );

      final data = res.data;
      if (data is Map) {
        final success = data['success'] == true;
        if (success) return {'success': true, 'userId': data['user_id']};
        return {
          'success': false,
          'error': (data['error'] ?? 'Failed to create admin').toString(),
        };
      }

      // Some errors can surface as non-map payloads.
      return {'success': false, 'error': 'Failed to create admin'};
    } on FunctionException catch (e) {
      debugPrint('Create admin function error: ${e.toString()}');
      return {'success': false, 'error': e.toString()};
    } catch (e) {
      debugPrint('Create admin error: $e');
      return {'success': false, 'error': 'An error occurred while creating the admin'};
    }
  }
}
