import 'package:flutter/material.dart';

/// Semantic colors that Material's ColorScheme has no slot for. Read them with
/// `AppColors.of(context)` so they follow the active theme.
@immutable
class AppColors extends ThemeExtension<AppColors> {
  const AppColors({
    required this.success,
    required this.warning,
    required this.info,
  });

  final Color success;
  final Color warning;
  final Color info;

  static AppColors of(BuildContext context) =>
      Theme.of(context).extension<AppColors>()!;

  @override
  AppColors copyWith({Color? success, Color? warning, Color? info}) =>
      AppColors(
        success: success ?? this.success,
        warning: warning ?? this.warning,
        info: info ?? this.info,
      );

  @override
  AppColors lerp(ThemeExtension<AppColors>? other, double t) {
    if (other is! AppColors) return this;
    return AppColors(
      success: Color.lerp(success, other.success, t)!,
      warning: Color.lerp(warning, other.warning, t)!,
      info: Color.lerp(info, other.info, t)!,
    );
  }
}

/// Central theme configuration. Light = Lilac, Dark = Midnight Blue.
/// Widgets should read colors from `Theme.of(context).colorScheme` or
/// `AppColors.of(context)` instead of using literal color values.
class AppTheme {
  AppTheme._();

  // ---- Light: Lilac -------------------------------------------------------
  static const ColorScheme _lightScheme = ColorScheme(
    brightness: Brightness.light,
    primary: Color(0xFF7B5CC4), // lilac accent (white text: ~5:1 contrast)
    onPrimary: Color(0xFFFFFFFF),
    primaryContainer: Color(0xFFEADFFC),
    onPrimaryContainer: Color(0xFF2E1B5E),
    secondary: Color(0xFF5B4B86),
    onSecondary: Color(0xFFFFFFFF),
    secondaryContainer: Color(0xFFE6DCFA),
    onSecondaryContainer: Color(0xFF2B2150),
    error: Color(0xFFC62828),
    onError: Color(0xFFFFFFFF),
    errorContainer: Color(0xFFFDE0DE),
    onErrorContainer: Color(0xFF5C1111),
    surface: Color(0xFFFFFFFF),
    onSurface: Color(0xFF1C1B2E),
    onSurfaceVariant: Color(0xFF5A5670),
    outline: Color(0xFF8A85A0),
    outlineVariant: Color(0xFFE4DEF0),
    surfaceTint: Colors.transparent,
    surfaceContainerLowest: Color(0xFFFFFFFF),
    surfaceContainerLow: Color(0xFFF8F6FC),
    surfaceContainer: Color(0xFFF3EFFA),
    surfaceContainerHigh: Color(0xFFEDE8F7),
    surfaceContainerHighest: Color(0xFFE7E1F3),
    inverseSurface: Color(0xFF2E2A45),
    onInverseSurface: Color(0xFFF3EFFA),
    inversePrimary: Color(0xFFCDB8F8),
    shadow: Color(0xFF000000),
    scrim: Color(0xFF000000),
  );

  // ---- Dark: Midnight Blue ------------------------------------------------
  static const ColorScheme _darkScheme = ColorScheme(
    brightness: Brightness.dark,
    primary: Color(0xFFCDB8F8), // lilac accent on midnight blue
    onPrimary: Color(0xFF2B1A5C),
    primaryContainer: Color(0xFF47338A),
    onPrimaryContainer: Color(0xFFEADDFF),
    secondary: Color(0xFFB9ADD9),
    onSecondary: Color(0xFF2B2150),
    secondaryContainer: Color(0xFF2B3470),
    onSecondaryContainer: Color(0xFFDDE1FF),
    error: Color(0xFFFF8A80),
    onError: Color(0xFF3B0A0A),
    errorContainer: Color(0xFF5C1A1A),
    onErrorContainer: Color(0xFFFFDAD6),
    surface: Color(0xFF121B3D),
    onSurface: Color(0xFFE6E9F8),
    onSurfaceVariant: Color(0xFFB4B9D6),
    outline: Color(0xFF7C84A8),
    outlineVariant: Color(0xFF283159),
    surfaceTint: Colors.transparent,
    surfaceContainerLowest: Color(0xFF070D20),
    surfaceContainerLow: Color(0xFF0F1736),
    surfaceContainer: Color(0xFF151F45),
    surfaceContainerHigh: Color(0xFF1B2754),
    surfaceContainerHighest: Color(0xFF222F63),
    inverseSurface: Color(0xFFE6E9F8),
    onInverseSurface: Color(0xFF121B3D),
    inversePrimary: Color(0xFF7B5CC4),
    shadow: Color(0xFF000000),
    scrim: Color(0xFF000000),
  );

