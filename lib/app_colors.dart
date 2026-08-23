import 'package:flutter/material.dart';

/// Al Merrikh SC Design Tokens — Premium Light Theme
///
/// Identity:
///   Soft Bg        : #F7F5EF
///   White Cards    : #FFFFFF
///   Primary Maroon : #8B0015
///   Dark Maroon    : #4A000D  (hero cards / deep gradients)
///   Premium Gold   : #F6B82E  (CTAs, active states only)
///   Text Primary   : #171717
///   Text Secondary : #7A7D85
class AppColors {
  // ── Backgrounds ────────────────────────────────────────────────────────────
  static const background  = Color(0xFFF8F7F6); // design soft off-white
  static const surface2    = Color(0xFFECE9E7); // slightly darker surface
  static const card        = Color(0xFFFFFFFF); // white cards
  static const hero        = Color(0xFF8A001C); // maroon — hero card bg

  // ── Text ──────────────────────────────────────────────────────────────────
  static const foreground  = Color(0xFF161616); // text primary
  static const textSoft    = Color(0xFF374151); // secondary dark
  static const muted       = Color(0xFF858891); // text secondary / muted
  static const onDark      = Color(0xFFFFFFFF); // white text on dark surfaces
  static const onDarkMuted = Color(0xFFE2C477); // gold-tinted text on maroon

  // ── Text (spec-named aliases) ─────────────────────────────────────────────
  static const textPrimary   = Color(0xFF161616); // alias for foreground
  static const textSecondary = Color(0xFF858891); // alias for muted

  // ── Borders ───────────────────────────────────────────────────────────────
  static const border      = Color(0xFFEDEAE8); // clean light border

  // ── Premium Gold — primary accent ─────────────────────────────────────────
  static const primary     = Color(0xFFC8A34D); // gold (CTAs, active states)
  static const primarySoft = Color(0xFFF7E9ED); // light maroon/gold tint for bg

  // ── Maroon brand ─────────────────────────────────────────────────────────
  static const maroon      = Color(0xFF8A001C); // Al Merrikh primary maroon
  static const maroonDark  = Color(0xFF580012); // deep dark maroon (gradient end)
  static const gold        = Color(0xFFC8A34D); // alias for primary

  // ── Semantic status ───────────────────────────────────────────────────────
  static const success     = Color(0xFF3D9A5C);
  static const warning     = Color(0xFFE3A127);
  static const destructive = Color(0xFF8A001C);
  static const danger      = Color(0xFF8A001C); // alias for destructive
  static const disabled    = Color(0xFFEEECE7);
  static const risk        = Color(0xFFC0392B); // high-risk status

  // ── Role accents ──────────────────────────────────────────────────────────
  static const coachAccent  = Color(0xFFC8A34D); // gold — club
  static const playerAccent = Color(0xFF7C3AED); // purple — player
  static const parentAccent = Color(0xFF1A6BEB); // blue — parent

  // ── Legacy aliases (backward compat — do NOT remove) ─────────────────────
  static const text         = Color(0xFF161616); // alias for foreground
  static const hero2        = Color(0xFF8A001C); // alias for hero
  static const primaryGlow  = Color(0xFFC8A34D);
  static const accentGreen  = Color(0xFF3D9A5C);
  static const accentGold   = Color(0xFFC8A34D);
}
