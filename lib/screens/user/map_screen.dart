import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart' as latlong;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:go_router/go_router.dart';
import 'dart:async';
import 'dart:ui';

import 'package:caddymoney/core/utils/app_localizations_temp.dart';
import 'package:caddymoney/models/merchant_model.dart';
import 'package:caddymoney/screens/merchant/merchant_dashboard_screen.dart';
import 'package:caddymoney/screens/user/widgets/user_bottom_nav_bar.dart';
import 'package:caddymoney/services/merchant_service.dart';
import 'package:caddymoney/theme.dart';
import 'package:caddymoney/widgets/support_notifications_app_bar.dart';
import 'package:caddymoney/core/enums/support_requester_type.dart';

class MapScreen extends StatefulWidget {
  const MapScreen({super.key});

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  final _merchantService = MerchantService();

  static const _radiusPrefsKey = 'merchant_search_radius_km';
  static const List<int> _radiusOptionsKm = [1, 2, 5, 10];

  bool _isLoading = true;
  String? _error;
  List<MerchantModel> _merchants = const [];

  bool _isLocating = false;
  int _radiusKm = 2;
  latlong.LatLng? _userPos;
  bool _nearbyOnly = false;
  Map<String, double> _distanceMetersByMerchantId = const {};

  String? _selectedCategory;

  final TextEditingController _cityController = TextEditingController();
  Timer? _cityDebounce;
  String _cityQuery = '';

  @override
  void initState() {
    super.initState();
    _loadRadiusSetting();
    _load();
  }

  @override
  void dispose() {
    _cityDebounce?.cancel();
    _cityController.dispose();
    super.dispose();
  }

