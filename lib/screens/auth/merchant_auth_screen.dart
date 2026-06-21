import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:caddymoney/providers/auth_provider.dart';
import 'package:caddymoney/theme.dart';
import 'package:caddymoney/core/theme/app_colors.dart';
import 'package:caddymoney/core/constants/app_constants.dart';
import 'package:caddymoney/core/utils/app_localizations_temp.dart';
import 'package:caddymoney/core/enums/app_role.dart';
import 'package:caddymoney/widgets/caddy_money_top_app_bar.dart';

class MerchantAuthScreen extends StatefulWidget {
  const MerchantAuthScreen({super.key});

  @override
  State<MerchantAuthScreen> createState() => _MerchantAuthScreenState();
}

class _CategoryMultiSelectField extends StatelessWidget {
  final Set<String> selected;
  final ValueChanged<Set<String>> onChanged;

  const _CategoryMultiSelectField({required this.selected, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Categories', style: Theme.of(context).textTheme.labelLarge?.copyWith(color: cs.onSurfaceVariant)),
        const SizedBox(height: AppSpacing.sm),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: AppConstants.businessCategories.map((c) {
            final isSelected = selected.contains(c);
            return FilterChip(
              label: Text(c),
              selected: isSelected,
              selectedColor: cs.primaryContainer,
              checkmarkColor: cs.primary,
              onSelected: (v) {
                final next = {...selected};
                if (v) {
                  next.add(c);
                } else {
                  next.remove(c);
                }
                onChanged(next);
              },
            );
          }).toList(),
        ),
        if (selected.isEmpty)
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.sm),
            child: Text(
              'Select at least one category',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: cs.error),
            ),
          ),
      ],
    );
  }
}

