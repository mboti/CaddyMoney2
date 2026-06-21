import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';
import 'package:caddymoney/theme.dart';
import 'package:caddymoney/widgets/caddy_money_top_app_bar.dart';
import 'package:caddymoney/core/constants/app_constants.dart';
import 'package:caddymoney/core/enums/merchant_status.dart';
import 'package:caddymoney/nav.dart';
import 'package:caddymoney/providers/auth_provider.dart';
import 'package:caddymoney/services/merchant_service.dart';

class MerchantOnboardingKycScreen extends StatefulWidget {
  const MerchantOnboardingKycScreen({super.key});

  @override
  State<MerchantOnboardingKycScreen> createState() => _MerchantOnboardingKycScreenState();
}

class _MerchantOnboardingKycScreenState extends State<MerchantOnboardingKycScreen> {
  final _stepFormKeys = List.generate(6, (_) => GlobalKey<FormState>());
  final _merchantService = MerchantService();

  final _pageController = PageController();
  int _stepIndex = 0;

  final _businessNameController = TextEditingController();
  final _firstNameController = TextEditingController();
  final _lastNameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _emailController = TextEditingController();

  final _businessTypeController = TextEditingController();
  final _registrationNumberController = TextEditingController();
  final _vatNumberController = TextEditingController();

  final _addressLine1Controller = TextEditingController();
  final _addressLine2Controller = TextEditingController();
  final _cityController = TextEditingController();
  final _postalCodeController = TextEditingController();
  final _countryController = TextEditingController();

  final _dobController = TextEditingController();
  final _nationalityController = TextEditingController();

  final _ibanController = TextEditingController();
  final _accountHolderController = TextEditingController();

  bool _loading = false;
  DateTime? _dateOfBirth;
  Set<String> _categories = {};

  XFile? _idDoc;
  XFile? _registrationDoc;
  XFile? _businessLogo;

  bool _prefillLoaded = false;

  bool _flowStarted = false;

  String _countryKey = '';

  static const _prefsKey = 'merchant_kyc_draft_v1';
  static const _step1DraftPrefsKey = 'merchant_step1_draft_v1';

  @override
  void initState() {
    super.initState();
    _loadPrefill();

    _countryKey = _normalizeCountryKey(_countryController.text);
    _countryController.addListener(_handleCountryChanged);

    for (final c in [
      _businessTypeController,
      _registrationNumberController,
      _vatNumberController,
      _addressLine1Controller,
      _addressLine2Controller,
      _cityController,
      _postalCodeController,
      _countryController,
      _dobController,
      _nationalityController,
      _ibanController,
      _accountHolderController,
    ]) {
      c.addListener(_scheduleAutosave);
    }
  }

  @override
  void dispose() {
    _pageController.dispose();
    _businessNameController.dispose();
    _firstNameController.dispose();
    _lastNameController.dispose();
    _phoneController.dispose();
    _emailController.dispose();
    _businessTypeController.dispose();
    _registrationNumberController.dispose();
    _vatNumberController.dispose();
    _addressLine1Controller.dispose();
    _addressLine2Controller.dispose();
    _cityController.dispose();
    _postalCodeController.dispose();
    _countryController.dispose();
    _dobController.dispose();
    _nationalityController.dispose();
    _ibanController.dispose();
    _accountHolderController.dispose();
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // When navigating back to this screen, ensure controller is on the current step.
    if (_pageController.hasClients) {
      final target = _stepIndex.clamp(0, 5);
      if ((_pageController.page ?? target.toDouble()).round() != target) {
        _pageController.jumpToPage(target);
      }
    }
  }

  String _normalizeCountryKey(String input) {
    var s = input.trim().toLowerCase();
    // Minimal accent folding for our supported set.
    s = s
        .replaceAll('é', 'e')
        .replaceAll('è', 'e')
        .replaceAll('ê', 'e')
        .replaceAll('ë', 'e')
        .replaceAll('à', 'a')
        .replaceAll('â', 'a')
        .replaceAll('î', 'i')
        .replaceAll('ï', 'i')
        .replaceAll('ô', 'o')
        .replaceAll('ù', 'u')
        .replaceAll('û', 'u')
        .replaceAll('ç', 'c');
    return s;
  }

  List<String> _businessTypesForCountryKey(String key) {
    final list = AppConstants.businessTypesByCountry[key];
    if (list != null && list.isNotEmpty) return list;
    return const ['LLC', 'Corporation', 'Sole proprietorship', 'Partnership', 'Other'];
  }

  void _handleCountryChanged() {
    final nextKey = _normalizeCountryKey(_countryController.text);
    if (nextKey == _countryKey) return;

    final allowed = _businessTypesForCountryKey(nextKey);
    final current = _businessTypeController.text.trim();
    setState(() {
      _countryKey = nextKey;
      if (current.isNotEmpty && !allowed.contains(current)) {
        _businessTypeController.clear();
      }
    });
  }

