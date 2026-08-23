/// Minimal spacing / sizing tokens for Club MVP screens.
/// Use these instead of magic numbers for consistent layout.
abstract class ClubUiTokens {
  static const double spacingXs    =  4.0;
  static const double spacingSm    =  8.0;
  static const double spacingMd    = 12.0;
  static const double spacingLg    = 16.0;
  static const double spacingXl    = 24.0;
  static const double radiusMd     = 12.0;
  static const double radiusLg     = 16.0;
  static const double radiusXl     = 20.0;
  /// Minimum touch target size — all interactive icons must be at least this.
  static const double minTapTarget = 44.0;

  // ── Layout constants (design unification) ─────────────────────────────────
  static const double cardRadius           = 20.0; // alias for radiusXl
  static const double buttonRadius         = 14.0;
  static const double pageHorizontalPadding = 20.0;
  static const double sectionSpacing       = 24.0; // alias for spacingXl
  static const double primaryButtonHeight  = 54.0;
  static const double cardBorderWidth      = 1.0;
}