  Future<void> _loadRadiusSetting() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getInt(_radiusPrefsKey);
      final v = saved == null ? null : _radiusOptionsKm.contains(saved) ? saved : null;
      if (!mounted) return;
      setState(() => _radiusKm = v ?? 2);
    } catch (e) {
      debugPrint('MapScreen: failed to load radius setting: $e');
    }
  }

  Future<void> _saveRadiusSetting(int km) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_radiusPrefsKey, km);
    } catch (e) {
      debugPrint('MapScreen: failed to save radius setting: $e');
    }
  }

  Future<void> _load() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      // User-facing map list: show only approved merchants.
      final items = await _merchantService.listMerchants(status: 'approved', profileCompleted: true, limit: 200);
      if (!mounted) return;
      setState(() => _merchants = items);
    } catch (e) {
      debugPrint('MapScreen: failed to load merchants: $e');
      if (!mounted) return;
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  List<String> get _availableCategories {
    final set = <String>{};
    for (final m in _merchants) {
      for (final c in m.categories) {
        final s = c.trim();
        if (s.isNotEmpty) set.add(s);
      }
    }
    final list = set.toList()..sort();
    return list;
  }

  List<MerchantModel> get _filteredMerchants {
    final base = _merchants.where((m) {
      final q = _cityQuery.trim().toLowerCase();
      final city = (m.city ?? '').trim().toLowerCase();
      final cityOk = q.isEmpty || city.contains(q);
      final catOk = _selectedCategory == null || m.categories.map((e) => e.trim()).contains(_selectedCategory);
      return cityOk && catOk;
    }).toList();

    if (!_nearbyOnly || _userPos == null) return base;

    final within = <MerchantModel>[];
    for (final m in base) {
      final d = _distanceMetersByMerchantId[m.id];
      if (d == null) continue;
      if (d <= _radiusKm * 1000) within.add(m);
    }
    within.sort((a, b) => (_distanceMetersByMerchantId[a.id] ?? 1e18).compareTo(_distanceMetersByMerchantId[b.id] ?? 1e18));
    return within;
  }

  String _formatAddress(MerchantModel m) {
    final parts = <String>[];
    final l1 = (m.addressLine1 ?? '').trim();
    final l2 = (m.addressLine2 ?? '').trim();
    final city = (m.city ?? '').trim();
    final postal = (m.postalCode ?? '').trim();
    if (l1.isNotEmpty) parts.add(l1);
    if (l2.isNotEmpty) parts.add(l2);
    final cityLine = [postal, city].where((e) => e.trim().isNotEmpty).join(' ');
    if (cityLine.isNotEmpty) parts.add(cityLine);
    return parts.isEmpty ? '—' : parts.join(', ');
  }

  Future<void> _openPicker({required String title, required List<String> options, required String? current, required void Function(String? v) onPicked}) async {
    if (!mounted) return;
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    final selected = await showModalBottomSheet<String?>(
      context: context,
      showDragHandle: true,
      backgroundColor: cs.surface,
      isScrollControlled: true,
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.lg),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: AppSpacing.paddingLg,
                  child: Row(
                    children: [
                      Expanded(child: Text(title, style: tt.titleMedium?.copyWith(fontWeight: FontWeight.w800))),
                      TextButton(
                        onPressed: () => context.pop(null),
                        style: TextButton.styleFrom(foregroundColor: cs.primary),
                        child: const Text('Tout'),
                      ),
                    ],
                  ),
                ),
                Flexible(
                  child: ListView.separated(
                    shrinkWrap: true,
                    padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
                    itemCount: options.length,
                    separatorBuilder: (_, __) => const SizedBox(height: AppSpacing.sm),
                    itemBuilder: (context, i) {
                      final opt = options[i];
                      final isSelected = opt == current;
                      return _PickerTile(
                        label: opt,
                        selected: isSelected,
                        onTap: () => context.pop(opt),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );

    if (!mounted) return;
    onPicked(selected);
  }

  Future<void> _onRadiusButtonLongPress() async {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final picked = await showModalBottomSheet<int>(
      context: context,
      showDragHandle: true,
      backgroundColor: cs.surface,
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.sm, AppSpacing.lg, AppSpacing.lg),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('Rayon de recherche', style: tt.titleMedium?.copyWith(fontWeight: FontWeight.w900)),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  'Choisissez le rayon (en km) pour la recherche autour de vous.',
                  style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant, height: 1.3),
                ),
                const SizedBox(height: AppSpacing.md),
                for (final km in _radiusOptionsKm)
                  Padding(
                    padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                    child: _PickerTile(
                      label: '$km km',
                      selected: km == _radiusKm,
                      onTap: () => context.pop(km),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );

    if (!mounted || picked == null) return;
    setState(() => _radiusKm = picked);
    await _saveRadiusSetting(picked);
  }

  Future<void> _onRadiusButtonTap() async {
    if (_isLocating) return;
    setState(() {
      _isLocating = true;
      _error = null;
    });

    try {
      final enabled = await Geolocator.isLocationServiceEnabled();
      if (!enabled) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Activez la localisation pour rechercher autour de vous.')));
        return;
      }

      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) perm = await Geolocator.requestPermission();
      if (perm == LocationPermission.denied) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Permission de localisation refusée.')));
        return;
      }
      if (perm == LocationPermission.deniedForever) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Autorisez la localisation dans les réglages du téléphone.')));
        return;
      }

      final pos = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high);
      final here = latlong.LatLng(pos.latitude, pos.longitude);

      final distances = <String, double>{};
      for (final m in _merchants) {
        final lat = m.latitude;
        final lng = m.longitude;
        if (lat == null || lng == null) continue;
        try {
          final d = Geolocator.distanceBetween(here.latitude, here.longitude, lat, lng);
          distances[m.id] = d;
        } catch (e) {
          debugPrint('MapScreen: distanceBetween failed for merchantId=${m.id}: $e');
        }
      }

      if (!mounted) return;
      setState(() {
        _userPos = here;
        _nearbyOnly = true;
        _distanceMetersByMerchantId = distances;
      });

      final withinCount = _filteredMerchants.length;
      if (withinCount == 0 && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Aucun commerçant trouvé dans ce rayon.')));
      }
    } catch (e) {
      debugPrint('MapScreen: locate+filter failed: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erreur localisation: $e')));
      }
    } finally {
      if (mounted) setState(() => _isLocating = false);
    }
  }

  Future<void> _openDetails(MerchantModel merchant) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.35),
      builder: (context) => MerchantDetailSheet(merchant: merchant),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    final merchants = _filteredMerchants;

    return Scaffold(
      appBar: const SupportNotificationsAppBar(showLeading: false, requesterType: SupportRequesterType.user),
      bottomNavigationBar: const UserBottomNavBar(),
      body: SafeArea(
        bottom: false,
        child: RefreshIndicator(
          color: cs.primary,
          onRefresh: _load,
          child: ListView(
            padding: AppSpacing.paddingLg,
            children: [
              Align(
                alignment: Alignment.center,
                child: Text(
                  l10n.map, // “Carte” in FR.
                  style: tt.titleLarge?.copyWith(fontWeight: FontWeight.w800),
                  textAlign: TextAlign.center,
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              MerchantMapFilterBar(
                isLocating: _isLocating,
                radiusKm: _radiusKm,
                nearbyOnly: _nearbyOnly,
                onRadiusTap: _onRadiusButtonTap,
                onRadiusLongPress: _onRadiusButtonLongPress,
                selectedCategory: _selectedCategory,
                onCategoryPressed: () => _openPicker(
                  title: 'Catégorie',
                  options: _availableCategories,
                  current: _selectedCategory,
                  onPicked: (v) => setState(() => _selectedCategory = v),
                ),
                  cityController: _cityController,
                  onCityChanged: (v) {
                    _cityDebounce?.cancel();
                    _cityDebounce = Timer(const Duration(milliseconds: 180), () {
                      if (!mounted) return;
                      setState(() => _cityQuery = v);
                    });
                  },
                  onCityClear: () {
                    _cityDebounce?.cancel();
                    _cityController.clear();
                    setState(() => _cityQuery = '');
                  },
              ),
              const SizedBox(height: AppSpacing.lg),
              if (_isLoading)
                Padding(
                  padding: const EdgeInsets.only(top: AppSpacing.xl),
                  child: Center(child: CircularProgressIndicator(color: cs.primary)),
                )
              else if (_error != null)
                _InlineErrorCard(message: _error!, onRetry: _load)
              else if (merchants.isEmpty)
                _EmptyMerchantsState(
                  cityQuery: _cityQuery,
                  selectedCategory: _selectedCategory,
                  onClear: () => setState(() {
                    _selectedCategory = null;
                    _cityQuery = '';
                    _cityController.clear();
                  }),
                )
              else
                ...[
                  for (final m in merchants)
                    Padding(
                      padding: const EdgeInsets.only(bottom: AppSpacing.md),
                      child: MerchantListCard(
                        merchant: m,
                        addressText: _formatAddress(m),
                        onCallPressed: () => _launchTel(m.businessPhone),
                        onViewPressed: () => _openDetails(m),
                      ),
                    ),
                  const SizedBox(height: AppSpacing.xl),
                ],
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _launchTel(String? phone) async {
    final raw = (phone ?? '').trim();
    if (raw.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Numéro de téléphone indisponible.')));
      return;
    }
    final uri = Uri(scheme: 'tel', path: raw);
    try {
      final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!ok && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Impossible d\'ouvrir le téléphone.')));
      }
    } catch (e) {
      debugPrint('MapScreen: launch tel failed: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erreur téléphone: $e')));
      }
    }
  }
}

