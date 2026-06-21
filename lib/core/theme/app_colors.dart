import 'package:flutter/material.dart';

class AppColors {
  // Fintech Primary - Brand purple accent (per latest Home mock)
  // Light: #8B5CF6 (lavender purple)
  // Dark:  keep same hue family with deeper shade.
  static const primary = Color(0xFF8B5CF6);
  static const primaryDark = Color(0xFF5B2EDB);
  static const primaryLight = Color(0xFFA78BFA);
  
  // Accent - Warm coral for CTAs and important actions
  static const accent = Color(0xFFFF6B6B);
  static const accentDark = Color(0xFFE85555);
  static const accentLight = Color(0xFFFF8A8A);
  
  // Aliases
  static const secondary = accent;
  static const tertiary = success;
  
  // Success - Green for positive transactions
  static const success = Color(0xFF06D6A0);
  static const successDark = Color(0xFF05B589);

  /// Brand purple used for the “Money” part of the wordmark and header icons.
  /// Intentionally constant across light/dark mode.
  static const brandPurple = primary;
  
  // Warning - Amber for pending states
  static const warning = Color(0xFFFFC107);
  static const warningDark = Color(0xFFF57C00);
  
  // Error - Red for failed transactions
  static const error = Color(0xFFEF476F);
  static const errorDark = Color(0xFFD93A5C);
  
  // Light Mode
  // Slightly tinted neutral to harmonize with the new lavender/sky background.
  static const lightBackground = Color(0xFFF6F4FF);
  static const lightSurface = Color(0xFFFFFFFF);
  static const lightSurfaceVariant = Color(0xFFF2F2FF);
  static const lightOnSurface = Color(0xFF1A1A1A);
  static const lightOnSurfaceVariant = Color(0xFF5F6368);
  static const lightBorder = Color(0xFFE5E3FF);
  
  // Dark Mode
  // Dark neutral (per provided dark-mode background sample).
  // Keep surfaces slightly lighter than background for elevation-free separation.
  static const darkBackground = Color(0xFF1C1C1C);
  static const darkSurface = Color(0xFF232323);
  static const darkSurfaceVariant = Color(0xFF2A2A2A);
  static const darkOnSurface = Color(0xFFE8EAED);
  static const darkOnSurfaceVariant = Color(0xFF9AA0A6);
  static const darkBorder = Color(0xFF3A3A3A);
  
  // Semantic colors
  static const textPrimary = Color(0xFF1A1A1A);
  static const textSecondary = Color(0xFF5F6368);
  static const textHint = Color(0xFF9AA0A6);
  
  // Transaction type colors
  static const transactionSent = Color(0xFFEF476F);
  static const transactionReceived = Color(0xFF06D6A0);
  static const transactionPending = Color(0xFFFFC107);

  // User Home (Balance card) gradients
  // Kept centralized to avoid hardcoding in widgets.
  // NOTE: Keep the ring teal/cyan for a fintech feel (as in the reference),
  // while the app-wide accent (ColorScheme.primary) is purple.
  static const _balanceRingTeal = Color(0xFF00B8A9);
  static const _balanceRingTealLight = Color(0xFF4DD4C7);
  static const _balanceRingTealDark = Color(0xFF008C7E);

  static const balanceCardGradientLight = [_balanceRingTeal, _balanceRingTealLight];
  static const balanceCardGradientDark = [_balanceRingTealDark, _balanceRingTeal];

  // User Home background (soft waves / modern finance feel)
  // These are used to build gradients + decorative blobs for both modes.
  // Light mode matches the provided lavender → sky gradient sample.
  static const homeBgLightTop = Color(0xFF8B5CF6);
  static const homeBgLightBottom = Color(0xFFBFE3FF);

  // Dark mode uses the same hues in darker shades.
  // Dark mode background is a flat neutral (matches provided sample).
  static const homeBgDarkTop = darkBackground;
  static const homeBgDarkBottom = darkBackground;

  static const homeBackgroundGradientLight = [homeBgLightTop, homeBgLightBottom];
  static const homeBackgroundGradientDark = [homeBgDarkTop, homeBgDarkBottom];

  // Decorative tint colors used for background blobs.
  // Keep these background-only tints in the same family as the new gradient.
  static const homeBlobTeal = Color(0xFF58A6FF);
  static const homeBlobMint = Color(0xFF7C5CFF);
  static const homeBlobCoral = Color(0xFFFF6BD6);

  // Transactions (filters) gradients
  // Keep the same API (a gradient list) but make it visually solid purple.
  // This avoids green/teal tones in selected filter buttons.
  /// Selected filter chip color (solid) per latest provided purple sample.
  static const transactionFilterSelectedPurple = Color(0xFFA08CFF);

  static const transactionFilterSelectedGradient = [transactionFilterSelectedPurple, transactionFilterSelectedPurple];

  // Merchant (Home) specific surface colors (for exact mock reuse)
  // Kept here (centralized) to avoid hardcoding in widgets.
  static const merchantHomeBackgroundDark = Color(0xFF071216);
  static const merchantHomeCardDark = Color(0xFF0C1A1F);
  // When the amount field is focused we darken the whole amount card so the
  // “outer” area matches the input fill (per provided mock).
  static const merchantHomeAmountCardFocusedDark = Color(0xFF071B20);

  // Coupon (User Home) category accents
  static const couponFood = accent;
  static const couponTech = primary;
  static const couponServices = success;
  static const couponTransport = warning;
  static const couponShopping = Color(0xFF7C5CFF);
  static const couponHealth = Color(0xFF4D96FF);

  /// Ticket “hole” color used on the User/Home coupon cards.
  ///
  /// Set to match the light periwinkle sample provided by the user.
  static const couponTicketHole = Color(0xFFB0A6FF);

  static const List<Color> _couponPalette = [
    couponFood,
    couponTech,
    couponServices,
    couponTransport,
    couponShopping,
    couponHealth,
  ];

  /// Returns a stable accent color for a coupon category.
  ///
  /// Uses explicit mappings for common categories and falls back to a
  /// deterministic palette pick for unknown categories.
  static Color couponColorForCategory(String category) {
    final c = category.trim().toLowerCase();
    if (c.isEmpty) return couponTech;
    if (c.contains('food') || c.contains('beverage') || c.contains('restaurant')) return couponFood;
    if (c.contains('tech') || c.contains('electronics') || c.contains('digital')) return couponTech;
    if (c.contains('service')) return couponServices;
    if (c.contains('transport') || c.contains('travel') || c.contains('taxi') || c.contains('bus')) return couponTransport;
    if (c.contains('shop') || c.contains('retail') || c.contains('fashion')) return couponShopping;
    if (c.contains('health') || c.contains('pharma') || c.contains('wellness')) return couponHealth;

    final idx = c.hashCode.abs() % _couponPalette.length;
    return _couponPalette[idx];
  }

  /// Icon mapping for coupon categories.
  ///
  /// IMPORTANT: keep this aligned with the iconography used on the User Home
  /// coupon section so the visual identity stays consistent across screens.
  static IconData couponIconForCategory(String category) {
    final c = category.trim().toLowerCase();
    if (c.contains('tech')) return Icons.memory_rounded;
    if (c.contains('service')) return Icons.work_outline_rounded;
    if (c.contains('food') || c.contains('restaurant')) return Icons.restaurant_rounded;
    if (c.contains('transport')) return Icons.directions_bus_rounded;
    return Icons.local_offer_rounded;
  }
}