class _MerchantAuthScreenState extends State<MerchantAuthScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _businessNameController = TextEditingController();
  final _firstNameController = TextEditingController();
  final _lastNameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _addressLine1Controller = TextEditingController();
  final _addressLine2Controller = TextEditingController();
  final _postalCodeController = TextEditingController();
  final _cityController = TextEditingController();
  final _cityFocusNode = FocusNode();
  final _confirmPasswordController = TextEditingController();
  Timer? _postalDebounce;
  String? _selectedCountry;
  String? _selectedCity;
  List<String> _suggestedCities = const [];
  bool _isCityLookupLoading = false;
  String? _cityLookupError;
  int _cityLookupToken = 0;
  final Map<String, List<String>> _cityLookupCache = {};
  
  bool _isSignIn = true;
  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;
  final Set<String> _selectedCategories = {};

  static const _step1DraftPrefsKey = 'merchant_step1_draft_v1';

  static const List<String> _countryOptions = [
    'Morocco',
    'Algeria',
    'Tunisia',
    'Spain',
    'Italy',
    'Belgium',
    'France',
    'Germany',
    'Switzerland',
    'England',
  ];

  @override
  void initState() {
    super.initState();
    _postalCodeController.addListener(_onPostalChanged);
  }

  void _onPostalChanged() {
    // Debounce to avoid rebuilding on every keystroke.
    _postalDebounce?.cancel();
    _postalDebounce = Timer(const Duration(milliseconds: 250), () {
      if (!mounted) return;
      final country = _selectedCountry;
      final postal = _postalCodeController.text.trim();
      final iso = _countryToZippopotamCode(country);
      debugPrint('[postal-cities] postal changed (country=$country, iso=$iso, postal=$postal)');

      // If the user clears the postal code, immediately clear suggestions.
      if (postal.isEmpty) {
        setState(() {
          _isCityLookupLoading = false;
          _cityLookupError = null;
          _suggestedCities = const [];
          _selectedCity = null;
        });
        return;
      }

      // Don’t call the network until the country is selected and we have a
      // minimally useful postal code.
      if (country == null || country.trim().isEmpty) return;
      if (postal.length < 2) return;

      _refreshCitySuggestions();
    });
  }

  String? _countryToZippopotamCode(String? countryName) {
    final normalized = countryName?.trim().toLowerCase();
    if (normalized == null || normalized.isEmpty) return null;

    // Zippopotam expects ISO-3166 alpha-2 codes.
    // We accept common English/French labels to be resilient to localization.
    switch (normalized) {
      case 'france':
        return 'fr';
      case 'spain':
      case 'espagne':
        return 'es';
      case 'italy':
      case 'italie':
        return 'it';
      case 'belgium':
      case 'belgique':
        return 'be';
      case 'germany':
      case 'allemagne':
        return 'de';
      case 'switzerland':
      case 'suisse':
        return 'ch';
      case 'england':
      case 'united kingdom':
      case 'royaume-uni':
      case 'royaume uni':
      case 'uk':
        // Zippopotam uses GB for United Kingdom.
        return 'gb';
      case 'morocco':
      case 'maroc':
        return 'ma';
      case 'algeria':
      case 'algérie':
      case 'algerie':
        return 'dz';
      case 'tunisia':
      case 'tunisie':
        return 'tn';
      default:
        return null;
    }
  }

  Future<List<String>> _fetchCitiesViaSupabaseProxy({required String countryCode, required String postalCode}) async {
    try {
      // IMPORTANT: different deployments of the Edge Function may expect either
      // { country, postalCode } or { countryCode, postalCode }.
      // To be robust (and avoid silent 400s), we send BOTH keys.
      final normalizedCountry = countryCode.trim().toLowerCase();
      final normalizedPostal = postalCode.trim();

      // NOTE: For supabase_flutter, `functions.invoke(..., body: <map>)` is the
      // most reliable way to ensure the request is sent as JSON and can be read
      // by `await req.json()` in the Edge Runtime.
      final payload = <String, dynamic>{
        'country': normalizedCountry,
        'countryCode': normalizedCountry,
        'postalCode': normalizedPostal,
      };

      final session = Supabase.instance.client.auth.currentSession;
      debugPrint('[postal-cities] auth session present=${session != null}');
      debugPrint('[postal-cities] invoking edge function with payload=$payload');
      final resp = await Supabase.instance.client.functions.invoke(
        'postal-cities',
        body: payload,
        headers: const {
          // Being explicit helps avoid Edge Function rejecting non-JSON content types.
          'content-type': 'application/json',
          'accept': 'application/json',
        },
      );
      debugPrint('[postal-cities] invoke completed: status=${resp.status} data=${resp.data}');

      dynamic data = resp.data;
      // Depending on the version / platform, supabase_flutter can surface
      // response data as a Map (already decoded) or a JSON string.
      if (data is String) {
        try {
          data = jsonDecode(data);
        } catch (e) {
          debugPrint('[postal-cities] failed to jsonDecode response string: $e');
          return const [];
        }
      }

      if (data is Map) {
        final cities = data['cities'];
        if (cities is List) {
          final result = cities.whereType<String>().map((e) => e.trim()).where((e) => e.isNotEmpty).toSet().toList()..sort();
          return result;
        }
      }
      return const [];
    } catch (e) {
      // If the function has verify_jwt=true, unauthenticated users will get 401/403
      // and the Edge Function code may never run.
      debugPrint('[postal-cities] proxy exception: $e');
      return const [];
    }
  }

  Future<List<String>> _fetchCitiesOnline({required String? countryName, required String postalCode}) async {
    final code = _countryToZippopotamCode(countryName);
    if (code == null) {
      debugPrint('[postal-cities] unsupported country for lookup: countryName=$countryName');
      return const [];
    }

    final normalizedPostal = postalCode.trim();
    if (normalizedPostal.isEmpty) {
      debugPrint('[postal-cities] empty postal code; skip lookup');
      return const [];
    }

    final cacheKey = '$code|$normalizedPostal';
    final cached = _cityLookupCache[cacheKey];
    if (cached != null) return cached;

    // On web, direct calls to Zippopotam.us are often blocked by CORS.
    // Route via Supabase Edge Function proxy instead.
    if (kIsWeb) {
      debugPrint('[postal-cities] kIsWeb=true -> using Supabase edge proxy (country=$code, postalCode=$normalizedPostal)');
      final list = await _fetchCitiesViaSupabaseProxy(countryCode: code, postalCode: normalizedPostal);
      _cityLookupCache[cacheKey] = list;
      return list;
    }

    final uri = Uri.parse('https://api.zippopotam.us/$code/${Uri.encodeComponent(normalizedPostal)}');
    try {
      final resp = await http.get(uri).timeout(const Duration(seconds: 6));
      if (resp.statusCode == 404) {
        _cityLookupCache[cacheKey] = const [];
        return const [];
      }
      if (resp.statusCode < 200 || resp.statusCode >= 300) {
        debugPrint('City lookup failed: ${resp.statusCode} ${resp.reasonPhrase}');
        return const [];
      }

      final decoded = jsonDecode(utf8.decode(resp.bodyBytes));
      if (decoded is! Map<String, dynamic>) return const [];
      final places = decoded['places'];
      if (places is! List) return const [];

      final cities = <String>{};
      for (final p in places) {
        if (p is Map) {
          final name = p['place name'];
          if (name is String && name.trim().isNotEmpty) cities.add(name.trim());
        }
      }
      final list = cities.toList()..sort();
      _cityLookupCache[cacheKey] = list;
      return list;
    } catch (e) {
      debugPrint('City lookup exception: $e');
      return const [];
    }
  }

  Future<void> _refreshCitySuggestions() async {
    final country = _selectedCountry;
    final iso = _countryToZippopotamCode(country);
    final postal = _postalCodeController.text.trim();
    final token = ++_cityLookupToken;

    debugPrint('[postal-cities] _refreshCitySuggestions start (country=$country, iso=$iso, postal=$postal, token=$token)');

    if (country == null || country.trim().isEmpty || postal.isEmpty) {
      debugPrint('[postal-cities] missing country or postal; clearing suggestions');
      setState(() {
        _isCityLookupLoading = false;
        _cityLookupError = null;
        _suggestedCities = const [];
        _selectedCity = null;
      });
      return;
    }

    setState(() {
      _isCityLookupLoading = true;
      _cityLookupError = null;
      _suggestedCities = const [];
      _selectedCity = null;
    });

    var next = await _fetchCitiesOnline(countryName: country, postalCode: postal);
    if (!mounted || token != _cityLookupToken) return;

    debugPrint('[postal-cities] lookup result count=${next.length} (country=$country, postal=$postal)');

    // Fallback: if the online lookup returns nothing (or is unsupported), we
    // still provide a small offline mapping so users aren't blocked.
    if (next.isEmpty) next = _suggestCitiesFallback(countryName: country, postalCode: postal);

    setState(() {
      _isCityLookupLoading = false;
      _suggestedCities = next;
      _cityLookupError = next.isEmpty ? 'No cities found for this postal code.' : null;

      final current = _cityController.text.trim();
      if (current.isNotEmpty && _suggestedCities.contains(current)) {
        _selectedCity = current;
      } else {
        _selectedCity = null;
      }

      // Helpful autofill only when the user hasn't typed anything yet.
      if (current.isEmpty && _suggestedCities.length == 1) {
        _cityController.text = _suggestedCities.first;
        _selectedCity = _suggestedCities.first;
      }
    });
  }

  List<String> _suggestCitiesFallback({required String? countryName, required String postalCode}) {
    if (countryName == null || countryName.isEmpty) return const [];
    if (postalCode.isEmpty) return const [];

    final normalized = postalCode.replaceAll(RegExp(r'\s+'), '');
    String digitsOnly() => normalized.replaceAll(RegExp(r'[^0-9]'), '');
    String upperAlnum() => normalized.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');

    switch (countryName) {
      case 'Morocco':
        final d = digitsOnly();
        if (d.startsWith('200') || d.startsWith('201') || d.startsWith('202')) return const ['Casablanca'];
        if (d.startsWith('100') || d.startsWith('101')) return const ['Rabat'];
        if (d.startsWith('400')) return const ['Marrakech'];
        if (d.startsWith('800')) return const ['Agadir'];
        if (d.startsWith('300')) return const ['Fes'];
        if (d.startsWith('500')) return const ['Meknes'];
        if (d.startsWith('600')) return const ['Oujda'];
        if (d.startsWith('900')) return const ['Tangier'];
        if (d.startsWith('700')) return const ['Laayoune'];
        return const [];
      case 'Algeria':
        final d = digitsOnly();
        if (d.startsWith('16')) return const ['Algiers'];
        if (d.startsWith('31')) return const ['Oran'];
        if (d.startsWith('25')) return const ['Constantine'];
        if (d.startsWith('23')) return const ['Annaba'];
        if (d.startsWith('09')) return const ['Blida'];
        return const [];
      case 'Tunisia':
        final d = digitsOnly();
        if (d.startsWith('10') || d.startsWith('20')) return const ['Tunis'];
        if (d.startsWith('30')) return const ['Bizerte'];
        if (d.startsWith('40')) return const ['Sfax'];
        if (d.startsWith('50')) return const ['Sousse'];
        return const [];
      case 'France':
        final d = digitsOnly();
        if (d.startsWith('75')) return const ['Paris'];
        if (d.startsWith('13')) return const ['Marseille'];
        if (d.startsWith('69')) return const ['Lyon'];
        if (d.startsWith('31')) return const ['Toulouse'];
        if (d.startsWith('33')) return const ['Bordeaux'];
        if (d.startsWith('59')) return const ['Lille'];
        if (d.startsWith('06')) return const ['Nice'];
        if (d.startsWith('44')) return const ['Nantes'];
        if (d.startsWith('67')) return const ['Strasbourg'];
        if (d.startsWith('34')) return const ['Montpellier'];
        // Haute-Saône (70) – e.g. 70000 Vesoul and nearby communes.
        if (d.startsWith('70')) return const ['Vesoul', 'Navenne', 'Quincey'];
        return const [];
      case 'Belgium':
        final d = digitsOnly();
        if (d.startsWith('10') || d.startsWith('11')) return const ['Brussels'];
        if (d.startsWith('20')) return const ['Antwerp'];
        if (d.startsWith('90')) return const ['Ghent'];
        if (d.startsWith('40')) return const ['Liège'];
        if (d.startsWith('60')) return const ['Charleroi'];
        return const [];
      case 'Germany':
        final d = digitsOnly();
        if (d.startsWith('10')) return const ['Berlin'];
        if (d.startsWith('20')) return const ['Hamburg'];
        if (d.startsWith('60')) return const ['Frankfurt am Main'];
        if (d.startsWith('50')) return const ['Cologne'];
        if (d.startsWith('80')) return const ['Munich'];
        if (d.startsWith('70')) return const ['Stuttgart'];
        if (d.startsWith('40')) return const ['Düsseldorf'];
        return const [];
      case 'Switzerland':
        final d = digitsOnly();
        if (d.startsWith('80')) return const ['Zurich'];
        if (d.startsWith('12')) return const ['Geneva'];
        if (d.startsWith('30')) return const ['Bern'];
        if (d.startsWith('40')) return const ['Basel'];
        if (d.startsWith('10')) return const ['Lausanne'];
        return const [];
      case 'Spain':
        final d = digitsOnly();
        if (d.startsWith('28')) return const ['Madrid'];
        if (d.startsWith('08')) return const ['Barcelona'];
        if (d.startsWith('41')) return const ['Seville'];
        if (d.startsWith('46')) return const ['Valencia'];
        if (d.startsWith('48')) return const ['Bilbao'];
        if (d.startsWith('29')) return const ['Málaga'];
        return const [];
      case 'Italy':
        final d = digitsOnly();
        if (d.startsWith('00')) return const ['Rome'];
        if (d.startsWith('20')) return const ['Milan'];
        if (d.startsWith('80')) return const ['Naples'];
        if (d.startsWith('10')) return const ['Turin'];
        if (d.startsWith('50')) return const ['Florence'];
        if (d.startsWith('40')) return const ['Bologna'];
        return const [];
      case 'England':
        // UK postcodes are alphanumeric; use first 1-2 letters.
        final a = upperAlnum();
        if (a.startsWith('SW') || a.startsWith('NW') || a.startsWith('EC') || a.startsWith('WC') || a.startsWith('E') || a.startsWith('W')) return const ['London'];
        if (a.startsWith('M')) return const ['Manchester'];
        if (a.startsWith('B')) return const ['Birmingham'];
        if (a.startsWith('L')) return const ['Liverpool'];
        if (a.startsWith('LS')) return const ['Leeds'];
        if (a.startsWith('BS')) return const ['Bristol'];
        return const [];
      default:
        return const [];
    }
  }

  Future<void> _persistStep1Draft() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final draft = MerchantStep1Draft(
        businessName: _businessNameController.text.trim(),
        firstName: _firstNameController.text.trim(),
        lastName: _lastNameController.text.trim(),
        phone: _phoneController.text.trim(),
        email: _emailController.text.trim(),
        addressLine1: _addressLine1Controller.text.trim(),
        addressLine2: _addressLine2Controller.text.trim().isEmpty ? null : _addressLine2Controller.text.trim(),
        city: _cityController.text.trim(),
        postalCode: _postalCodeController.text.trim(),
        countryName: (_selectedCountry ?? '').trim(),
        categories: _selectedCategories.toList(),
      );
      await prefs.setString(_step1DraftPrefsKey, draft.encode());
    } catch (e) {
      // Non-blocking: prefill convenience only.
      debugPrint('Failed to persist merchant step1 draft: $e');
    }
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _businessNameController.dispose();
    _firstNameController.dispose();
    _lastNameController.dispose();
    _phoneController.dispose();
    _addressLine1Controller.dispose();
    _addressLine2Controller.dispose();
    _postalCodeController.dispose();
    _cityController.dispose();
    _cityFocusNode.dispose();
    _confirmPasswordController.dispose();
    _postalDebounce?.cancel();
    super.dispose();
  }

  Future<void> _handleSubmit() async {
    if (!_formKey.currentState!.validate()) return;
    if (!_isSignIn && _selectedCategories.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please select at least one category.')));
      return;
    }

    final authProvider = context.read<AuthProvider>();
    bool success;

    if (_isSignIn) {
      success = await authProvider.signInForRole(
        email: _emailController.text.trim(),
        password: _passwordController.text.trim(),
        requiredRole: AppRole.merchant,
      );
    } else {
      success = await authProvider.signUpMerchant(
        email: _emailController.text.trim(),
        password: _passwordController.text.trim(),
        businessName: _businessNameController.text.trim(),
        firstName: _firstNameController.text.trim(),
        lastName: _lastNameController.text.trim(),
        phone: _phoneController.text.trim(),
        addressLine1: _addressLine1Controller.text.trim(),
        addressLine2: _addressLine2Controller.text.trim().isNotEmpty ? _addressLine2Controller.text.trim() : null,
        city: _cityController.text.trim(),
        postalCode: _postalCodeController.text.trim(),
        countryName: (_selectedCountry ?? '').trim(),
        categories: _selectedCategories.toList(),
      );

      // Save Step 1 fields for Step 2 prefill even if email confirmation is
      // required (in that case the provider returns false with an
      // "Email not confirmed" error).
      final err = authProvider.error?.toLowerCase() ?? '';
      final isEmailNotConfirmed = err.contains('email not confirmed');
      if (success || isEmailNotConfirmed) await _persistStep1Draft();

      if (!success && isEmailNotConfirmed && mounted) {
        // Switch to sign-in view so the user can paste the code / retry after confirming.
        setState(() => _isSignIn = true);
      }
    }

    if (success && mounted) {
      // Router will redirect merchants without full access to onboarding.
      context.go('/merchant-dashboard');
      return;
    }

    if (!mounted) return;
    final error = authProvider.error ?? 'Authentication failed';
    final isEmailNotConfirmed = error.toLowerCase().contains('email not confirmed');
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(isEmailNotConfirmed ? 'Email not confirmed. Please check your inbox.' : error),
        action: isEmailNotConfirmed
            ? SnackBarAction(
                label: 'Resend',
                onPressed: () async {
                  final ok = await context.read<AuthProvider>().resendSignupConfirmationEmail(_emailController.text);
                  if (!mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(ok ? 'Confirmation email sent.' : (context.read<AuthProvider>().error ?? 'Failed to resend'))),
                  );
                },
              )
            : null,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final authProvider = context.watch<AuthProvider>();

    return Scaffold(
      appBar: CaddyMoneyTopAppBar(
        showSignOut: false,
        leading: IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => context.pop()),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: AppSpacing.paddingLg,
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: AppSpacing.lg),
                Text(
                  _isSignIn ? l10n.merchantRole : 'Register Merchant',
                  style: Theme.of(context).textTheme.headlineLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: AppSpacing.xxl),
                if (!_isSignIn) ...[
                  DropdownButtonFormField<String>(
                    value: _selectedCountry,
                    decoration: const InputDecoration(
                      labelText: 'Country',
                      prefixIcon: Icon(Icons.public_outlined),
                    ),
                    items: _countryOptions
                        .map((c) => DropdownMenuItem<String>(value: c, child: Text(c)))
                        .toList(),
                    onChanged: (v) {
                      setState(() {
                        _selectedCountry = v;
                        _selectedCity = null;
                        _suggestedCities = const [];
                        _cityController.clear();
                      });
                      // City suggestions depend on both country and postal code.
                      // Only refresh if the user already entered a postal code.
                      if (_postalCodeController.text.trim().isNotEmpty) {
                        _refreshCitySuggestions();
                      }
                    },
                    validator: (v) => (v == null || v.trim().isEmpty) ? l10n.requiredField : null,
                  ),
                  const SizedBox(height: AppSpacing.md),
                  TextFormField(
                    controller: _businessNameController,
                    decoration: InputDecoration(
                      labelText: l10n.businessName,
                      prefixIcon: const Icon(Icons.business_outlined),
                    ),
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) {
                        return l10n.requiredField;
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: AppSpacing.md),
                  Row(
                    children: [
                      Expanded(
                        child: TextFormField(
                          controller: _firstNameController,
                          decoration: const InputDecoration(
                            labelText: 'First name',
                            prefixIcon: Icon(Icons.person_outline),
                          ),
                          validator: (value) {
                            if (value == null || value.trim().isEmpty) return l10n.requiredField;
                            return null;
                          },
                        ),
                      ),
                      const SizedBox(width: AppSpacing.md),
                      Expanded(
                        child: TextFormField(
                          controller: _lastNameController,
                          decoration: const InputDecoration(
                            labelText: 'Last name',
                            prefixIcon: Icon(Icons.person_outline),
                          ),
                          validator: (value) {
                            if (value == null || value.trim().isEmpty) return l10n.requiredField;
                            return null;
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.md),
                  TextFormField(
                    controller: _phoneController,
                    decoration: InputDecoration(
                      labelText: l10n.phone,
                      prefixIcon: const Icon(Icons.phone_outlined),
                    ),
                    keyboardType: TextInputType.phone,
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) return l10n.requiredField;
                      return null;
                    },
                  ),
                  const SizedBox(height: AppSpacing.md),
                  _CategoryMultiSelectField(
                    selected: _selectedCategories,
                    onChanged: (next) => setState(() {
                      _selectedCategories
                        ..clear()
                        ..addAll(next);
                    }),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  TextFormField(
                    controller: _addressLine1Controller,
                    decoration: const InputDecoration(
                      labelText: 'Address line',
                      prefixIcon: Icon(Icons.location_on_outlined),
                    ),
                    validator: (v) => (v == null || v.trim().isEmpty) ? l10n.requiredField : null,
                  ),
                  const SizedBox(height: AppSpacing.md),
                  TextFormField(
                    controller: _addressLine2Controller,
                    decoration: const InputDecoration(
                      labelText: 'Address complement',
                      prefixIcon: Icon(Icons.location_on_outlined),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  Row(
                    children: [
                      Expanded(
                        child: TextFormField(
                          controller: _postalCodeController,
                          decoration: const InputDecoration(
                            labelText: 'Postal code',
                            prefixIcon: Icon(Icons.local_post_office_outlined),
                          ),
                          validator: (v) => (v == null || v.trim().isEmpty) ? l10n.requiredField : null,
                        ),
                      ),
                      const SizedBox(width: AppSpacing.md),
                      Expanded(
                        child: DropdownMenu<String>(
                          width: double.infinity,
                          expandedInsets: EdgeInsets.zero,
                          controller: _cityController,
                          focusNode: _cityFocusNode,
                          requestFocusOnTap: true,
                          enableFilter: true,
                          enableSearch: true,
                          inputDecorationTheme: Theme.of(context).inputDecorationTheme.copyWith(
                            isDense: false,
                            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                          ),
                          leadingIcon: const Icon(Icons.location_city_outlined),
                          label: const Text('City'),
                          trailingIcon: _isCityLookupLoading
                              ? Padding(
                                  padding: const EdgeInsets.only(right: 12),
                                  child: SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(strokeWidth: 2, color: Theme.of(context).colorScheme.primary),
                                  ),
                                )
                              : null,
                          helperText: (_selectedCountry == null)
                              ? 'Select a country first'
                              : (_postalCodeController.text.trim().isEmpty)
                                  ? 'Enter postal code to see cities'
                                  : _isCityLookupLoading
                                      ? 'Searching cities…'
                                      : (_suggestedCities.isEmpty)
                                          ? (_cityLookupError ?? 'No match for this postal code (type your city)')
                                          : null,
                          dropdownMenuEntries: _suggestedCities
                              .map((c) => DropdownMenuEntry<String>(value: c, label: c))
                              .toList(growable: false),
                          onSelected: (selection) => setState(() => _selectedCity = selection),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.md),
                ],
                TextFormField(
                  controller: _emailController,
                  decoration: InputDecoration(
                    labelText: l10n.email,
                    prefixIcon: const Icon(Icons.email_outlined),
                  ),
                  keyboardType: TextInputType.emailAddress,
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return l10n.requiredField;
                    }
                    if (!value.contains('@')) {
                      return l10n.invalidEmail;
                    }
                    return null;
                  },
                ),
                const SizedBox(height: AppSpacing.md),
                TextFormField(
                  controller: _passwordController,
                  decoration: InputDecoration(
                    labelText: l10n.password,
                    prefixIcon: const Icon(Icons.lock_outline),
                    suffixIcon: IconButton(
                      icon: Icon(_obscurePassword ? Icons.visibility_off : Icons.visibility),
                      onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                    ),
                  ),
                  obscureText: _obscurePassword,
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return l10n.requiredField;
                    }
                    if (value.length < 8) {
                      return l10n.passwordTooShort;
                    }
                    return null;
                  },
                ),
                if (!_isSignIn) ...[
                  const SizedBox(height: AppSpacing.md),
                  TextFormField(
                    controller: _confirmPasswordController,
                    decoration: InputDecoration(
                      labelText: l10n.confirmPassword,
                      prefixIcon: const Icon(Icons.lock_outline),
                      suffixIcon: IconButton(
                        icon: Icon(_obscureConfirmPassword ? Icons.visibility_off : Icons.visibility),
                        onPressed: () => setState(() => _obscureConfirmPassword = !_obscureConfirmPassword),
                      ),
                    ),
                    obscureText: _obscureConfirmPassword,
                    validator: (value) {
                      if (value != _passwordController.text) {
                        return l10n.passwordsDoNotMatch;
                      }
                      return null;
                    },
                  ),
                ],
                const SizedBox(height: AppSpacing.xl),
                ElevatedButton(
                  onPressed: authProvider.isLoading ? null : _handleSubmit,
                  child: authProvider.isLoading
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : Text(_isSignIn ? l10n.signIn : l10n.signUp),
                ),
                const SizedBox(height: AppSpacing.lg),
                Center(
                  child: TextButton(
                    onPressed: () => setState(() => _isSignIn = !_isSignIn),
                    child: Text(
                      _isSignIn ? l10n.dontHaveAccount : l10n.alreadyHaveAccount,
                      style: const TextStyle(color: AppColors.primary),
                    ),
                  ),
                ),
                if (authProvider.error != null && authProvider.error!.toLowerCase().contains('email not confirmed')) ...[
                  const SizedBox(height: AppSpacing.sm),
                  Center(
                    child: TextButton(
                      onPressed: authProvider.isLoading
                          ? null
                          : () async {
                              final ok = await context.read<AuthProvider>().resendSignupConfirmationEmail(_emailController.text);
                              if (!mounted) return;
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text(ok ? 'Confirmation email sent.' : (context.read<AuthProvider>().error ?? 'Failed to resend'))),
                              );
                            },
                      child: const Text('Resend confirmation email', style: TextStyle(color: AppColors.primary)),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class MerchantStep1Draft {
  final String businessName;
  final String firstName;
  final String lastName;
  final String phone;
  final String email;
  final String addressLine1;
  final String? addressLine2;
  final String city;
  final String postalCode;
  final String countryName;
  final List<String> categories;

  MerchantStep1Draft({
    required this.businessName,
    required this.firstName,
    required this.lastName,
    required this.phone,
    required this.email,
    required this.addressLine1,
    required this.addressLine2,
    required this.city,
    required this.postalCode,
    required this.countryName,
    required this.categories,
  });

  String encode() {
    return [
      businessName,
      firstName,
      lastName,
      phone,
      email,
      addressLine1,
      addressLine2 ?? '',
      city,
      postalCode,
      countryName,
      categories.join('|'),
    ].join(';;');
  }
}