class MerchantMapFilterBar extends StatelessWidget {
  final int radiusKm;
  final bool isLocating;
  final bool nearbyOnly;
  final VoidCallback onRadiusTap;
  final VoidCallback onRadiusLongPress;
  final VoidCallback onCategoryPressed;
  final String? selectedCategory;

  final TextEditingController cityController;
  final ValueChanged<String> onCityChanged;
  final VoidCallback onCityClear;

  const MerchantMapFilterBar({
    super.key,
    required this.radiusKm,
    required this.isLocating,
    required this.nearbyOnly,
    required this.onRadiusTap,
    required this.onRadiusLongPress,
    required this.onCategoryPressed,
    required this.selectedCategory,
    required this.cityController,
    required this.onCityChanged,
    required this.onCityClear,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            _RadiusLocationButton(
              radiusKm: radiusKm,
              isLoading: isLocating,
              isActive: nearbyOnly,
              onTap: onRadiusTap,
              onLongPress: onRadiusLongPress,
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: _FilterPillButton(
                icon: Icons.sell_outlined,
                label: selectedCategory ?? 'Catégorie',
                isActive: selectedCategory != null,
                onPressed: onCategoryPressed,
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        _CityFilterTextPill(
          controller: cityController,
          onChanged: onCityChanged,
          onClear: onCityClear,
        ),
      ],
    );
  }
}

class _CityFilterTextPill extends StatelessWidget {
  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final VoidCallback onClear;

  const _CityFilterTextPill({
    required this.controller,
    required this.onChanged,
    required this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final isActive = controller.text.trim().isNotEmpty;
    final bg = isActive ? cs.primaryContainer : cs.surface;
    final fg = isActive ? cs.onPrimaryContainer : cs.onSurface;

    return Container(
      height: 44,
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.55)),
      ),
      child: Row(
        children: [
          Icon(Icons.location_city, size: 18, color: fg),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: TextField(
              controller: controller,
              onChanged: onChanged,
              style: tt.labelLarge?.copyWith(color: fg, fontWeight: FontWeight.w700),
              cursorColor: cs.primary,
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                isDense: true,
                border: InputBorder.none,
                hintText: 'Ville',
                hintStyle: tt.labelLarge?.copyWith(color: fg.withValues(alpha: 0.6), fontWeight: FontWeight.w700),
              ),
            ),
          ),
          if (isActive)
            Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: onClear,
                splashFactory: NoSplash.splashFactory,
                highlightColor: Colors.transparent,
                borderRadius: BorderRadius.circular(999),
                child: Padding(
                  padding: const EdgeInsets.all(8),
                  child: Icon(Icons.close, size: 18, color: fg.withValues(alpha: 0.9)),
                ),
              ),
            )
          else
            Icon(Icons.search, size: 18, color: fg.withValues(alpha: 0.7)),
        ],
      ),
    );
  }
}

class MerchantListCard extends StatelessWidget {
  final MerchantModel merchant;
  final String addressText;
  final VoidCallback onCallPressed;
  final VoidCallback onViewPressed;

