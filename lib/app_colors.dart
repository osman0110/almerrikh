import 'package:flutter/material.dart';


class AppColors {
  // ── Core backgrounds ─────────────────────────────────────────────
  static const background  = Color(0xff08090F);   // deep premium dark
  static const foreground  = Color(0xffF5F5FF);   // crisp white
  static const surface2    = Color(0xff100F18);   // elevated surface
  static const card        = Color(0xff0D0C15);   // card background
  static const hero        = Color(0xff08090F);   // same as background
  static const hero2       = Color(0xff130D1A);   // slightly lighter dark

  // ── Al Merrikh Red – primary accent ──────────────────────────────
  static const primary     = Color(0xffCC0A00);   // Al Merrikh signature red
  static const primaryGlow = Color(0xffFF2010);   // bright red for glow/lighting
  static const primarySoft = Color(0xff380A08);   // dark red surface tint

  // ── Gold – premium secondary accent ──────────────────────────────
  static const gold        = Color(0xffC9A84C);   // subtle gold highlights
  static const accentGold  = Color(0xffC9A84C);   // alias

  // ── Kept for legacy references that expect accentGreen ───────────
  // (these widgets use it for status/score indicators)
  static const accentGreen = Color(0xffCC0A00);   // remapped to primary red

  // ── Border / muted ───────────────────────────────────────────────
  static const border      = Color(0xff221018);   // dark red-tinted border
  static const muted       = Color(0xff8A8A9A);   // neutral muted text

  // ── Semantic ─────────────────────────────────────────────────────
  static const warning     = Color(0xfff59e0b);   // amber
  static const success     = Color(0xff22C55E);   // green (real success state)
  static const destructive = Color(0xffef4444);   // red error
}
