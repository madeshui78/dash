// 应用主题：中性底色 + 单一主色，四个模块各有一个功能色
// （颜色定义在 module_palette.dart，改配色只改那一处）。
//
// 几条规矩：
//   - 页面底色统一是 canvas，卡片是 surface，不再出现纯黑大色块；
//   - 主色不再是黑：黑色只用于正文，按钮和选中态用墨绿；
//   - 没有重阴影，层次靠底色差和留白；
//   - 圆角 14，按钮和卡片同一套。
//
// 深色模式不是"反过来"，是另一套同构的中性色，避免纯黑底 + 纯白字刺眼。

import 'package:flutter/material.dart';

import 'module_palette.dart';

class AppTheme {
  AppTheme._();

  static const double radius = 14;

  /// 浅色：冷白
  static ThemeData light() {
    const ModulePalette p = ModulePalette.light;
    final ColorScheme cs = ColorScheme(
      brightness: Brightness.light,
      primary: p.essay,
      onPrimary: const Color(0xFFFFFFFF),
      primaryContainer: const Color(0xFFDCE8FF),
      onPrimaryContainer: const Color(0xFF12305F),
      secondary: p.word,
      onSecondary: const Color(0xFFFFFFFF),
      secondaryContainer: const Color(0xFFE7E0FF),
      onSecondaryContainer: const Color(0xFF2A1D5A),
      tertiary: p.chat,
      onTertiary: const Color(0xFFFFFFFF),
      tertiaryContainer: p.surfaceAlt,
      onTertiaryContainer: p.ink,
      error: p.wrong,
      onError: const Color(0xFFFFFFFF),
      errorContainer: const Color(0xFFFBE4E1),
      onErrorContainer: const Color(0xFF6B1E16),
      surface: p.canvas,
      onSurface: p.ink,
      onSurfaceVariant: p.muted,
      outline: const Color(0xFFC3CAD8),
      outlineVariant: p.line,
      shadow: const Color(0x00000000),
      scrim: const Color(0x66000000),
      inverseSurface: const Color(0xFF1B2333),
      onInverseSurface: const Color(0xFFF5F7FB),
      inversePrimary: const Color(0xFF7FA8FF),
      surfaceTint: p.canvas,
      // M3 的容器色必须写全，否则会被推导成跟背景一样，卡片直接隐形
      surfaceContainerLowest: p.surface,
      surfaceContainerLow: const Color(0xFFF2F5FA),
      surfaceContainer: const Color(0xFFE9EDF5),
      surfaceContainerHigh: const Color(0xFFE1E7F1),
      surfaceContainerHighest: p.surfaceAlt,
    );
    return _build(cs, p);
  }

  /// 深色：墨蓝，不用纯黑
  static ThemeData dark() {
    const ModulePalette p = ModulePalette.dark;
    final ColorScheme cs = ColorScheme(
      brightness: Brightness.dark,
      primary: p.essay,
      onPrimary: const Color(0xFF06101F),
      primaryContainer: const Color(0xFF16294A),
      onPrimaryContainer: const Color(0xFFD6E3FF),
      secondary: p.word,
      onSecondary: const Color(0xFF0B0820),
      secondaryContainer: const Color(0xFF241C44),
      onSecondaryContainer: const Color(0xFFE2D9FF),
      tertiary: p.chat,
      onTertiary: const Color(0xFF0E0D0A),
      tertiaryContainer: p.surfaceAlt,
      onTertiaryContainer: p.ink,
      error: p.wrong,
      onError: const Color(0xFF2B0F0B),
      errorContainer: const Color(0xFF3A211E),
      onErrorContainer: const Color(0xFFF5D9D5),
      surface: p.canvas,
      onSurface: p.ink,
      onSurfaceVariant: p.muted,
      outline: const Color(0xFF333C52),
      outlineVariant: p.line,
      shadow: const Color(0x00000000),
      scrim: const Color(0x99000000),
      inverseSurface: const Color(0xFFECEEF5),
      onInverseSurface: const Color(0xFF101828),
      inversePrimary: const Color(0xFF2E76F2),
      surfaceTint: p.canvas,
      surfaceContainerLowest: const Color(0xFF0E1422),
      surfaceContainerLow: p.surface,
      surfaceContainer: const Color(0xFF1B1F20),
      surfaceContainerHigh: const Color(0xFF222627),
      surfaceContainerHighest: p.surfaceAlt,
    );
    return _build(cs, p);
  }

  static ThemeData _build(ColorScheme cs, ModulePalette p) {
    return ThemeData(
      useMaterial3: true,
      brightness: cs.brightness,
      colorScheme: cs,
      scaffoldBackgroundColor: p.canvas,
      canvasColor: p.surface,
      splashFactory: InkSparkle.splashFactory,

      cardTheme: CardThemeData(
        color: p.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radius),
        ),
      ),

      appBarTheme: AppBarTheme(
        backgroundColor: p.canvas,
        foregroundColor: p.ink,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleSpacing: 4,
        titleTextStyle: TextStyle(
          fontSize: 17,
          fontWeight: FontWeight.w600,
          color: p.ink,
          letterSpacing: 0.2,
        ),
        iconTheme: IconThemeData(color: p.ink),
        actionsIconTheme: IconThemeData(color: p.ink),
      ),

      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: cs.primary,
          foregroundColor: cs.onPrimary,
          elevation: 0,
          minimumSize: const Size.fromHeight(46),
          textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radius),
          ),
        ),
      ),

      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: p.ink,
          elevation: 0,
          minimumSize: const Size.fromHeight(46),
          textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
          side: BorderSide(color: p.line),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radius),
          ),
        ),
      ),

      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(foregroundColor: p.ink),
      ),

      chipTheme: ChipThemeData(
        backgroundColor: p.surface,
        side: BorderSide(color: p.line),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        showCheckmark: false,
      ),

      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: p.surface,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        hintStyle: TextStyle(color: p.muted, fontSize: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radius),
          borderSide: BorderSide(color: p.line),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radius),
          borderSide: BorderSide(color: p.line),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radius),
          borderSide: BorderSide(color: cs.primary, width: 1.4),
        ),
      ),

      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor: p.surface,
        selectedItemColor: cs.primary,
        unselectedItemColor: p.muted,
        elevation: 0,
        type: BottomNavigationBarType.fixed,
      ),

      drawerTheme: DrawerThemeData(
        backgroundColor: p.canvas,
        scrimColor: cs.scrim,
        elevation: 0,
        shape: const RoundedRectangleBorder(),
      ),

      listTileTheme: ListTileThemeData(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        iconColor: p.muted,
        textColor: p.ink,
      ),

      dividerTheme: DividerThemeData(
        color: p.line,
        thickness: 1,
        space: 1,
      ),

      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: cs.inverseSurface,
        contentTextStyle: TextStyle(color: cs.onInverseSurface),
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radius),
        ),
      ),

      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: cs.primary,
        linearTrackColor: p.surfaceAlt,
      ),

      dialogTheme: DialogThemeData(
        backgroundColor: p.surface,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radius),
        ),
      ),

      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: p.surface,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
      ),
    );
  }
}