  Future<void> _loadPrefill() async {
    final auth = context.read<AuthProvider>();

    // Load merchant record (fresh) to prefill the UI.
    await auth.refreshMerchant();
    final m = auth.currentMerchant;
    final u = auth.currentUser;

    if (m != null) {
      _businessNameController.text = m.businessName;
      _firstNameController.text = m.ownerFirstName ?? (u?.fullName.split(' ').firstOrNull ?? '');
      _lastNameController.text = m.ownerLastName ?? ((u?.fullName ?? '').split(' ').skip(1).join(' '));
      _phoneController.text = m.businessPhone ?? '';
      _emailController.text = m.businessEmail;

      _addressLine1Controller.text = m.addressLine1 ?? '';
      _addressLine2Controller.text = m.addressLine2 ?? '';
      _cityController.text = m.city ?? '';
      _postalCodeController.text = m.postalCode ?? '';
      _countryController.text = m.countryName ?? (m.countryCode ?? '');

      _categories = {...m.categories};
    }

    // If the merchant row isn't available/readable yet, fall back to Step 1 local draft.
    try {
      if (_businessNameController.text.trim().isEmpty || _emailController.text.trim().isEmpty) {
        final prefs = await SharedPreferences.getInstance();
        final raw = prefs.getString(_step1DraftPrefsKey);
        if (raw != null && raw.isNotEmpty) {
          final d = MerchantStep1Draft.decode(raw);
          if (_businessNameController.text.trim().isEmpty) _businessNameController.text = d.businessName ?? '';
          if (_firstNameController.text.trim().isEmpty) _firstNameController.text = d.firstName ?? '';
          if (_lastNameController.text.trim().isEmpty) _lastNameController.text = d.lastName ?? '';
          if (_phoneController.text.trim().isEmpty) _phoneController.text = d.phone ?? '';
          if (_emailController.text.trim().isEmpty) _emailController.text = d.email ?? '';
          if (_addressLine1Controller.text.trim().isEmpty) _addressLine1Controller.text = d.addressLine1 ?? '';
          if (_addressLine2Controller.text.trim().isEmpty) _addressLine2Controller.text = d.addressLine2 ?? '';
          if (_cityController.text.trim().isEmpty) _cityController.text = d.city ?? '';
          if (_postalCodeController.text.trim().isEmpty) _postalCodeController.text = d.postalCode ?? '';
          if (_countryController.text.trim().isEmpty) _countryController.text = d.countryName ?? '';
          if (_categories.isEmpty && d.categories.isNotEmpty) _categories = {...d.categories};
        }
      }
    } catch (e) {
      debugPrint('Failed to load merchant step1 draft: $e');
    }

    // Then apply any local autosave draft over it.
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_prefsKey);
      if (raw != null && raw.isNotEmpty) {
        final map = MerchantKycDraft.decode(raw);
        _businessTypeController.text = map.businessType ?? _businessTypeController.text;
        _registrationNumberController.text = map.registrationNumber ?? _registrationNumberController.text;
        _vatNumberController.text = map.vatNumber ?? _vatNumberController.text;
        _nationalityController.text = map.nationality ?? _nationalityController.text;
        _ibanController.text = map.iban ?? _ibanController.text;
        _accountHolderController.text = map.accountHolderName ?? _accountHolderController.text;
        if (map.categories.isNotEmpty) _categories = {...map.categories};
        if (map.dateOfBirthIso != null) {
          _dateOfBirth = DateTime.tryParse(map.dateOfBirthIso!);
          if (_dateOfBirth != null) _dobController.text = _formatDate(_dateOfBirth!);
        }
      }
    } catch (e) {
      debugPrint('Failed to load merchant KYC draft: $e');
    }

    if (mounted) setState(() => _prefillLoaded = true);
  }

  DateTime? _tryParseDob() {
    final text = _dobController.text.trim();
    if (text.isEmpty) return null;

    // Expect: YYYY-MM-DD
    final parsed = DateTime.tryParse(text);
    return parsed;
  }

  String _formatDate(DateTime d) => '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  bool _hasValue(TextEditingController c) => c.text.trim().isNotEmpty;

  /// Step 1 shared fields:
  /// - If we already have a value: lock the field and show a green “completed” highlight.
  /// - If we don't: allow the merchant to fill it here (still treated as Step 1 shared).
  ///
  /// Important: we use `readOnly` instead of `enabled: false` because disabled
  /// fields often render their text with low-contrast “disabled” colors.
  bool _sharedFieldReadOnly(TextEditingController c) => _hasValue(c);

  TextStyle _sharedFieldTextStyle(BuildContext context) => TextStyle(color: Theme.of(context).colorScheme.onSurface);

  InputDecoration _sharedCompletedDecoration(BuildContext context, InputDecoration base, {required bool completed}) {
    final cs = Theme.of(context).colorScheme;
    if (!completed) return base;

    final success = cs.tertiary;
    final successFill = cs.tertiaryContainer.withValues(alpha: 0.22);
    final outline = success.withValues(alpha: 0.45);

    OutlineInputBorder border(double width) => OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
          borderSide: BorderSide(color: outline, width: width),
        );

    return base.copyWith(
      filled: true,
      fillColor: successFill,
      suffixIcon: Icon(Icons.verified_rounded, color: success),
      disabledBorder: border(1.2),
      enabledBorder: border(1.2),
      focusedBorder: border(2),
    );
  }

  void _scheduleAutosave() {
    // Keep simple: save on each change.
    _autosave();
  }

  Future<void> _autosave() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final draft = MerchantKycDraft(
        businessType: _businessTypeController.text.trim().isEmpty ? null : _businessTypeController.text.trim(),
        registrationNumber: _registrationNumberController.text.trim().isEmpty ? null : _registrationNumberController.text.trim(),
        vatNumber: _vatNumberController.text.trim().isEmpty ? null : _vatNumberController.text.trim(),
        dateOfBirthIso: _dateOfBirth?.toIso8601String(),
        nationality: _nationalityController.text.trim().isEmpty ? null : _nationalityController.text.trim(),
        iban: _ibanController.text.trim().isEmpty ? null : _ibanController.text.trim(),
        accountHolderName: _accountHolderController.text.trim().isEmpty ? null : _accountHolderController.text.trim(),
        categories: _categories.toList(),
      );
      await prefs.setString(_prefsKey, draft.encode());
    } catch (e) {
      debugPrint('Merchant KYC autosave failed: $e');
    }
  }

  Future<void> _pickDateOfBirth() async {
    final now = DateTime.now();
    final initial = _dateOfBirth ?? DateTime(now.year - 25, 1, 1);
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(1900, 1, 1),
      lastDate: DateTime(now.year - 18, now.month, now.day),
    );
    if (picked == null) return;
    setState(() {
      _dateOfBirth = picked;
      _dobController.text = _formatDate(picked);
    });
    _autosave();
  }

  Future<XFile?> _pickFile({required String label, required List<String> allowedExtensions}) async {
    try {
      final result = await FilePicker.platform.pickFiles(
        dialogTitle: label,
        type: FileType.custom,
        allowedExtensions: allowedExtensions,
        withData: kIsWeb,
      );
      if (result == null || result.files.isEmpty) return null;

      final f = result.files.first;
      if (f.bytes != null) return XFile.fromData(f.bytes!, name: f.name);

      final path = f.path;
      if (path == null || path.isEmpty) {
        debugPrint('FilePicker returned a null/empty path for $label');
        if (!mounted) return null;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Unable to open file browser. Please try again.')),
        );
        return null;
      }
      return XFile(path, name: f.name);
    } catch (e) {
      debugPrint('Failed to open file picker for $label: $e');
      if (!mounted) return null;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Unable to open file browser. Please try again.')),
      );
      return null;
    }
  }

  Future<XFile?> _pickDocumentViaActionSheet({
    required String pickerLabel,
    required String sheetTitle,
    required IconData sheetIcon,
    required List<String> allowedExtensions,
    String fileTileTitle = 'Choose a file',
    String fileTileSubtitle = 'Upload a PDF or an image from your device',
  }) async {
    // Dreamflow preview typically runs on web; camera capture isn't available there.
    if (kIsWeb) return _pickFile(label: pickerLabel, allowedExtensions: allowedExtensions);

    final action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (context) {
        final cs = Theme.of(context).colorScheme;
        return SafeArea(
          child: Padding(
            padding: AppSpacing.paddingLg,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Icon(sheetIcon, color: cs.primary),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: Text(
                        sheetTitle,
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.md),
                ListTile(
                  leading: Icon(Icons.photo_camera_outlined, color: cs.primary),
                  title: const Text('Use camera'),
                  subtitle: const Text('Take a photo and attach it'),
                  onTap: () => Navigator.of(context).pop('camera'),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.md)),
                ),
                const SizedBox(height: AppSpacing.sm),
                ListTile(
                  leading: Icon(Icons.folder_open_outlined, color: cs.primary),
                  title: Text(fileTileTitle),
                  subtitle: Text(fileTileSubtitle),
                  onTap: () => Navigator.of(context).pop('files'),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.md)),
                ),
              ],
            ),
          ),
        );
      },
    );

    if (!mounted || action == null) return null;

    // iOS can fail to present the document picker if we try to open it while the
    // bottom sheet is still dismissing. Give the route transition a brief moment.
    await Future.delayed(const Duration(milliseconds: 400));

    if (action == 'camera') {
      try {
        final picker = ImagePicker();
        final img = await picker.pickImage(
          source: ImageSource.camera,
          preferredCameraDevice: CameraDevice.rear,
          maxWidth: 2400,
          imageQuality: 88,
        );
        return img;
      } catch (e) {
        debugPrint('Failed to capture image from camera: $e');
        if (!mounted) return null;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Unable to access camera. Please choose a file instead.')),
        );
        return null;
      }
    }

    return _pickFile(label: pickerLabel, allowedExtensions: allowedExtensions);
  }

  Future<XFile?> _pickIdentityDocument() => _pickDocumentViaActionSheet(
        pickerLabel: 'Identity document',
        sheetTitle: 'Add identity document',
        sheetIcon: Icons.badge_outlined,
        allowedExtensions: const ['pdf', 'png', 'jpg', 'jpeg'],
      );

  Future<XFile?> _pickBusinessRegistrationDocument() => _pickDocumentViaActionSheet(
        pickerLabel: 'Business registration',
        sheetTitle: 'Add business registration document',
        sheetIcon: Icons.domain_verification_outlined,
        allowedExtensions: const ['pdf', 'png', 'jpg', 'jpeg'],
      );

  Future<XFile?> _pickBusinessLogo() => _pickDocumentViaActionSheet(
        pickerLabel: 'Business logo',
        sheetTitle: 'Add business logo',
        sheetIcon: Icons.image_outlined,
        allowedExtensions: const ['png', 'jpg', 'jpeg'],
        fileTileTitle: 'Load image',
        fileTileSubtitle: 'Upload a JPG or PNG from your device',
      );

  bool _isFormCompleteForSubmit() {
    if (_businessTypeController.text.trim().isEmpty) return false;
    if (_dateOfBirth == null) return false;
    if (_nationalityController.text.trim().isEmpty) return false;
    if (_ibanController.text.trim().isEmpty) return false;
    if (_accountHolderController.text.trim().isEmpty) return false;
    if (_categories.isEmpty) return false;
    if (_idDoc == null || _registrationDoc == null) return false;
    return true;
  }

  bool _validateStep(int step) {
    final key = _stepFormKeys[step];
    final ok = key.currentState?.validate() ?? true;
    if (!ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please fix the highlighted fields to continue.')),
      );
    }
    return ok;
  }

  Future<void> _goToStep(int next) async {
    final clamped = next.clamp(0, 5);
    if (clamped == _stepIndex) return;
    setState(() => _stepIndex = clamped);
    await _pageController.animateToPage(
      clamped,
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
    );
  }

  Future<void> _next() async {
    if (_loading) return;
    if (!_validateStep(_stepIndex)) return;
    if (_stepIndex >= 5) return;
    await _goToStep(_stepIndex + 1);
  }

  Future<void> _back() async {
    if (_loading) return;
    if (_stepIndex <= 0) return;
    await _goToStep(_stepIndex - 1);
  }

  Future<void> _submit() async {
    if (_loading) return;
    // Validate all steps before submission.
    for (var i = 0; i < _stepFormKeys.length; i++) {
      final ok = _stepFormKeys[i].currentState?.validate() ?? true;
      if (!ok) {
        await _goToStep(i);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please complete the highlighted fields.')),
        );
        return;
      }
    }
    if (!_isFormCompleteForSubmit()) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please complete all required fields and documents.')),
      );
      return;
    }

    setState(() => _loading = true);
    try {
      // Upload documents first.
      final idRes = await _merchantService.uploadMerchantDocument(docType: 'id_document', file: _idDoc!);
      final regRes = await _merchantService.uploadMerchantDocument(docType: 'business_registration', file: _registrationDoc!);
      final logoRes = _businessLogo == null ? (path: null as String?, error: null as String?) : await _merchantService.uploadMerchantDocument(docType: 'logo', file: _businessLogo!);

      final firstError = idRes.error ?? regRes.error ?? logoRes.error;
      if (idRes.path == null || regRes.path == null || (_businessLogo != null && logoRes.path == null)) {
        debugPrint('KYC upload failed. id=${idRes.error} reg=${regRes.error} logo=${logoRes.error}');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(firstError ?? 'Upload failed. Please try again or contact support.')),
        );
        return;
      }

      final saveRes = await _merchantService.updateMyMerchantKycResult(
        businessType: _businessTypeController.text.trim(),
        registrationNumber: _registrationNumberController.text.trim().isEmpty ? null : _registrationNumberController.text.trim(),
        vatNumber: _vatNumberController.text.trim().isEmpty ? null : _vatNumberController.text.trim(),
        dateOfBirth: _dateOfBirth!,
        nationality: _nationalityController.text.trim(),
        iban: _ibanController.text.trim(),
        accountHolderName: _accountHolderController.text.trim(),
        categories: _categories.toList(),
        idDocumentPath: idRes.path,
        businessRegistrationDocPath: regRes.path,
        logoPath: logoRes.path,
        submitForReview: true,
        businessName: _businessNameController.text.trim(),
        ownerFirstName: _firstNameController.text.trim(),
        ownerLastName: _lastNameController.text.trim(),
        businessEmail: _emailController.text.trim(),
        businessPhone: _phoneController.text.trim(),
        addressLine1: _addressLine1Controller.text.trim(),
        addressLine2: _addressLine2Controller.text.trim().isEmpty ? null : _addressLine2Controller.text.trim(),
        city: _cityController.text.trim(),
        postalCode: _postalCodeController.text.trim(),
        countryName: _countryController.text.trim(),
      );

      if (!mounted) return;
      if (!saveRes.ok) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(saveRes.error ?? 'Failed to save your profile. Please try again.')),
        );
        return;
      }

      await context.read<AuthProvider>().refreshMerchant();
      final refreshedMerchant = context.read<AuthProvider>().currentMerchant;
      final isActuallySubmitted = refreshedMerchant?.profileCompleted == true && refreshedMerchant?.status == MerchantStatus.pending;
      if (!isActuallySubmitted) {
        debugPrint(
          'KYC submit mismatch: update returned ok but refreshed merchant is profileCompleted=${refreshedMerchant?.profileCompleted} status=${refreshedMerchant?.status}',
        );
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Your submission could not be confirmed. Please try again. If the issue persists, contact support.',
            ),
          ),
        );
        return;
      }
      // Ensure no transient SnackBars from previous steps linger into the next screen.
      ScaffoldMessenger.of(context).clearSnackBars();
      context.go(AppRoutes.merchantUnderReview);
    } catch (e) {
      debugPrint('Merchant KYC submit failed: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('An error occurred. Please try again.')),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final merchant = auth.currentMerchant;
    final isApproved = merchant?.status == MerchantStatus.approved;
    final profileCompleted = merchant?.profileCompleted == true;

    final progress = isApproved
        ? 1.0
        : profileCompleted
            ? 0.85
            : 0.45;

    return Scaffold(
      appBar: CaddyMoneyTopAppBar(
        leading: IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => context.go('/role-selection')),
      ),
      body: SafeArea(
        child: !_prefillLoaded
            ? const Center(child: CircularProgressIndicator())
            : Padding(
                padding: AppSpacing.paddingLg,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Align(
                      alignment: Alignment.center,
                      child: Text(
                        'Merchant Verification',
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
                        textAlign: TextAlign.center,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    if (!_flowStarted) ...[
                      _StatusHeader(progress: progress, statusText: _statusText(merchant)),
                      const SizedBox(height: AppSpacing.lg),
                    ],

                    if (isApproved) ...[
                      _VerifiedPanel(onGoDashboard: () => context.go('/merchant-dashboard')),
                      const SizedBox(height: AppSpacing.lg),
                    ] else if (!_flowStarted) ...[
                      _BlockedPanel(
                        title: profileCompleted ? 'Profile submitted' : 'Profile incomplete',
                        message: profileCompleted
                            ? 'Thanks — we are reviewing your information. You’ll get access once verified.'
                            : 'To protect the platform, you must complete verification before using the app.',
                      ),
                      const SizedBox(height: AppSpacing.lg),
                    ],

                    if (_flowStarted) ...[
                      _KycStepProgressHeader(currentIndex: _stepIndex, stepCount: _stepFormKeys.length),
                      const SizedBox(height: AppSpacing.md),
                    ],

                    Expanded(
                      child: !_flowStarted
                          ? _KycIntroCard(
                              progress: progress,
                              statusText: _statusText(merchant),
                              isApproved: isApproved,
                              profileCompleted: profileCompleted,
                              onStart: () async {
                                setState(() => _flowStarted = true);
                                await _goToStep(0);
                              },
                            )
                          : ClipRRect(
                              borderRadius: BorderRadius.circular(AppRadius.lg),
                              child: Container(
                                decoration: BoxDecoration(
                                  color: Theme.of(context).colorScheme.surface,
                                  border: Border.all(color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.35)),
                                  borderRadius: BorderRadius.circular(AppRadius.lg),
                                ),
                                child: PageView(
                                  controller: _pageController,
                                  physics: const NeverScrollableScrollPhysics(),
                                  onPageChanged: (i) => setState(() => _stepIndex = i),
                                  children: [
                              _KycStepPage(
                                titleIcon: Icons.business_outlined,
                                title: '1. Business information',
                                child: Form(
                                  key: _stepFormKeys[0],
                                  child: SingleChildScrollView(
                                    padding: AppSpacing.paddingLg,
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.stretch,
                                      children: [
                                        TextFormField(
                                          controller: _businessNameController,
                                          readOnly: _sharedFieldReadOnly(_businessNameController),
                                          style: _sharedFieldTextStyle(context),
                                          decoration: _sharedCompletedDecoration(
                                            context,
                                            const InputDecoration(labelText: 'Legal business name', prefixIcon: Icon(Icons.business_outlined)),
                                            completed: _hasValue(_businessNameController),
                                          ),
                                          validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
                                        ),
                                        const SizedBox(height: AppSpacing.md),
                                        FormField<String>(
                                          validator: (_) => _businessTypeController.text.trim().isEmpty ? 'Required' : null,
                                          builder: (state) {
                                            final items = _businessTypesForCountryKey(_countryKey);
                                            return DropdownMenu<String>(
                                              controller: _businessTypeController,
                                              width: double.infinity,
                                              expandedInsets: EdgeInsets.zero,
                                              requestFocusOnTap: true,
                                              enableFilter: true,
                                              leadingIcon: const Icon(Icons.apartment_outlined),
                                              label: const Text('Business type'),
                                              hintText: items.isNotEmpty ? items.first : null,
                                              errorText: state.errorText,
                                              onSelected: (v) {
                                                if (v == null) return;
                                                _businessTypeController.text = v;
                                                state.didChange(v);
                                                _autosave();
                                              },
                                              dropdownMenuEntries: [
                                                for (final t in items) DropdownMenuEntry<String>(value: t, label: t),
                                              ],
                                            );
                                          },
                                        ),
                                        const SizedBox(height: AppSpacing.md),
                                        _PrefilledAddressPanel(
                                          line1: _addressLine1Controller,
                                          line2: _addressLine2Controller,
                                          city: _cityController,
                                          postalCode: _postalCodeController,
                                          country: _countryController,
                                          readOnlyLine1: _sharedFieldReadOnly(_addressLine1Controller),
                                          readOnlyLine2: _sharedFieldReadOnly(_addressLine2Controller),
                                          readOnlyCity: _sharedFieldReadOnly(_cityController),
                                          readOnlyPostalCode: _sharedFieldReadOnly(_postalCodeController),
                                          readOnlyCountry: _sharedFieldReadOnly(_countryController),
                                          style: _sharedFieldTextStyle(context),
                                          decorate: (d, completed) => _sharedCompletedDecoration(context, d, completed: completed),
                                        ),
                                        const SizedBox(height: AppSpacing.md),
                                        TextFormField(
                                          controller: _registrationNumberController,
                                          decoration: const InputDecoration(
                                            labelText: 'Business registration number (optional)',
                                            prefixIcon: Icon(Icons.badge_outlined),
                                          ),
                                        ),
                                        const SizedBox(height: AppSpacing.md),
                                        TextFormField(
                                          controller: _vatNumberController,
                                          decoration: const InputDecoration(
                                            labelText: 'VAT number (optional)',
                                            prefixIcon: Icon(Icons.confirmation_number_outlined),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                              _KycStepPage(
                                titleIcon: Icons.person_outline,
                                title: '2. Seller identity',
                                child: Form(
                                  key: _stepFormKeys[1],
                                  child: SingleChildScrollView(
                                    padding: AppSpacing.paddingLg,
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.stretch,
                                      children: [
                                        Row(
                                          children: [
                                            Expanded(
                                              child: TextFormField(
                                                controller: _firstNameController,
                                                readOnly: _sharedFieldReadOnly(_firstNameController),
                                                style: _sharedFieldTextStyle(context),
                                                decoration: _sharedCompletedDecoration(
                                                  context,
                                                  const InputDecoration(labelText: 'First name', prefixIcon: Icon(Icons.person_outline)),
                                                  completed: _hasValue(_firstNameController),
                                                ),
                                                validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
                                              ),
                                            ),
                                            const SizedBox(width: AppSpacing.md),
                                            Expanded(
                                              child: TextFormField(
                                                controller: _lastNameController,
                                                readOnly: _sharedFieldReadOnly(_lastNameController),
                                                style: _sharedFieldTextStyle(context),
                                                decoration: _sharedCompletedDecoration(
                                                  context,
                                                  const InputDecoration(labelText: 'Last name', prefixIcon: Icon(Icons.person_outline)),
                                                  completed: _hasValue(_lastNameController),
                                                ),
                                                validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
                                              ),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: AppSpacing.md),
                                        TextFormField(
                                          controller: _dobController,
                                          readOnly: true,
                                          decoration: InputDecoration(
                                            labelText: 'Date of birth',
                                            prefixIcon: const Icon(Icons.cake_outlined),
                                            suffixIcon: IconButton(
                                              icon: const Icon(Icons.calendar_month_outlined),
                                              onPressed: _pickDateOfBirth,
                                            ),
                                          ),
                                          validator: (_) => _dateOfBirth == null ? 'Required' : null,
                                        ),
                                        const SizedBox(height: AppSpacing.md),
                                        FormField<String>(
                                          validator: (_) => _nationalityController.text.trim().isEmpty ? 'Required' : null,
                                          builder: (state) {
                                            return DropdownMenu<String>(
                                              controller: _nationalityController,
                                              width: double.infinity,
                                              expandedInsets: EdgeInsets.zero,
                                              requestFocusOnTap: true,
                                              enableFilter: true,
                                              leadingIcon: const Icon(Icons.flag_outlined),
                                              label: const Text('Nationality'),
                                              errorText: state.errorText,
                                              onSelected: (v) {
                                                if (v == null) return;
                                                _nationalityController.text = v;
                                                state.didChange(v);
                                                _autosave();
                                              },
                                              dropdownMenuEntries: [
                                                for (final c in AppConstants.countryOptions) DropdownMenuEntry<String>(value: c, label: c),
                                              ],
                                            );
                                          },
                                        ),
                                        const SizedBox(height: AppSpacing.md),
                                        _DocumentPickerRow(
                                          title: 'Identity document (ID or passport)',
                                          value: _idDoc?.name,
                                          onPick: () async {
                                            final f = await _pickIdentityDocument();
                                            if (f == null) return;
                                            setState(() => _idDoc = f);
                                          },
                                          onClear: _idDoc == null
                                              ? null
                                              : () {
                                                  setState(() => _idDoc = null);
                                                },
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                              _KycStepPage(
                                titleIcon: Icons.account_balance_outlined,
                                title: '3. Banking information',
                                child: Form(
                                  key: _stepFormKeys[2],
                                  child: SingleChildScrollView(
                                    padding: AppSpacing.paddingLg,
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.stretch,
                                      children: [
                                        TextFormField(
                                          controller: _ibanController,
                                          decoration: const InputDecoration(labelText: 'IBAN', prefixIcon: Icon(Icons.account_balance_outlined)),
                                          validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
                                        ),
                                        const SizedBox(height: AppSpacing.md),
                                        TextFormField(
                                          controller: _accountHolderController,
                                          decoration: const InputDecoration(labelText: 'Account holder name', prefixIcon: Icon(Icons.person_outline)),
                                          validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                              _KycStepPage(
                                titleIcon: Icons.category_outlined,
                                title: '4. Business activity & Logo',
                                child: Form(
                                  key: _stepFormKeys[3],
                                  child: SingleChildScrollView(
                                    padding: AppSpacing.paddingLg,
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.stretch,
                                      children: [
                                        FormField<bool>(
                                          validator: (_) => _categories.isEmpty ? 'Select at least one category' : null,
                                          builder: (state) {
                                            return Column(
                                              crossAxisAlignment: CrossAxisAlignment.stretch,
                                              children: [
                                                if (state.errorText != null) ...[
                                                  Padding(
                                                    padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                                                    child: Text(
                                                      state.errorText!,
                                                      style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Theme.of(context).colorScheme.error),
                                                    ),
                                                  ),
                                                ],
                                                _CategoryMultiSelect(
                                                  selected: _categories,
                                                  onChanged: (next) {
                                                    setState(() => _categories = next);
                                                    state.didChange(true);
                                                    _autosave();
                                                  },
                                                ),
                                              ],
                                            );
                                          },
                                        ),
                                        const SizedBox(height: AppSpacing.md),
                                        _DocumentPickerRow(
                                          title: 'Logo',
                                          value: _businessLogo?.name,
                                          onPick: () async {
                                            final f = await _pickBusinessLogo();
                                            if (f == null) return;
                                            setState(() => _businessLogo = f);
                                          },
                                          onClear: _businessLogo == null
                                              ? null
                                              : () {
                                                  setState(() => _businessLogo = null);
                                                },
                                        ),
                                        const SizedBox(height: AppSpacing.sm),
                                        Text(
                                          'Logo is optional, but recommended for trust.',
                                          style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                              _KycStepPage(
                                titleIcon: Icons.support_agent_outlined,
                                title: '5. Contact & customer support',
                                child: Form(
                                  key: _stepFormKeys[4],
                                  child: SingleChildScrollView(
                                    padding: AppSpacing.paddingLg,
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.stretch,
                                      children: [
                                        TextFormField(
                                          controller: _phoneController,
                                          readOnly: _sharedFieldReadOnly(_phoneController),
                                          style: _sharedFieldTextStyle(context),
                                          decoration: _sharedCompletedDecoration(
                                            context,
                                            const InputDecoration(labelText: 'Phone number', prefixIcon: Icon(Icons.phone_outlined)),
                                            completed: _hasValue(_phoneController),
                                          ),
                                          validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
                                        ),
                                        const SizedBox(height: AppSpacing.md),
                                        TextFormField(
                                          controller: _emailController,
                                          readOnly: _sharedFieldReadOnly(_emailController),
                                          style: _sharedFieldTextStyle(context),
                                          decoration: _sharedCompletedDecoration(
                                            context,
                                            const InputDecoration(labelText: 'Professional email', prefixIcon: Icon(Icons.email_outlined)),
                                            completed: _hasValue(_emailController),
                                          ),
                                          validator: (v) {
                                            if (v == null || v.trim().isEmpty) return 'Required';
                                            if (!v.contains('@')) return 'Invalid email';
                                            return null;
                                          },
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                              _KycStepPage(
                                titleIcon: Icons.verified_outlined,
                                title: '6. Verification & compliance',
                                child: Form(
                                  key: _stepFormKeys[5],
                                  child: SingleChildScrollView(
                                    padding: AppSpacing.paddingLg,
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.stretch,
                                      children: [
                                        FormField<bool>(
                                          validator: (_) => _registrationDoc == null ? 'Required' : null,
                                          builder: (state) {
                                            return Column(
                                              crossAxisAlignment: CrossAxisAlignment.stretch,
                                              children: [
                                                if (state.errorText != null) ...[
                                                  Padding(
                                                    padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                                                    child: Text(
                                                      state.errorText!,
                                                      style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Theme.of(context).colorScheme.error),
                                                    ),
                                                  ),
                                                ],
                                                _DocumentPickerRow(
                                                  title: 'Business registration document (e.g., Kbis)',
                                                  value: _registrationDoc?.name,
                                                  onPick: () async {
                                                    final f = await _pickBusinessRegistrationDocument();
                                                    if (f == null) return;
                                                    setState(() => _registrationDoc = f);
                                                    state.didChange(true);
                                                  },
                                                  onClear: _registrationDoc == null
                                                      ? null
                                                      : () {
                                                          setState(() => _registrationDoc = null);
                                                          state.didChange(false);
                                                        },
                                                ),
                                              ],
                                            );
                                          },
                                        ),
                                        const SizedBox(height: AppSpacing.md),
                                        Text(
                                          'Access unlocks only after verification.',
                                          textAlign: TextAlign.center,
                                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                            color: Theme.of(context).colorScheme.onSurfaceVariant,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ],
                                ),
                              ),
                            ),
                    ),

                    const SizedBox(height: AppSpacing.md),
                    if (_flowStarted)
                      _StepNavBar(
                        stepIndex: _stepIndex,
                        isLoading: _loading,
                        onBack: _back,
                        onNext: _stepIndex == 5 ? _submit : _next,
                      ),
                  ],
                ),
              ),
      ),
    );
  }

  String _statusText(merchant) {
    if (merchant == null) return 'Profile incomplete (blocked)';
    if (merchant.status == MerchantStatus.approved) return 'Profile verified (full access)';
    if (merchant.profileCompleted == true) return 'Profile submitted (review in progress)';
    return 'Profile incomplete (blocked)';
  }
}

class _StatusHeader extends StatelessWidget {
  final double progress;
  final String statusText;

  const _StatusHeader({required this.progress, required this.statusText});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: AppSpacing.paddingLg,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppRadius.lg),
        color: cs.surfaceContainerHighest,
        border: Border.all(color: cs.outline.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.shield_outlined, color: cs.primary),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  statusText,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          ClipRRect(
            borderRadius: BorderRadius.circular(99),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 8,
              backgroundColor: cs.surface,
            ),
          ),
        ],
      ),
    );
  }
}

class _BlockedPanel extends StatelessWidget {
  final String title;
  final String message;

  const _BlockedPanel({required this.title, required this.message});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: AppSpacing.paddingLg,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppRadius.lg),
        color: cs.errorContainer.withValues(alpha: 0.35),
        border: Border.all(color: cs.error.withValues(alpha: 0.25)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.lock_outline, color: cs.error),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                const SizedBox(height: AppSpacing.xs),
                Text(message, style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: cs.onSurfaceVariant)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _VerifiedPanel extends StatelessWidget {
  final VoidCallback onGoDashboard;

  const _VerifiedPanel({required this.onGoDashboard});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: AppSpacing.paddingLg,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppRadius.lg),
        color: cs.primaryContainer.withValues(alpha: 0.35),
        border: Border.all(color: cs.primary.withValues(alpha: 0.25)),
      ),
      child: Row(
        children: [
          Icon(Icons.verified_outlined, color: cs.primary),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Text(
              'You’re verified. Full access is unlocked.',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ),
          FilledButton(
            onPressed: onGoDashboard,
            child: const Text('Open dashboard'),
          ),
        ],
      ),
    );
  }
}

class _KycIntroCard extends StatelessWidget {
  final double progress;
  final String statusText;
  final bool isApproved;
  final bool profileCompleted;
  final VoidCallback onStart;

  const _KycIntroCard({required this.progress, required this.statusText, required this.isApproved, required this.profileCompleted, required this.onStart});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final title = isApproved
        ? 'Verification complete'
        : profileCompleted
            ? 'Submission received'
            : 'Start merchant verification';
    final subtitle = isApproved
        ? 'You already have full access.'
        : profileCompleted
            ? 'We’re reviewing your information. You can revisit and update details if needed.'
            : 'Complete a few quick steps to unlock selling and payments.';

    return Container(
      padding: AppSpacing.paddingLg,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: cs.outline.withValues(alpha: 0.35)),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            cs.primaryContainer.withValues(alpha: 0.45),
            cs.surface,
          ],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
          const SizedBox(height: AppSpacing.xs),
          Text(subtitle, style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: cs.onSurfaceVariant, height: 1.45)),
          const SizedBox(height: AppSpacing.lg),
          Container(
            padding: AppSpacing.paddingMd,
            decoration: BoxDecoration(
              color: cs.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(AppRadius.md),
              border: Border.all(color: cs.outline.withValues(alpha: 0.25)),
            ),
            child: Row(
              children: [
                Icon(Icons.timelapse_rounded, color: cs.primary),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Text(
                    'Estimated time: 3–5 minutes',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                  ),
                ),
                Text('${(progress * 100).round()}%', style: Theme.of(context).textTheme.labelLarge?.copyWith(color: cs.onSurfaceVariant)),
              ],
            ),
          ),
          const Spacer(),
          if (!isApproved)
            ElevatedButton.icon(
              onPressed: onStart,
              icon: const Icon(Icons.play_arrow_rounded, color: Colors.white),
              label: const Text('Start', style: TextStyle(color: Colors.white)),
            )
          else
            FilledButton.tonal(
              onPressed: () => context.go('/merchant-dashboard'),
              child: const Text('Go to dashboard'),
            ),
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final IconData icon;
  final String title;

  const _SectionTitle({required this.icon, required this.title});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, color: Theme.of(context).colorScheme.primary),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Text(title, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
        ),
      ],
    );
  }
}

class _DocumentPickerRow extends StatelessWidget {
  final String title;
  final String? value;
  final VoidCallback onPick;
  final VoidCallback? onClear;

  const _DocumentPickerRow({required this.title, required this.value, required this.onPick, this.onClear});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: AppSpacing.paddingMd,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: cs.outline.withValues(alpha: 0.35)),
        color: cs.surface,
      ),
      child: Row(
        children: [
          Icon(Icons.upload_file_outlined, color: cs.primary),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
                const SizedBox(height: AppSpacing.xs),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        value ?? 'No file selected',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (onClear != null) ...[
                      const SizedBox(width: AppSpacing.xs),
                      IconButton(
                        tooltip: 'Remove file',
                        onPressed: onClear,
                        icon: Icon(Icons.delete_outline_rounded, color: cs.error),
                        visualDensity: VisualDensity.compact,
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints.tightFor(width: 32, height: 32),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          FilledButton.tonal(onPressed: onPick, child: const Text('Choose')),
        ],
      ),
    );
  }
}

class _CategoryMultiSelect extends StatelessWidget {
  final Set<String> selected;
  final ValueChanged<Set<String>> onChanged;

  const _CategoryMultiSelect({required this.selected, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Wrap(
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
    );
  }
}

class _PrefilledAddressPanel extends StatelessWidget {
  final TextEditingController line1;
  final TextEditingController line2;
  final TextEditingController city;
  final TextEditingController postalCode;
  final TextEditingController country;
  final bool readOnlyLine1;
  final bool readOnlyLine2;
  final bool readOnlyCity;
  final bool readOnlyPostalCode;
  final bool readOnlyCountry;
  final TextStyle style;
  final InputDecoration Function(InputDecoration base, bool completed) decorate;

  const _PrefilledAddressPanel({
    required this.line1,
    required this.line2,
    required this.city,
    required this.postalCode,
    required this.country,
    required this.readOnlyLine1,
    required this.readOnlyLine2,
    required this.readOnlyCity,
    required this.readOnlyPostalCode,
    required this.readOnlyCountry,
    required this.style,
    required this.decorate,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        TextFormField(
          controller: line1,
          readOnly: readOnlyLine1,
          style: style,
          decoration: decorate(
            const InputDecoration(labelText: 'Registered address line', prefixIcon: Icon(Icons.location_on_outlined)),
            line1.text.trim().isNotEmpty,
          ),
          validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
        ),
        const SizedBox(height: AppSpacing.md),
        TextFormField(
          controller: line2,
          readOnly: readOnlyLine2,
          style: style,
          decoration: decorate(
            const InputDecoration(labelText: 'Address complement (optional)', prefixIcon: Icon(Icons.location_on_outlined)),
            line2.text.trim().isNotEmpty,
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        Row(
          children: [
            Expanded(
              child: TextFormField(
                controller: city,
                readOnly: readOnlyCity,
                style: style,
                decoration: decorate(
                  const InputDecoration(labelText: 'City', prefixIcon: Icon(Icons.location_city_outlined)),
                  city.text.trim().isNotEmpty,
                ),
                validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: TextFormField(
                controller: postalCode,
                readOnly: readOnlyPostalCode,
                style: style,
                decoration: decorate(
                  const InputDecoration(labelText: 'Postal code', prefixIcon: Icon(Icons.local_post_office_outlined)),
                  postalCode.text.trim().isNotEmpty,
                ),
                validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        TextFormField(
          controller: country,
          readOnly: readOnlyCountry,
          style: style,
          decoration: decorate(
            const InputDecoration(labelText: 'Country', prefixIcon: Icon(Icons.public_outlined)),
            country.text.trim().isNotEmpty,
          ),
          validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
        ),
      ],
    );
  }
}

class _KycStepProgressHeader extends StatelessWidget {
  final int currentIndex;
  final int stepCount;

  const _KycStepProgressHeader({required this.currentIndex, required this.stepCount});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final safeStepCount = stepCount <= 0 ? 1 : stepCount;
    final safeCurrent = currentIndex.clamp(0, safeStepCount - 1);
    final value = (safeCurrent + 1) / safeStepCount;

    return Container(
      padding: AppSpacing.paddingMd,
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: cs.outline.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(Icons.route_outlined, color: cs.primary),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  'Step ${safeCurrent + 1} of $safeStepCount',
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800),
                ),
              ),
              Text(
                '${(value * 100).round()}%',
                style: Theme.of(context).textTheme.labelLarge?.copyWith(color: cs.onSurfaceVariant),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          ClipRRect(
            borderRadius: BorderRadius.circular(99),
            child: LinearProgressIndicator(
              value: value,
              minHeight: 8,
              backgroundColor: cs.surface,
            ),
          ),
        ],
      ),
    );
  }
}

class _KycStepPage extends StatelessWidget {
  final IconData titleIcon;
  final String title;
  final Widget child;

  const _KycStepPage({required this.titleIcon, required this.title, required this.child});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: AppSpacing.md),
          decoration: BoxDecoration(
            color: cs.surfaceContainerHighest,
            border: Border(bottom: BorderSide(color: cs.outline.withValues(alpha: 0.25))),
          ),
          child: Row(
            children: [
              Icon(titleIcon, color: cs.primary),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(title, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
              ),
            ],
          ),
        ),
        Expanded(child: child),
      ],
    );
  }
}

class _StepNavBar extends StatelessWidget {
  final int stepIndex;
  final bool isLoading;
  final VoidCallback onBack;
  final VoidCallback onNext;

  const _StepNavBar({required this.stepIndex, required this.isLoading, required this.onBack, required this.onNext});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isFirst = stepIndex == 0;
    final isLast = stepIndex == 5;

    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: cs.outline.withValues(alpha: 0.35)),
      ),
      child: Row(
        children: [
          if (!isFirst) ...[
            Expanded(
              child: OutlinedButton.icon(
                onPressed: isLoading ? null : onBack,
                icon: Icon(Icons.arrow_back_rounded, color: cs.primary),
                label: Text('Back', style: TextStyle(color: cs.primary)),
              ),
            ),
            const SizedBox(width: AppSpacing.md),
          ],
          Expanded(
            child: ElevatedButton.icon(
              onPressed: isLoading ? null : onNext,
              icon: isLoading
                  ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : Icon(isLast ? Icons.lock_open_outlined : Icons.arrow_forward_rounded, color: Colors.white),
              label: Text(isLast ? 'Validate' : 'Next', style: const TextStyle(color: Colors.white)),
            ),
          ),
        ],
      ),
    );
  }
}

class MerchantKycDraft {
  final String? businessType;
  final String? registrationNumber;
  final String? vatNumber;
  final String? dateOfBirthIso;
  final String? nationality;
  final String? iban;
  final String? accountHolderName;
  final List<String> categories;

  MerchantKycDraft({
    required this.businessType,
    required this.registrationNumber,
    required this.vatNumber,
    required this.dateOfBirthIso,
    required this.nationality,
    required this.iban,
    required this.accountHolderName,
    required this.categories,
  });

  String encode() {
    return [
      businessType ?? '',
      registrationNumber ?? '',
      vatNumber ?? '',
      dateOfBirthIso ?? '',
      nationality ?? '',
      iban ?? '',
      accountHolderName ?? '',
      categories.join('|'),
    ].join(';;');
  }

  static MerchantKycDraft decode(String raw) {
    final parts = raw.split(';;');
    String? pick(int i) => parts.length > i && parts[i].trim().isNotEmpty ? parts[i].trim() : null;

    // Backward compatible parsing:
    // v1 (old): 10 parts = ... accountHolderName, customerSupportAddress, categories, sms
    // v2 (old): 9 parts = ... accountHolderName, categories, sms
    // v3 (current): 8 parts = ... accountHolderName, categories
    final isV1 = parts.length >= 10;
    final isV2 = parts.length == 9;
    final categoriesIndex = isV1 ? 8 : 7;
    final categoriesIndexV3 = 7;

    final cats = pick(isV2 || isV1 ? categoriesIndex : categoriesIndexV3)?.split('|').where((e) => e.trim().isNotEmpty).toList() ?? <String>[];
    return MerchantKycDraft(
      businessType: pick(0),
      registrationNumber: pick(1),
      vatNumber: pick(2),
      dateOfBirthIso: pick(3),
      nationality: pick(4),
      iban: pick(5),
      accountHolderName: pick(6),
      categories: cats,
    );
  }
}

class MerchantStep1Draft {
  final String? businessName;
  final String? firstName;
  final String? lastName;
  final String? phone;
  final String? email;
  final String? addressLine1;
  final String? addressLine2;
  final String? city;
  final String? postalCode;
  final String? countryName;
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

  static MerchantStep1Draft decode(String raw) {
    final parts = raw.split(';;');
    String? pick(int i) => parts.length > i && parts[i].trim().isNotEmpty ? parts[i].trim() : null;
    final cats = pick(10)?.split('|').where((e) => e.trim().isNotEmpty).toList() ?? <String>[];
    return MerchantStep1Draft(
      businessName: pick(0),
      firstName: pick(1),
      lastName: pick(2),
      phone: pick(3),
      email: pick(4),
      addressLine1: pick(5),
      addressLine2: pick(6),
      city: pick(7),
      postalCode: pick(8),
      countryName: pick(9),
      categories: cats,
    );
  }
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