  const MerchantListCard({
    super.key,
    required this.merchant,
    required this.addressText,
    required this.onCallPressed,
    required this.onViewPressed,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    final categories = merchant.categories.map((e) => e.trim()).where((e) => e.isNotEmpty).take(3).toList();
    final phoneText = (merchant.businessPhone ?? '').trim().isEmpty ? 'Téléphone' : (merchant.businessPhone ?? '').trim();

    final cardGradient = LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [
        cs.surface,
        cs.surfaceContainerHighest.withValues(alpha: 0.55),
      ],
    );

    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        gradient: cardGradient,
        borderRadius: BorderRadius.circular(AppRadius.xl),
        boxShadow: [
          BoxShadow(
            color: cs.shadow.withValues(alpha: 0.06),
            blurRadius: 22,
            offset: const Offset(0, 10),
          ),
        ],
        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.22)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _RingedMerchantAvatar(
            logoPathOrUrl: merchant.logoPath,
            size: 52,
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  merchant.businessName,
                  style: tt.titleMedium?.copyWith(fontWeight: FontWeight.w900, height: 1.1),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: AppSpacing.xs),
                _CategoryDotRow(categories: categories),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  addressText,
                  style: tt.bodyMedium?.copyWith(color: cs.onSurface, height: 1.25),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: AppSpacing.md),
                Row(
                  children: [
                    Expanded(
                      child: _PhonePillButton(
                        label: phoneText,
                        onPressed: onCallPressed,
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    _RoundIconButton(icon: Icons.visibility_outlined, tooltip: 'Voir', onPressed: onViewPressed),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _RingedMerchantAvatar extends StatelessWidget {
  final String? logoPathOrUrl;
  final double size;

  const _RingedMerchantAvatar({
    required this.logoPathOrUrl,
    required this.size,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      width: size,
      height: size,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: cs.surface,
        border: Border.all(color: cs.primary.withValues(alpha: 0.18), width: 1.5),
      ),
      child: MerchantLogoCircle(logoPathOrUrl: logoPathOrUrl, size: size - 8),
    );
  }
}

class _CategoryDotRow extends StatelessWidget {
  final List<String> categories;

  const _CategoryDotRow({required this.categories});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    if (categories.isEmpty) {
      return Text('—', style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant, height: 1.2), maxLines: 1, overflow: TextOverflow.ellipsis);
    }

    final children = <InlineSpan>[];
    for (var i = 0; i < categories.length; i++) {
      if (i != 0) {
        children.add(WidgetSpan(
          alignment: PlaceholderAlignment.middle,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Container(width: 5, height: 5, decoration: BoxDecoration(color: cs.primary, shape: BoxShape.circle)),
          ),
        ));
      }
      children.add(TextSpan(text: categories[i]));
    }

    return Text.rich(
      TextSpan(children: children),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant, height: 1.2, fontWeight: FontWeight.w500),
    );
  }
}

class _PhonePillButton extends StatelessWidget {
  final String label;
  final VoidCallback onPressed;

  const _PhonePillButton({
    required this.label,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return Semantics(
      button: true,
      label: 'Appeler $label',
      child: GestureDetector(
        onTap: onPressed,
        behavior: HitTestBehavior.opaque,
        child: Container(
          height: 44,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            color: cs.primary.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(999),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.call, size: 18, color: cs.primary),
              const SizedBox(width: 10),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: tt.titleSmall?.copyWith(color: cs.primary, fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class MerchantDetailSheet extends StatefulWidget {
  final MerchantModel merchant;

  const MerchantDetailSheet({
    super.key,
    required this.merchant,
  });

  @override
  State<MerchantDetailSheet> createState() => _MerchantDetailSheetState();
}

class _MerchantDetailSheetState extends State<MerchantDetailSheet> {
  final _service = MerchantService();
  late final Future<latlong.LatLng?> _posFuture = _resolvePos();

  Future<latlong.LatLng?> _resolvePos() async {
    final m = widget.merchant;
    if (m.latitude != null && m.longitude != null) return latlong.LatLng(m.latitude!, m.longitude!);

    // No stored coordinates yet: attempt a one-shot geocode from address (OSM fallback).
    final address = [m.addressLine1, m.addressLine2, m.postalCode, m.city, m.countryName]
        .whereType<String>()
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .join(', ');
    if (address.trim().isEmpty) return null;

    try {
      final res = await _service.geocodeAddress(address: address);
      if (res == null) return null;
      return latlong.LatLng(res.lat, res.lng);
    } catch (e) {
      debugPrint('MerchantDetailSheet: geocode failed: $e');
      return null;
    }
  }

  String _formatAddress(MerchantModel m) {
    final parts = <String>[];
    final l1 = (m.addressLine1 ?? '').trim();
    final l2 = (m.addressLine2 ?? '').trim();
    final city = (m.city ?? '').trim();
    final postal = (m.postalCode ?? '').trim();
    if (l1.isNotEmpty) parts.add(l1);
    if (l2.isNotEmpty) parts.add(l2);
    final cityLine = [postal, city].where((e) => e.trim().isNotEmpty).join(' ');
    if (cityLine.isNotEmpty) parts.add(cityLine);
    return parts.isEmpty ? '—' : parts.join(', ');
  }

  String _categoriesText(MerchantModel m) {
    final categories = m.categories.map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
    return categories.isEmpty ? '—' : categories.join(' • ');
  }

  Future<void> _launchTel(String? phone) async {
    final raw = (phone ?? '').trim();
    if (raw.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Numéro de téléphone indisponible.')));
      return;
    }
    final uri = Uri(scheme: 'tel', path: raw);
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (e) {
      debugPrint('MerchantDetailSheet: launch tel failed: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erreur téléphone: $e')));
      }
    }
  }

  Future<void> _launchDirections(latlong.LatLng? pos) async {
    if (pos == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Position indisponible pour l\'itinéraire.')));
      return;
    }

    // Universal deep link (works with Google Maps / browser).
    final uri = Uri.parse('https://www.google.com/maps/dir/?api=1&destination=${pos.latitude},${pos.longitude}');
    try {
      final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!ok && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Impossible d\'ouvrir l\'itinéraire.')));
      }
    } catch (e) {
      debugPrint('MerchantDetailSheet: launch directions failed: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erreur itinéraire: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final m = widget.merchant;

    return SafeArea(
      child: DraggableScrollableSheet(
        initialChildSize: 0.92,
        minChildSize: 0.55,
        maxChildSize: 0.95,
        builder: (context, scrollController) {
          return Container(
            decoration: BoxDecoration(
              color: cs.surface,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(AppRadius.xl)),
              border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.65)),
            ),
            clipBehavior: Clip.antiAlias,
            child: FutureBuilder<latlong.LatLng?>(
              future: _posFuture,
              builder: (context, snapshot) {
                final pos = snapshot.data;
                final isLoading = snapshot.connectionState == ConnectionState.waiting;

                return Stack(
                  children: [
                    Positioned.fill(
                      child: MerchantOsmMap(
                        position: pos,
                        isLoading: isLoading,
                        height: null,
                        borderRadius: 0,
                        showChrome: false,
                      ),
                    ),
                    Positioned(
                      left: AppSpacing.lg,
                      right: AppSpacing.lg,
                      top: AppSpacing.lg,
                      child: _MerchantMapHeaderCard(
                        merchant: m,
                        categoriesText: _categoriesText(m),
                        addressText: _formatAddress(m),
                        onClose: () => context.pop(),
                      ),
                    ),
                    Positioned(
                      left: AppSpacing.lg,
                      right: AppSpacing.lg,
                      bottom: AppSpacing.lg,
                      child: _MerchantMapActionBar(
                        onCall: () => _launchTel(m.businessPhone),
                        onDirections: () => _launchDirections(pos),
                      ),
                    ),
                  ],
                );
              },
            ),
          );
        },
      ),
    );
  }
}

