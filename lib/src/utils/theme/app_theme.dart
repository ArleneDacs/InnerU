import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:selfcare_projects/src/services/company_theme_service.dart';

/// InnerU design system — single source of truth for colors, radii and
/// component styling so every screen looks consistent.
class AppColors {
  AppColors._();

  static const Color primary = Color(0xFF59BDB3);
  static const Color primaryDark = Color(0xFF3E9189);
  static const Color primaryDeep = Color(0xFF245A55);
  static const Color primarySoft = Color(0xFFE8F6F3);
  static const Color accent = Color(0xFF8ED1B8);

  static const Color background = Color(0xFFF7FAF9);
  static const Color surface = Colors.white;
  static const Color border = Color(0xFFE3EAE8);

  static const Color textPrimary = Color(0xFF1F2933);
  static const Color textSecondary = Color(0xFF6B7A78);

  static const Color danger = Color(0xFFD95555);
  static const Color dangerSoft = Color(0xFFFDECEC);
  static const Color success = Color(0xFF3E9189);
  static const Color warning = Color(0xFFE8A13D);

  static const LinearGradient brandGradient = LinearGradient(
    colors: [primary, accent],
    begin: Alignment.centerLeft,
    end: Alignment.centerRight,
  );

  static const LinearGradient pageGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Color(0xFFF8FBF8), Color(0xFFE9F2EC)],
  );

  static List<BoxShadow> get softShadow => [
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.06),
          blurRadius: 18,
          offset: const Offset(0, 8),
        ),
      ];

  static List<BoxShadow> get cardShadow => [
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.05),
          blurRadius: 24,
          offset: const Offset(0, 12),
        ),
      ];
}

class AppRadius {
  AppRadius._();

  static const double input = 14;
  static const double button = 16;
  static const double card = 20;
  static const double dialog = 24;
  static const double sheet = 28;
}

class AppTheme {
  AppTheme._();