  static final ThemeData light = _build(
    _lightScheme,
    scaffold: const Color(0xFFF8F6FC),
    extra: const AppColors(
      success: Color(0xFF18803A),
      warning: Color(0xFFB45309),
      info: Color(0xFF2563EB),
    ),
  );

  static final ThemeData dark = _build(
    _darkScheme,
    scaffold: const Color(0xFF0A1128), // midnight blue
    extra: const AppColors(
      success: Color(0xFF6EE7A0),
      warning: Color(0xFFFBBF24),
      info: Color(0xFF8DB4FF),
    ),
  );

  static ThemeData _build(
    ColorScheme cs, {
    required Color scaffold,
    required AppColors extra,
  }) {
    OutlineInputBorder border(Color color, [double width = 1]) =>
        OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: color, width: width),
        );

    final buttonShape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(8),
    );

    return ThemeData(
      useMaterial3: true,
      brightness: cs.brightness,
      colorScheme: cs,
      scaffoldBackgroundColor: scaffold,
      extensions: <ThemeExtension<dynamic>>[extra],
      appBarTheme: AppBarTheme(
        backgroundColor: cs.primary,
        foregroundColor: cs.onPrimary,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: cs.surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: cs.outlineVariant, width: 1),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: cs.surfaceContainerHigh,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 12,
        ),
        labelStyle: TextStyle(color: cs.onSurfaceVariant),
        hintStyle: TextStyle(color: cs.onSurfaceVariant),
        border: border(cs.outlineVariant),
        enabledBorder: border(cs.outlineVariant),
        focusedBorder: border(cs.primary, 1.5),
        errorBorder: border(cs.error),
        focusedErrorBorder: border(cs.error, 1.5),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: cs.primary,
          foregroundColor: cs.onPrimary,
          elevation: 0,
          shape: buttonShape,
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: cs.primary,
          foregroundColor: cs.onPrimary,
          shape: buttonShape,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: cs.primary,
          side: BorderSide(color: cs.outline),
          shape: buttonShape,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(foregroundColor: cs.primary),
      ),
      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        type: BottomNavigationBarType.fixed,
        backgroundColor: cs.surface,
        elevation: 0,
        selectedItemColor: cs.primary,
        unselectedItemColor: cs.onSurfaceVariant,
        selectedLabelStyle: const TextStyle(
          fontWeight: FontWeight.w600,
          fontSize: 12,
        ),
        unselectedLabelStyle: const TextStyle(
          fontWeight: FontWeight.w500,
          fontSize: 12,
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: cs.surfaceContainerHigh,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        titleTextStyle: TextStyle(
          color: cs.onSurface,
          fontSize: 16,
          fontWeight: FontWeight.bold,
        ),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: cs.surface,
        surfaceTintColor: Colors.transparent,
        showDragHandle: true,
        dragHandleColor: cs.outlineVariant,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
      ),
      checkboxTheme: CheckboxThemeData(
        fillColor: WidgetStateProperty.resolveWith(
          (states) =>
              states.contains(WidgetState.selected) ? cs.primary : null,
        ),
        checkColor: WidgetStatePropertyAll(cs.onPrimary),
        side: BorderSide(color: cs.outline, width: 1.5),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: cs.primaryContainer,
        labelStyle: TextStyle(color: cs.onPrimaryContainer),
        side: BorderSide.none,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
      dividerTheme: DividerThemeData(color: cs.outlineVariant, thickness: 1),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: cs.inverseSurface,
        contentTextStyle: TextStyle(color: cs.onInverseSurface),
        actionTextColor: cs.inversePrimary,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: cs.surfaceContainerHigh,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      textSelectionTheme: TextSelectionThemeData(cursorColor: cs.primary),
    );
  }
}