class MerchantOsmMap extends StatefulWidget {
  final latlong.LatLng? position;
  final bool isLoading;
  final double? height;
  final double borderRadius;
  final bool showChrome;
  final bool showTileStyleSelector;

  const MerchantOsmMap({
    super.key,
    required this.position,
    required this.isLoading,
    this.height = 280,
    this.borderRadius = AppRadius.xl,
    this.showChrome = true,
    this.showTileStyleSelector = true,
  });

  @override
  State<MerchantOsmMap> createState() => _MerchantOsmMapState();
}

enum _MerchantMapTileStyle {
  standard,
  terrain,
  satellite,
}

class _MerchantOsmMapState extends State<MerchantOsmMap> {
  late final MapController _controller;

  _MerchantMapTileStyle _tileStyle = _MerchantMapTileStyle.standard;

  static const _fallbackCenter = latlong.LatLng(48.8566, 2.3522); // Paris
  static const double _fallbackZoom = 6.0;
  static const double _cityZoom = 14.0;

  String get _tileUrlTemplate {
    switch (_tileStyle) {
      case _MerchantMapTileStyle.standard:
        // Standard street map (OpenStreetMap)
        return 'https://tile.openstreetmap.org/{z}/{x}/{y}.png';
      case _MerchantMapTileStyle.terrain:
        // Topographic / relief-style map (OpenTopoMap)
        return 'https://a.tile.opentopomap.org/{z}/{x}/{y}.png';
      case _MerchantMapTileStyle.satellite:
        // Satellite imagery (ArcGIS / Esri)
        return 'https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}';
    }
  }

  @override
  void initState() {
    super.initState();
    _controller = MapController();
  }

