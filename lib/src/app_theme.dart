import 'dart:math' as math;

import 'package:flutter/material.dart';

class LlbAppTheme {
  const LlbAppTheme._();

  static const baize = Color(0xff0f5b46);
  static const wine = Color(0xff8f243b);
  static const felt = Color(0xfff3f5ee);
  static const border = Color(0xffdce2d6);

  static Widget mediaQueryBuilder(BuildContext context, Widget? child) {
    final media = MediaQuery.of(context);
    final scale = math.min(media.textScaler.scale(1), 1.08);
    return MediaQuery(
      data: media.copyWith(textScaler: TextScaler.linear(scale)),
      child: child ?? const SizedBox.shrink(),
    );
  }

  static ThemeData light() {
    return ThemeData(
      useMaterial3: true,
      colorScheme:
          ColorScheme.fromSeed(
            seedColor: baize,
            brightness: Brightness.light,
          ).copyWith(
            primary: baize,
            secondary: wine,
            tertiary: const Color(0xffc79a2f),
            surface: const Color(0xfffffff9),
            surfaceContainerHighest: const Color(0xffe7ece3),
            outline: const Color(0xff76847a),
          ),
      scaffoldBackgroundColor: felt,
      cardTheme: CardThemeData(
        color: const Color(0xfffffff9),
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: const BorderSide(color: border),
        ),
      ),
      appBarTheme: const AppBarTheme(
        centerTitle: true,
        backgroundColor: baize,
        foregroundColor: Colors.white,
        scrolledUnderElevation: 0,
        titleTextStyle: TextStyle(
          color: Colors.white,
          fontSize: 24,
          fontWeight: FontWeight.w500,
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        height: 76,
        indicatorColor: const Color(0xffd2f3e3),
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          return TextStyle(
            fontSize: 15,
            fontWeight: states.contains(WidgetState.selected)
                ? FontWeight.w700
                : FontWeight.w500,
            letterSpacing: 0,
          );
        }),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: const Color(0xfffffff9),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: baize, width: 1.4),
        ),
      ),
    );
  }
}
