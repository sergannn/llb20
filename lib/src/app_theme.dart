import 'dart:math' as math;

import 'package:flutter/material.dart';

class LlbAppTheme {
  const LlbAppTheme._();

  static const baize = Color(0xff1c694d);
  static const wine = Color(0xff8f243b);
  static const felt = Color(0xfff8f5ec);
  static const border = Color(0xffc1d0c7);

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
            surface: Colors.white,
            surfaceContainerHighest: const Color(0xffe3ece7),
            outline: const Color(0xff839188),
          ),
      scaffoldBackgroundColor: felt,
      cardTheme: CardThemeData(
        color: Colors.white,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: const BorderSide(color: border),
        ),
      ),
      appBarTheme: const AppBarTheme(
        centerTitle: true,
        backgroundColor: felt,
        foregroundColor: Color(0xff1f2a24),
        scrolledUnderElevation: 0,
        elevation: 0,
        titleTextStyle: TextStyle(
          color: Color(0xff1f2a24),
          fontSize: 20,
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
        fillColor: Colors.white,
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