  @override
  void didUpdateWidget(covariant MerchantOsmMap oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.position != widget.position && widget.position != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        try {
          _controller.move(widget.position!, _cityZoom);
        } catch (e) {
          debugPrint('MerchantOsmMap: failed to move map: $e');
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final center = widget.position ?? _fallbackCenter;
    final initialZoom = widget.position == null ? _fallbackZoom : _cityZoom;

    final map = Stack(
      children: [
        FlutterMap(
          mapController: _controller,
          options: MapOptions(
            initialCenter: center,
            initialZoom: initialZoom,
            interactionOptions: const InteractionOptions(flags: InteractiveFlag.all & ~InteractiveFlag.rotate),
          ),
          children: [
            TileLayer(
              urlTemplate: _tileUrlTemplate,
              userAgentPackageName: 'caddymoney',
            ),
            if (widget.position != null)
              MarkerLayer(
                markers: [
                  Marker(
                    point: widget.position!,
                    width: 46,
                    height: 46,
                    child: Icon(Icons.location_pin, color: cs.primary, size: 44),
                  ),
                ],
              ),
          ],
        ),
        if (widget.showTileStyleSelector)
          Positioned(
            left: widget.showChrome ? AppSpacing.md : AppSpacing.lg,
            // When this map is used inside the merchant detail sheet, a header card is
            // overlaid at the very top. Push the selector down so it stays tappable.
            // Extra offset so it never overlaps the translucent merchant header card.
            top: MediaQuery.paddingOf(context).top + (widget.showChrome ? AppSpacing.md : (AppSpacing.lg + 118)),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: cs.surface.withValues(alpha: 0.78),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.28)),
                boxShadow: [
                  BoxShadow(color: cs.shadow.withValues(alpha: 0.06), blurRadius: 18, offset: const Offset(0, 10)),
                ],
              ),
              child: Padding(
                padding: const EdgeInsets.all(6),
                child: SegmentedButton<_MerchantMapTileStyle>(
                  showSelectedIcon: false,
                  style: ButtonStyle(
                    visualDensity: VisualDensity.compact,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    padding: const WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: 10, vertical: 8)),
                    backgroundColor: WidgetStateProperty.resolveWith((states) {
                      if (states.contains(WidgetState.selected)) return cs.primary;
                      return cs.surface.withValues(alpha: 0.9);
                    }),
                    foregroundColor: WidgetStateProperty.resolveWith((states) {
                      if (states.contains(WidgetState.selected)) return cs.onPrimary;
                      return cs.onSurfaceVariant;
                    }),
                    overlayColor: const WidgetStatePropertyAll(Colors.transparent),
                    side: WidgetStatePropertyAll(BorderSide(color: cs.outlineVariant.withValues(alpha: 0.25))),
                    shape: WidgetStatePropertyAll(RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
                  ),
                  segments: const [
                    ButtonSegment(
                      value: _MerchantMapTileStyle.standard,
                      label: SizedBox.shrink(),
                      icon: _TileProviderLogo(
                        semanticsLabel: 'Standard',
                        imageUrl: 'https://www.openstreetmap.org/favicon.ico',
                        fallbackIcon: Icons.map_outlined,
                      ),
                    ),
                    ButtonSegment(
                      value: _MerchantMapTileStyle.terrain,
                      label: SizedBox.shrink(),
                      icon: _TileProviderLogo(
                        semanticsLabel: 'Terrain',
                        imageUrl: 'https://opentopomap.org/favicon.ico',
                        fallbackIcon: Icons.terrain_rounded,
                      ),
                    ),
                    ButtonSegment(
                      value: _MerchantMapTileStyle.satellite,
                      label: SizedBox.shrink(),
                      icon: _TileProviderLogo(
                        semanticsLabel: 'Satellite',
                        imageUrl: 'https://www.arcgis.com/favicon.ico',
                        fallbackIcon: Icons.satellite_alt_rounded,
                      ),
                    ),
                  ],
                  selected: {_tileStyle},
                  onSelectionChanged: (sel) {
                    if (sel.isEmpty) return;
                    setState(() => _tileStyle = sel.first);
                  },
                ),
              ),
            ),
          ),
        if (widget.showChrome && widget.isLoading)
          Align(
            alignment: Alignment.topRight,
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm),
                decoration: BoxDecoration(
                  color: cs.surface.withValues(alpha: 0.85),
                  borderRadius: BorderRadius.circular(AppRadius.lg),
                  border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.65)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: cs.primary)),
                    const SizedBox(width: AppSpacing.sm),
                    Text('Chargement...', style: Theme.of(context).textTheme.labelMedium),
                  ],
                ),
              ),
            ),
          ),
        if (widget.showChrome && !widget.isLoading && widget.position == null)
          Align(
            alignment: Alignment.topRight,
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm),
                decoration: BoxDecoration(
                  color: cs.surface.withValues(alpha: 0.85),
                  borderRadius: BorderRadius.circular(AppRadius.lg),
                  border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.65)),
                ),
                child: Text('Adresse non localisée', style: Theme.of(context).textTheme.labelMedium),
              ),
            ),
          ),
      ],
    );

    final decorated = Container(
      height: widget.height,
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.25),
        borderRadius: BorderRadius.circular(widget.borderRadius),
        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.65)),
      ),
      clipBehavior: Clip.antiAlias,
      child: map,
    );

    if (widget.height == null) {
      return DecoratedBox(
        decoration: BoxDecoration(color: cs.surfaceContainerHighest.withValues(alpha: 0.25)),
        child: map,
      );
    }
    return decorated;
  }
}

class _TileProviderLogo extends StatelessWidget {
  final String imageUrl;
  final String semanticsLabel;
  final IconData fallbackIcon;

  const _TileProviderLogo({
    required this.imageUrl,
    required this.semanticsLabel,
    required this.fallbackIcon,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Semantics(
      label: semanticsLabel,
      image: true,
      child: ClipOval(
        child: SizedBox(
          width: 18,
          height: 18,
          child: Image.network(
            imageUrl,
            fit: BoxFit.cover,
            errorBuilder: (context, error, stack) => Container(
              color: cs.surfaceContainerHighest.withValues(alpha: 0.4),
              child: Icon(fallbackIcon, size: 16, color: cs.onSurfaceVariant),
            ),
          ),
        ),
      ),
    );
  }
}

class _MerchantMapHeaderCard extends StatelessWidget {
  final MerchantModel merchant;
  final String categoriesText;
  final String addressText;
  final VoidCallback onClose;

