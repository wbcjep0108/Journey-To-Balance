import 'package:flutter/material.dart';

import 'barrier_blur.dart';

Widget appDatePickerBuilder(BuildContext context, Widget? child) {
  return withBarrierBlur(
    Theme(
      data: Theme.of(context).copyWith(
        colorScheme: const ColorScheme.light(
          primary: Color(0xFF121212),
          onPrimary: Colors.white,
          surface: Colors.white,
          onSurface: Color(0xFF121212),
        ),
        dialogTheme: const DialogThemeData(backgroundColor: Colors.white),
        datePickerTheme: DatePickerThemeData(
          backgroundColor: Colors.white,
          surfaceTintColor: Colors.transparent,
          headerBackgroundColor: const Color(0xFF121212),
          headerForegroundColor: Colors.white,
          dayForegroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) {
              return Colors.white;
            }
            if (states.contains(WidgetState.disabled)) {
              return Colors.black38;
            }
            return const Color(0xFF121212);
          }),
          dayBackgroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) {
              return const Color(0xFF121212);
            }
            return Colors.transparent;
          }),
          todayForegroundColor: const WidgetStatePropertyAll(Color(0xFF121212)),
          todayBackgroundColor: const WidgetStatePropertyAll(
            Colors.transparent,
          ),
          todayBorder: const BorderSide(color: Color(0xFF121212)),
          confirmButtonStyle: TextButton.styleFrom(
            foregroundColor: const Color(0xFF121212),
          ),
          cancelButtonStyle: TextButton.styleFrom(
            foregroundColor: const Color(0xFF121212),
          ),
        ),
      ),
      child: child!,
    ),
  );
}
