import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:caddymoney/models/user_model.dart';
import 'package:caddymoney/services/auth_service.dart';
import 'package:caddymoney/core/enums/app_role.dart';
import 'package:caddymoney/models/merchant_model.dart';
import 'package:caddymoney/services/merchant_service.dart';
import 'package:caddymoney/core/enums/merchant_status.dart';
import 'package:caddymoney/core/utils/router_refresh.dart';

class AuthProvider with ChangeNotifier {
  final AuthService _authService = AuthService();
  final MerchantService _merchantService = MerchantService();
  
  UserModel? _currentUser;
  MerchantModel? _currentMerchant;
  bool _isLoading = false;
  String? _error;

  UserModel? get currentUser => _currentUser;
  MerchantModel? get currentMerchant => _currentMerchant;
  bool get isLoading => _isLoading;
  String? get error => _error;
  bool get isAuthenticated => _currentUser != null;
  AppRole? get userRole => _currentUser?.role;

  /// Full access means: Step 2 completed + admin verified.
  bool get merchantHasFullAccess {
    if (userRole != AppRole.merchant) return true;
    final m = _currentMerchant;
    if (m == null) return false;
    return m.profileCompleted == true && m.status == MerchantStatus.approved;
  }

  AuthProvider() {
    _init();
  }

  Future<void> _init() async {
    _authService.authStateChanges.listen((AuthState state) {
      if (state.event == AuthChangeEvent.signedIn) {
        _loadCurrentUser();
      } else if (state.event == AuthChangeEvent.signedOut) {
        _currentUser = null;
        notifyListeners();
      }
    });

    await _loadCurrentUser();
  }

  Future<void> _loadCurrentUser() async {
    try {
      _currentUser = await _authService.getCurrentUserProfile();
      if (_currentUser?.role == AppRole.merchant) {
        _currentMerchant = await _merchantService.getMyMerchant();
      } else {
        _currentMerchant = null;
      }
      notifyListeners();
      RouterRefresh.instance.ping();
    } catch (e) {
      debugPrint('Error loading current user: $e');
    }
  }

  Future<void> refreshMerchant() async {
    if (userRole != AppRole.merchant) return;
    try {
      _currentMerchant = await _merchantService.getMyMerchant();
      notifyListeners();
      RouterRefresh.instance.ping();
    } catch (e) {
      debugPrint('AuthProvider.refreshMerchant failed: $e');
    }
  }

  Future<bool> signIn(String email, String password) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    final result = await _authService.signInWithEmail(
      email: email,
      password: password,
    );

    if (result['success'] == true) {
      try {
        // Ensure we load both profile + merchant (if applicable) immediately,
        // so go_router redirects can rely on up-to-date status.
        await _loadCurrentUser();
      } catch (e) {
        debugPrint('AuthProvider.signIn post-load failed: $e');
        // Fall back to whatever AuthService returned.
        _currentUser = result['profile'];
        notifyListeners();
      } finally {
        _isLoading = false;
        notifyListeners();
      }
      return true;
    }

    _isLoading = false;
    _error = result['error'];
    notifyListeners();
    return false;
  }

  Future<bool> signInForRole({
    required String email,
    required String password,
    required AppRole requiredRole,
  }) async {
    final ok = await signIn(email, password);
    if (!ok) return false;

    final role = _currentUser?.role;
    if (role == requiredRole) return true;

    _error = 'Unauthorized for ${requiredRole.displayName}. Your account role is: ${role?.displayName ?? 'unknown'}';
    try {
      await _authService.signOut();
    } catch (e) {
      debugPrint('Failed to sign out after unauthorized role login: $e');
    }
    _currentUser = null;
    notifyListeners();
    return false;
  }

  Future<bool> resetPassword(String email) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    final ok = await _authService.resetPassword(email);
    _isLoading = false;
    if (!ok) _error = 'Failed to send reset email';
    notifyListeners();
    return ok;
  }

  Future<bool> signUpUser({
    required String email,
    required String password,
    required String firstName,
    required String lastName,
    String? phone,
  }) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    final result = await _authService.signUpUser(
      email: email,
      password: password,
      firstName: firstName,
      lastName: lastName,
      phone: phone,
    );

    _isLoading = false;

    if (result['success'] == true) {
      // If email confirmations are enabled, the user must confirm before a session exists.
      if (result['needsEmailConfirmation'] == true) {
        _error = 'Email not confirmed';
        notifyListeners();
        return false;
      }

      await _loadCurrentUser();
      notifyListeners();
      return true;
    } else {
      _error = result['error'];
      notifyListeners();
      return false;
    }
  }

  Future<bool> signUpMerchant({
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
    _isLoading = true;
    _error = null;
    notifyListeners();

    final result = await _authService.signUpMerchant(
      email: email,
      password: password,
      businessName: businessName,
      firstName: firstName,
      lastName: lastName,
      phone: phone,
      addressLine1: addressLine1,
      addressLine2: addressLine2,
      city: city,
      postalCode: postalCode,
      countryName: countryName,
      categories: categories,
    );

    _isLoading = false;

    if (result['success'] == true) {
      if (result['needsEmailConfirmation'] == true) {
        _error = 'Email not confirmed';
        notifyListeners();
        return false;
      }

      await _loadCurrentUser();
      notifyListeners();
      return true;
    } else {
      _error = result['error'];
      notifyListeners();
      return false;
    }
  }

  Future<bool> resendSignupConfirmationEmail(String email) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    final res = await _authService.resendSignupConfirmationEmail(email);
    _isLoading = false;
    final ok = res['success'] == true;
    if (!ok) _error = (res['error'] ?? 'Failed to resend confirmation email').toString();
    notifyListeners();
    return ok;
  }

  Future<void> signOut() async {
    await _authService.signOut();
    _currentUser = null;
    _currentMerchant = null;
    notifyListeners();
    RouterRefresh.instance.ping();
  }

  Future<bool> createAdminFromBootstrap({
    required String email,
    required String password,
    required String fullName,
    required String bootstrapToken,
  }) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    final result = await _authService.createAdminFromBootstrap(
      email: email,
      password: password,
      fullName: fullName,
      bootstrapToken: bootstrapToken,
    );

    _isLoading = false;
    if (result['success'] == true) {
      notifyListeners();
      return true;
    }

    _error = (result['error'] ?? 'Failed to create admin').toString();
    notifyListeners();
    return false;
  }

  void clearError() {
    _error = null;
    notifyListeners();
  }
}