  const _MerchantMapHeaderCard({
    required this.merchant,
    required this.categoriesText,
    required this.addressText,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    // Glass / transparent header so the map is subtly visible underneath.
    return ClipRRect(
      borderRadius: BorderRadius.circular(AppRadius.xl),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
        child: Container(
          padding: const EdgeInsets.all(AppSpacing.md),
          decoration: BoxDecoration(
            color: cs.surface.withValues(alpha: 0.28),
            borderRadius: BorderRadius.circular(AppRadius.xl),
            border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.22)),
            boxShadow: [
              BoxShadow(color: cs.shadow.withValues(alpha: 0.04), blurRadius: 18, offset: const Offset(0, 10)),
            ],
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _RingedMerchantAvatar(logoPathOrUrl: merchant.logoPath, size: 48),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      merchant.businessName,
                      style: tt.titleMedium?.copyWith(fontWeight: FontWeight.w900, height: 1.1),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      categoriesText,
                      style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant, height: 1.2, fontWeight: FontWeight.w600),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    Text(
                      addressText,
                      style: tt.bodySmall?.copyWith(color: cs.onSurface, height: 1.25),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              _RoundIconButton(icon: Icons.close, tooltip: 'Fermer', onPressed: onClose),
            ],
          ),
        ),
      ),
    );
  }
}

class _MerchantMapActionBar extends StatelessWidget {
  final VoidCallback onCall;
  final VoidCallback onDirections;

  const _MerchantMapActionBar({
    required this.onCall,
    required this.onDirections,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return ClipRRect(
      borderRadius: BorderRadius.circular(999),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
        child: Container(
          padding: const EdgeInsets.all(AppSpacing.sm),
          decoration: BoxDecoration(
            color: cs.surface.withValues(alpha: 0.58),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.28)),
            boxShadow: [
              BoxShadow(color: cs.shadow.withValues(alpha: 0.06), blurRadius: 18, offset: const Offset(0, 10)),
            ],
          ),
          child: Row(
            children: [
              Expanded(child: _MapPillSecondaryButton(icon: Icons.call, label: 'Téléphone', onPressed: onCall)),
              const SizedBox(width: AppSpacing.sm),
              Expanded(child: _MapPillPrimaryButton(icon: Icons.directions, label: 'S\'y rendre', onPressed: onDirections)),
            ],
          ),
        ),
      ),
    );
  }
}

