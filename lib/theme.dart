import 'package:flutter/material.dart';

/// The app's colours. Each one has a light and a dark value; [dark] picks which, and the app redraws when it
/// changes. [ink] is for words and lines, [solid] for dark buttons and bars that carry white words, and
/// [surface] for cards and sheets. The dark look is a soft off-black with off-white words, never pure black.
class Palette {
  const Palette._();

  static bool dark = false;

  static Color _pick(int light, int night) => Color(dark ? night : light);

  static Color get canvas => _pick(0xFFF7F7F5, 0xFF171A18);
  static Color get surface => _pick(0xFFFFFFFF, 0xFF212522);
  static Color get stone => _pick(0xFFEDEDE9, 0xFF2B2F2C);
  static Color get line => _pick(0xFFE4E4DF, 0xFF343935);
  static Color get ink => _pick(0xFF0B0B0C, 0xFFEDEBE6);
  static Color get inkSoft => _pick(0xFF2B2925, 0xFFD8D5CD);
  static Color get body => _pick(0xFF3C3C38, 0xFFC9C6BC);
  static Color get muted => _pick(0xFF6E6E68, 0xFF9A978F);
  static Color get quiet => _pick(0xFFA3A39E, 0xFF6F6D67);
  static Color get solid => _pick(0xFF0B0B0C, 0xFF363C38);
  static Color get green => _pick(0xFF1F6B4A, 0xFF3E9C72);
  static Color get greenDeep => _pick(0xFF174F37, 0xFF2E7D59);
  static Color get greenSoft => _pick(0xFFE6EFE9, 0xFF1C2E25);
  static Color get gold => _pick(0xFFC9A86A, 0xFFC9A86A);
  static Color get goldLight => _pick(0xFFE3CF9F, 0xFFE3CF9F);
  static Color get bad => _pick(0xFF9A3412, 0xFFE07A52);
  static Color get badSoft => _pick(0xFFFBEAE3, 0xFF3A2119);

  /// Words on white pills that sit on dark bars, which stay white in both looks.
  static const onWhite = Color(0xFF0B0B0C);

  /// The brand green exactly, for the share card, which looks the same in both looks.
  static const brandGreenDeep = Color(0xFF174F37);
}

class AppTheme {
  const AppTheme._();

  static const sans = 'InstrumentSans';
  static const arabic = 'Amiri';

  static ThemeData build() {
    final scheme = ColorScheme.fromSeed(seedColor: Palette.green, primary: Palette.green, secondary: Palette.gold, surface: Palette.surface, error: Palette.bad, brightness: Palette.dark ? Brightness.dark : Brightness.light);
    final base = ThemeData(useMaterial3: true, colorScheme: scheme, fontFamily: sans, fontFamilyFallback: const [arabic], scaffoldBackgroundColor: Palette.canvas);
    final text = base.textTheme.apply(bodyColor: Palette.ink, displayColor: Palette.ink);
    return base.copyWith(
      textTheme: text.copyWith(
        displaySmall: TextStyle(fontFamily: sans, fontSize: 34, height: 0.95, letterSpacing: -1.5, fontWeight: FontWeight.w500, color: Palette.ink),
        headlineSmall: TextStyle(fontFamily: sans, fontSize: 22, height: 1.1, letterSpacing: -0.8, fontWeight: FontWeight.w500, color: Palette.ink),
        titleMedium: TextStyle(fontFamily: sans, fontSize: 15, height: 1.25, fontWeight: FontWeight.w600, color: Palette.ink),
        bodyMedium: TextStyle(fontSize: 14, height: 1.55, color: Palette.body),
        bodySmall: TextStyle(fontSize: 12, height: 1.45, color: Palette.muted),
        labelLarge: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
      ),
      appBarTheme: AppBarTheme(backgroundColor: Palette.canvas, surfaceTintColor: Colors.transparent, foregroundColor: Palette.ink, elevation: 0),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Palette.surface,
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
        hintStyle: TextStyle(color: Palette.quiet, fontSize: 14),
        labelStyle: TextStyle(color: Palette.muted, fontSize: 14),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: Palette.line)),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: Palette.line)),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: Palette.green, width: 1.4)),
        errorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: Palette.bad)),
        focusedErrorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: Palette.bad, width: 1.4)),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(color: Palette.green),
      snackBarTheme: SnackBarThemeData(behavior: SnackBarBehavior.floating, backgroundColor: Palette.solid),
      dividerTheme: DividerThemeData(color: Palette.line, thickness: 1, space: 1),
    );
  }
}
