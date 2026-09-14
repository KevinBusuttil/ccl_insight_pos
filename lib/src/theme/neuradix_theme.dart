import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../features/pos/pos_models.dart';

class NeuradixTheme {
  static ThemeData light({
    PosThemePalette palette = const PosThemePalette.fallback(),
  }) {
    final primary = _fromHex(palette.primary);
    final secondary = _fromHex(palette.secondary);
    final accent = _fromHex(palette.accent);
    final textAndCancelIcon = _fromHex(palette.textAndCancelIcon);
    final shadowBorder = _fromHex(palette.shadowBorder);
    final hintText = _fromHex(palette.hintText);
    final fontWhiteColor = _fromHex(palette.fontWhiteColor);
    final parkOrderButton = _fromHex(palette.parkOrderButton);
    final surface = _fromHex(palette.surface);
    final active = _fromHex(palette.active);
    final textOnPrimary = _fromHex(palette.textOnPrimary);
    final base = ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.light(
        primary: primary,
        secondary: secondary,
        surface: surface,
        onPrimary: textOnPrimary,
        outline: shadowBorder,
      ),
    );

    return base.copyWith(
      scaffoldBackgroundColor: active,
      textTheme: GoogleFonts.nunitoSansTextTheme(base.textTheme).copyWith(
        displaySmall: GoogleFonts.poppins(
          color: primary,
          fontSize: 34,
          fontWeight: FontWeight.w700,
          height: 1.05,
        ),
        headlineMedium: GoogleFonts.poppins(
          color: primary,
          fontWeight: FontWeight.w700,
          fontSize: 24,
        ),
        titleLarge: GoogleFonts.poppins(
          color: primary,
          fontWeight: FontWeight.w700,
          fontSize: 18,
        ),
        bodyLarge: GoogleFonts.nunitoSans(
          color: textAndCancelIcon.withValues(alpha: 0.86),
          fontSize: 16,
          height: 1.35,
        ),
        bodyMedium: GoogleFonts.nunitoSans(
          color: textAndCancelIcon.withValues(alpha: 0.72),
          fontSize: 14,
        ),
        labelLarge: GoogleFonts.nunitoSans(
          color: primary,
          fontWeight: FontWeight.w700,
          fontSize: 13,
        ),
      ),
      cardTheme: CardTheme(
        color: Colors.white,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: BorderSide(color: shadowBorder),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: primary,
          foregroundColor: textOnPrimary,
          textStyle: GoogleFonts.nunitoSans(
            fontWeight: FontWeight.w700,
            fontSize: 15,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: primary,
          side: BorderSide(color: shadowBorder),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          textStyle: GoogleFonts.nunitoSans(fontWeight: FontWeight.w700),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 14,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: shadowBorder),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: shadowBorder),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: primary, width: 1.4),
        ),
      ),
      dividerTheme: DividerThemeData(color: shadowBorder, thickness: 1),
      chipTheme: base.chipTheme.copyWith(
        backgroundColor: active,
        selectedColor: primary,
        side: BorderSide(color: shadowBorder),
        labelStyle: GoogleFonts.nunitoSans(
          color: textAndCancelIcon.withValues(alpha: 0.75),
          fontWeight: FontWeight.w600,
        ),
      ),
      iconTheme: IconThemeData(color: accent),
      progressIndicatorTheme: ProgressIndicatorThemeData(color: primary),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: parkOrderButton,
        contentTextStyle: GoogleFonts.nunitoSans(
          color: fontWhiteColor,
          fontWeight: FontWeight.w600,
        ),
      ),
      canvasColor: hintText,
    );
  }

  static Color _fromHex(String hex) {
    final sanitized = hex.replaceFirst('#', '').padLeft(8, 'F');
    return Color(int.parse(sanitized, radix: 16));
  }
}