class _MapPillSecondaryButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onPressed;

  const _MapPillSecondaryButton({
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return Material(
      color: cs.primary.withValues(alpha: 0.10),
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        onTap: onPressed,
        splashFactory: NoSplash.splashFactory,
        highlightColor: Colors.transparent,
        borderRadius: BorderRadius.circular(999),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: 12),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 18, color: cs.primary),
              const SizedBox(width: AppSpacing.sm),
              Flexible(
                child: Text(
                  label,
                  style: tt.labelLarge?.copyWith(color: cs.primary, fontWeight: FontWeight.w900),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MapPillPrimaryButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onPressed;

  const _MapPillPrimaryButton({
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return Material(
      color: cs.primary,
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        onTap: onPressed,
        splashFactory: NoSplash.splashFactory,
        highlightColor: Colors.transparent,
        borderRadius: BorderRadius.circular(999),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: 12),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 18, color: cs.onPrimary),
              const SizedBox(width: AppSpacing.sm),
              Flexible(
                child: Text(
                  label,
                  style: tt.labelLarge?.copyWith(color: cs.onPrimary, fontWeight: FontWeight.w900),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RoundIconButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;

  const _RoundIconButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Material(
      color: cs.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(999),
        side: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.65)),
      ),
      child: IconButton(
        tooltip: tooltip,
        onPressed: onPressed,
        splashRadius: 22,
        icon: Icon(icon, color: cs.onSurface),
      ),
    );
  }
}

class _RadiusLocationButton extends StatelessWidget {
  final int radiusKm;
  final bool isLoading;
  final bool isActive;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  const _RadiusLocationButton({
    required this.radiusKm,
    required this.isLoading,
    required this.isActive,
    required this.onTap,
    required this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final bg = isActive ? cs.primaryContainer : cs.surface;
    final fg = isActive ? cs.onPrimaryContainer : cs.onSurface;

    return Semantics(
      button: true,
      label: 'Recherche à proximité: $radiusKm km',
      hint: 'Appuyez pour chercher autour de vous. Appui long pour changer le rayon.',
      child: Material(
        color: bg,
        borderRadius: BorderRadius.circular(999),
        child: InkWell(
          onTap: isLoading ? null : onTap,
          onLongPress: isLoading ? null : onLongPress,
          splashFactory: NoSplash.splashFactory,
          highlightColor: Colors.transparent,
          borderRadius: BorderRadius.circular(999),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (isLoading)
                  SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2.2, color: fg))
                else
                  Icon(Icons.gps_fixed, size: 20, color: fg),
                const SizedBox(width: 10),
                Text('$radiusKm km', style: tt.labelLarge?.copyWith(color: fg, fontWeight: FontWeight.w900)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _FilterPillButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isActive;
  final VoidCallback onPressed;

  const _FilterPillButton({
    required this.icon,
    required this.label,
    required this.isActive,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final bg = isActive ? cs.primaryContainer : cs.surface;
    final fg = isActive ? cs.onPrimaryContainer : cs.onSurface;

    return Material(
      color: bg,
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        onTap: onPressed,
        splashFactory: NoSplash.splashFactory,
        highlightColor: Colors.transparent,
        borderRadius: BorderRadius.circular(999),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: 12),
          child: Row(
            children: [
              Icon(icon, size: 18, color: fg),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  label,
                  style: tt.labelLarge?.copyWith(color: fg, fontWeight: FontWeight.w700),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Icon(Icons.expand_more, size: 18, color: fg.withValues(alpha: 0.9)),
            ],
          ),
        ),
      ),
    );
  }
}

class _PrimarySoftButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onPressed;

  const _PrimarySoftButton({
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return Material(
      color: cs.surfaceContainerHighest.withValues(alpha: 0.38),
      borderRadius: BorderRadius.circular(AppRadius.lg),
      child: InkWell(
        onTap: onPressed,
        splashFactory: NoSplash.splashFactory,
        highlightColor: Colors.transparent,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: 12),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 18, color: cs.primary),
              const SizedBox(width: AppSpacing.sm),
              Flexible(
                child: Text(
                  label,
                  style: tt.labelLarge?.copyWith(color: cs.onSurface, fontWeight: FontWeight.w800),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PrimarySolidButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onPressed;

  const _PrimarySolidButton({
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return Material(
      color: cs.primary,
      borderRadius: BorderRadius.circular(AppRadius.lg),
      child: InkWell(
        onTap: onPressed,
        splashFactory: NoSplash.splashFactory,
        highlightColor: Colors.transparent,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: 12),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 18, color: cs.onPrimary),
              const SizedBox(width: AppSpacing.sm),
              Flexible(
                child: Text(
                  label,
                  style: tt.labelLarge?.copyWith(color: cs.onPrimary, fontWeight: FontWeight.w900),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PickerTile extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _PickerTile({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return Material(
      color: selected ? cs.primaryContainer : cs.surface,
      borderRadius: BorderRadius.circular(AppRadius.lg),
      child: InkWell(
        onTap: onTap,
        splashFactory: NoSplash.splashFactory,
        highlightColor: Colors.transparent,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: AppSpacing.md),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  style: tt.bodyMedium?.copyWith(
                    color: selected ? cs.onPrimaryContainer : cs.onSurface,
                    fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                  ),
                ),
              ),
              if (selected) Icon(Icons.check, color: cs.onPrimaryContainer, size: 18),
            ],
          ),
        ),
      ),
    );
  }
}

class _InlineErrorCard extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const _InlineErrorCard({
    required this.message,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return Container(
      padding: AppSpacing.paddingLg,
      decoration: BoxDecoration(
        color: cs.errorContainer,
        borderRadius: BorderRadius.circular(AppRadius.xl),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Erreur', style: tt.titleSmall?.copyWith(color: cs.onErrorContainer, fontWeight: FontWeight.w900)),
          const SizedBox(height: AppSpacing.xs),
          Text(message, style: tt.bodySmall?.copyWith(color: cs.onErrorContainer, height: 1.3)),
          const SizedBox(height: AppSpacing.md),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: onRetry,
              style: TextButton.styleFrom(foregroundColor: cs.onErrorContainer),
              child: const Text('Réessayer'),
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyMerchantsState extends StatelessWidget {
  final String cityQuery;
  final String? selectedCategory;
  final VoidCallback onClear;

  const _EmptyMerchantsState({
    required this.cityQuery,
    required this.selectedCategory,
    required this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final hasFilters = cityQuery.trim().isNotEmpty || selectedCategory != null;

    return Container(
      padding: AppSpacing.paddingLg,
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(AppRadius.xl),
        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.6)),
      ),
      child: Column(
        children: [
          Icon(Icons.storefront_outlined, color: cs.onSurfaceVariant, size: 30),
          const SizedBox(height: AppSpacing.sm),
          Text(
            'Aucun commerçant trouvé',
            style: tt.titleSmall?.copyWith(fontWeight: FontWeight.w900),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            hasFilters ? 'Essayez de modifier vos filtres.' : 'Aucun commerçant approuvé pour le moment.',
            style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant, height: 1.3),
            textAlign: TextAlign.center,
          ),
          if (hasFilters) ...[
            const SizedBox(height: AppSpacing.md),
            TextButton(
              onPressed: onClear,
              style: TextButton.styleFrom(foregroundColor: cs.primary),
              child: const Text('Effacer les filtres'),
            ),
          ],
        ],
      ),
    );
  }
}