  static ThemeData get light {
    final base = ThemeData(
      useMaterial3: false,
      brightness: Brightness.light,
      scaffoldBackgroundColor: AppColors.background,
      colorScheme: ColorScheme.fromSeed(
        seedColor: AppColors.primary,
        primary: AppColors.primary,
        secondary: AppColors.accent,
        error: AppColors.danger,
        surface: AppColors.surface,
      ),
    );

    return base.copyWith(
      appBarTheme: const AppBarTheme(
        backgroundColor: AppColors.background,
        foregroundColor: AppColors.textPrimary,
        elevation: 0,
        centerTitle: true,
        iconTheme: IconThemeData(color: AppColors.textPrimary),
        titleTextStyle: TextStyle(
          color: AppColors.textPrimary,
          fontSize: 18,
          fontWeight: FontWeight.w700,
        ),
      ),
      textTheme: base.textTheme
          .copyWith(
            titleLarge: GoogleFonts.parisienne(
              fontSize: 40,
              color: AppColors.textPrimary,
            ),
            bodyMedium: GoogleFonts.puritan(color: Colors.black87),
          )
          .apply(
            bodyColor: AppColors.textPrimary,
            displayColor: AppColors.textPrimary,
          ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.surface,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
        labelStyle: const TextStyle(color: AppColors.textSecondary),
        hintStyle: const TextStyle(color: AppColors.textSecondary),
        prefixIconColor: AppColors.textSecondary,
        suffixIconColor: AppColors.textSecondary,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.input),
          borderSide: const BorderSide(color: AppColors.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.input),
          borderSide: const BorderSide(color: AppColors.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.input),
          borderSide: const BorderSide(color: AppColors.primary, width: 1.6),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.input),
          borderSide: const BorderSide(color: AppColors.danger),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.input),
          borderSide: const BorderSide(color: AppColors.danger, width: 1.6),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          disabledBackgroundColor: AppColors.primary.withValues(alpha: 0.45),
          disabledForegroundColor: Colors.white70,
          elevation: 0,
          minimumSize: const Size(64, 50),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.button),
          ),
          textStyle: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.2,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.primaryDark,
          side: const BorderSide(color: AppColors.border),
          backgroundColor: AppColors.surface,
          minimumSize: const Size(64, 50),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.button),
          ),
          textStyle: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: AppColors.primaryDark,
          textStyle: const TextStyle(fontWeight: FontWeight.w600),
        ),
      ),
      cardTheme: CardThemeData(
        color: AppColors.surface,
        elevation: 0,
        margin: const EdgeInsets.symmetric(vertical: 6),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.card),
          side: const BorderSide(color: AppColors.border),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: AppColors.surface,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.dialog),
        ),
        titleTextStyle: const TextStyle(
          color: AppColors.textPrimary,
          fontSize: 19,
          fontWeight: FontWeight.w700,
        ),
        contentTextStyle: const TextStyle(
          color: AppColors.textSecondary,
          fontSize: 14.5,
          height: 1.5,
        ),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: AppColors.surface,
        modalBackgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(
          borderRadius:
              BorderRadius.vertical(top: Radius.circular(AppRadius.sheet)),
        ),
        showDragHandle: true,
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: AppColors.textPrimary,
        contentTextStyle: const TextStyle(color: Colors.white, fontSize: 14),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
        ),
      ),
      checkboxTheme: CheckboxThemeData(
        fillColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? AppColors.primary
              : Colors.transparent,
        ),
        side: const BorderSide(color: AppColors.textSecondary, width: 1.6),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(6),
        ),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? AppColors.primary
              : Colors.grey.shade400,
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? AppColors.primary.withValues(alpha: 0.4)
              : Colors.grey.shade300,
        ),
      ),
      dividerTheme: const DividerThemeData(
        color: AppColors.border,
        thickness: 1,
        space: 1,
      ),
      chipTheme: base.chipTheme.copyWith(
        backgroundColor: AppColors.primarySoft,
        selectedColor: AppColors.primary,
        labelStyle: const TextStyle(color: AppColors.primaryDeep),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide.none,
        ),
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: AppColors.primary,
      ),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        elevation: 2,
      ),
      listTileTheme: ListTileThemeData(
        iconColor: AppColors.primaryDark,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.input),
        ),
      ),
      tabBarTheme: const TabBarThemeData(
        labelColor: AppColors.primaryDark,
        unselectedLabelColor: AppColors.textSecondary,
        indicatorColor: AppColors.primary,
      ),
    );
  }

  static ThemeData get dark {
    final base = ThemeData(
      useMaterial3: false,
      brightness: Brightness.dark,
      colorScheme: ColorScheme.fromSeed(
        seedColor: AppColors.primary,
        brightness: Brightness.dark,
        primary: AppColors.primary,
        secondary: AppColors.accent,
      ),
    );

    return base.copyWith(
      textTheme: base.textTheme.copyWith(
        titleLarge: GoogleFonts.parisienne(fontSize: 40, color: Colors.white),
        bodyMedium: GoogleFonts.puritan(color: Colors.white70),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          elevation: 0,
          minimumSize: const Size(64, 50),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.button),
          ),
          textStyle: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
        ),
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: AppColors.primary,
      ),
    );
  }

  static ThemeData company(CompanyThemeData companyTheme) {
    final base = companyTheme.isDark ? dark : light;
    final brightness = companyTheme.isDark ? Brightness.dark : Brightness.light;
    final onPrimary = companyTheme.primaryColor.computeLuminance() > 0.48
        ? Colors.black
        : Colors.white;
    final outline = companyTheme.isDark
        ? companyTheme.primaryColor.withValues(alpha: 0.28)
        : companyTheme.mutedInkColor.withValues(alpha: 0.22);
    final inputFill = companyTheme.isDark
        ? companyTheme.surfaceColor.withValues(alpha: 0.92)
        : companyTheme.surfaceColor;

    return base.copyWith(
      brightness: brightness,
      scaffoldBackgroundColor: companyTheme.backgroundColor,
      canvasColor: companyTheme.backgroundColor,
      primaryColor: companyTheme.primaryColor,
      colorScheme: ColorScheme.fromSeed(
        seedColor: companyTheme.primaryColor,
        brightness: brightness,
        primary: companyTheme.primaryColor,
        onPrimary: onPrimary,
        secondary: companyTheme.accentColor,
        surface: companyTheme.surfaceColor,
        onSurface: companyTheme.inkColor,
        error: AppColors.danger,
      ),
      appBarTheme: base.appBarTheme.copyWith(
        backgroundColor: companyTheme.surfaceColor,
        foregroundColor: companyTheme.inkColor,
        iconTheme: IconThemeData(color: companyTheme.iconColor),
        actionsIconTheme: IconThemeData(color: companyTheme.iconColor),
        titleTextStyle: TextStyle(
          color: companyTheme.inkColor,
          fontSize: 18,
          fontWeight: FontWeight.w700,
        ),
      ),
      iconTheme: IconThemeData(color: companyTheme.iconColor),
      primaryIconTheme: IconThemeData(color: companyTheme.iconColor),
      textTheme: base.textTheme
          .copyWith(
            titleLarge: GoogleFonts.parisienne(
              fontSize: 40,
              color: companyTheme.inkColor,
            ),
            bodyMedium: GoogleFonts.puritan(color: companyTheme.inkColor),
          )
          .apply(
            bodyColor: companyTheme.inkColor,
            displayColor: companyTheme.inkColor,
          ),
      inputDecorationTheme: base.inputDecorationTheme.copyWith(
        fillColor: inputFill,
        labelStyle: TextStyle(color: companyTheme.mutedInkColor),
        hintStyle: TextStyle(color: companyTheme.mutedInkColor),
        prefixIconColor: companyTheme.iconColor,
        suffixIconColor: companyTheme.iconColor,
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.input),
          borderSide: BorderSide(color: outline),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.input),
          borderSide: BorderSide(color: companyTheme.iconColor, width: 1.6),
        ),
      ),
      dialogTheme: base.dialogTheme.copyWith(
        backgroundColor: companyTheme.surfaceColor,
        titleTextStyle: TextStyle(
          color: companyTheme.inkColor,
          fontSize: 19,
          fontWeight: FontWeight.w700,
        ),
        contentTextStyle: TextStyle(
          color: companyTheme.mutedInkColor,
          fontSize: 14.5,
          height: 1.5,
        ),
      ),
      bottomSheetTheme: base.bottomSheetTheme.copyWith(
        backgroundColor: companyTheme.surfaceColor,
        modalBackgroundColor: companyTheme.surfaceColor,
      ),
      listTileTheme: base.listTileTheme.copyWith(
        textColor: companyTheme.inkColor,
        iconColor: companyTheme.iconColor,
        titleTextStyle: TextStyle(
          color: companyTheme.inkColor,
          fontSize: 15.5,
          fontWeight: FontWeight.w600,
        ),
        subtitleTextStyle: TextStyle(color: companyTheme.mutedInkColor),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: companyTheme.primaryColor,
          foregroundColor: onPrimary,
          disabledBackgroundColor:
              companyTheme.primaryColor.withValues(alpha: 0.42),
          disabledForegroundColor: onPrimary.withValues(alpha: 0.64),
          elevation: 0,
          minimumSize: const Size(64, 50),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.button),
          ),
          textStyle: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.2,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: companyTheme.iconColor,
          side: BorderSide(color: outline),
          backgroundColor: companyTheme.surfaceColor,
          minimumSize: const Size(64, 50),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.button),
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: companyTheme.iconColor,
          textStyle: const TextStyle(fontWeight: FontWeight.w600),
        ),
      ),
      floatingActionButtonTheme: base.floatingActionButtonTheme.copyWith(
        backgroundColor: companyTheme.primaryColor,
        foregroundColor: onPrimary,
      ),
      tabBarTheme: base.tabBarTheme.copyWith(
        labelColor: companyTheme.iconColor,
        unselectedLabelColor: companyTheme.mutedInkColor,
        indicatorColor: companyTheme.iconColor,
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: companyTheme.iconColor,
      ),
    );
  }
}
