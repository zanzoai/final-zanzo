// lib/core/theme/app_theme.dart
//
// Zanzo's single source of visual truth.
//
// Design thesis: Zanzo is a *voice-first concierge*, not a service grid.
// The language is warm, human and tactile — cream ground, brown ink, a living
// saffron accent — deliberately NOT the cold-blue SaaS look of every other
// errand app. Every colour, radius, space and shadow the UI uses should come
// from here so the identity is applied once, not copy-pasted per screen.
//
// Adopt in a widget with:  `import 'package:zanzo_frontend/core/theme/app_theme.dart';`
// then reference e.g. `AppColors.saffron`, `AppRadii.card`, `AppSpacing.lg`,
// `AppText.hero`, `AppShadows.lifted(t)`.

import 'package:flutter/material.dart';

// ===========================================================================
// COLOURS
// ===========================================================================

/// The Zanzo palette. Warm, human, tactile — never generic-blue SaaS.
abstract final class AppColors {
  // ── Ground & surfaces ────────────────────────────────────────────────────
  /// Warm cream page ground. Kept in sync with the native splash (#FCFAF6).
  static const ground = Color(0xFFFCFAF6);

  /// Bright top of a lifted card gradient.
  static const surface = Color(0xFFFFFFFF);

  /// Warm-tinted base of a lifted card gradient — reads as paper, not glass.
  static const surfaceWarm = Color(0xFFFEFBF6);

  /// Muted warm surface for pills, badges and inset chips.
  static const surfaceMuted = Color(0xFFF5F2EE);

  /// Hairline divider on warm surfaces (previously the drifting #E8E2D9).
  static const divider = Color(0xFFE8E2D9);

  /// Slightly cooler warm surface used for the "crew on the way" banner.
  static const surfaceWarmAlt = Color(0xFFFFFBF3);

  // ── Ink ──────────────────────────────────────────────────────────────────
  /// Primary text — warm dark brown, not cold charcoal.
  static const ink = Color(0xFF3B2A1E);

  /// Secondary text / icons — warm taupe, not neutral grey.
  static const muted = Color(0xFF8C7B6E);

  // ── Brand ────────────────────────────────────────────────────────────────
  /// The signature saffron. The one colour that should feel *alive*.
  static const saffron = Color(0xFFE8720C);

  /// A deeper saffron for pressed states and gradient ends.
  static const saffronDeep = Color(0xFFC85D08);

  // ── Semantic ─────────────────────────────────────────────────────────────
  static const success = Color(0xFF4ADE80); // live/active dot
  static const successInk = Color(0xFF16A34A); // text on success tint
  static const successBg = Color(0xFFE8F5E9); // completed tint fill
  static const warning = Color(0xFFF59E0B); // amber — in-progress
  static const warningBg = Color(0xFFFFF3E9); // in-progress tint fill
  static const danger = Color(0xFFDC2626);

  // ── Incidental accents (previously drifting literals) ────────────────────
  /// Soft parcel/receipt tint used on task chips.
  static const parcelTint = Color(0xFFF3E2D2);

  /// Ink used on top of [parcelTint].
  static const parcelInk = Color(0xFF6B4226);

  // ── Hairlines & tints (opacity-driven, derived from ink/saffron) ─────────
  static Color hairline([double alpha = 0.10]) => ink.withValues(alpha: alpha);
  static Color saffronTint([double alpha = 0.10]) =>
      saffron.withValues(alpha: alpha);
  static Color successTint([double alpha = 0.18]) =>
      success.withValues(alpha: alpha);
}

// ===========================================================================
// RADII — squircle scale (matches iOS superellipse curvature intent)
// ===========================================================================

abstract final class AppRadii {
  static const chip = 12.0;
  static const banner = 18.0;
  static const card = 26.0; // the hero input card
  static const pill = 999.0; // fully rounded (segmented pill, avatar ring)

  static BorderRadius get chipR => BorderRadius.circular(chip);
  static BorderRadius get bannerR => BorderRadius.circular(banner);
  static BorderRadius get cardR => BorderRadius.circular(card);
  static BorderRadius get pillR => BorderRadius.circular(pill);
}

// ===========================================================================
// SPACING — 4pt-based scale
// ===========================================================================

abstract final class AppSpacing {
  static const xs = 4.0;
  static const sm = 8.0;
  static const md = 14.0;
  static const lg = 22.0; // default screen horizontal gutter
  static const xl = 32.0;
}

// ===========================================================================
// TYPOGRAPHY — one scale, warm and characterful
// ===========================================================================
//
// Body/UI stays on the platform default (SF Pro on iOS) so it feels native.
// The wordmark and hero carry the brand voice with tighter tracking.

abstract final class AppText {
  static const wordmark = TextStyle(
    fontSize: 30,
    fontWeight: FontWeight.w700,
    color: AppColors.saffron,
    letterSpacing: -0.5,
  );

  static const hero = TextStyle(
    fontWeight: FontWeight.w600,
    height: 1.0,
    letterSpacing: -0.5,
  );

  static const subtitle = TextStyle(
    color: AppColors.muted,
    fontWeight: FontWeight.w400,
    height: 1.4,
  );

  static const body = TextStyle(
    color: AppColors.ink,
    fontSize: 15,
    height: 1.4,
  );

  static const label = TextStyle(
    color: AppColors.ink,
    fontSize: 13,
    fontWeight: FontWeight.w600,
    letterSpacing: -0.2,
  );

  static const caption = TextStyle(
    color: AppColors.muted,
    fontSize: 11.5,
  );
}

// ===========================================================================
// GRADIENTS
// ===========================================================================

abstract final class AppGradients {
  /// Softly-lifted card surface: bright white top drifting to warm paper base.
  static const liftedCard = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [AppColors.surface, AppColors.surfaceWarm],
  );

  /// The living saffron of the send / voice affordance.
  static const saffronAction = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [AppColors.saffron, AppColors.saffronDeep],
  );
}

// ===========================================================================
// SHADOWS — animated "breathing" lift used on the hero surface
// ===========================================================================

abstract final class AppShadows {
  /// Depth + warm saffron ambient glow. [t] (0..1) drives the breathing pulse.
  static List<BoxShadow> lifted(double t) => [
    BoxShadow(
      color: Colors.black.withValues(alpha: 0.08 + t * 0.04),
      blurRadius: 36 + 10 * t,
      offset: Offset(0, 12 + 3 * t),
    ),
    BoxShadow(
      color: AppColors.saffron.withValues(alpha: 0.04 + t * 0.03),
      blurRadius: 48,
      offset: const Offset(0, 10),
    ),
  ];
}

// ===========================================================================
// THEME DATA
// ===========================================================================

abstract final class AppTheme {
  static ThemeData get light {
    final scheme =
        ColorScheme.fromSeed(
          seedColor: AppColors.saffron,
          brightness: Brightness.light,
        ).copyWith(
          primary: AppColors.saffron,
          onPrimary: Colors.white,
          surface: AppColors.surface,
          onSurface: AppColors.ink,
        );

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: AppColors.ground,
      // Keep the platform default font so UI feels native (SF Pro on iOS).
      appBarTheme: const AppBarTheme(
        elevation: 0,
        backgroundColor: AppColors.ground,
        foregroundColor: AppColors.ink,
        surfaceTintColor: Colors.transparent,
      ),
      textSelectionTheme: const TextSelectionThemeData(
        cursorColor: AppColors.saffron,
        selectionHandleColor: AppColors.saffron,
      ),
    );
  }
}
