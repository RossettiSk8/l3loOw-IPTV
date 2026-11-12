// Compatible con la versión de Flutter que distribuye LG.
// ignore: deprecated_member_use
import 'package:flutter/material.dart';

abstract final class StreamingPalette {
  static const background = Color(0xFF0B0D12);
  static const panel = Color(0xFF121824);
  static const surface = Color(0xFF1E293B);
  static const raised = Color(0xFF334155);
  static const outline = Color(0xFF64748B);
  static const divider = Color(0xFF303B4C);
  static const muted = Color(0xFF9CA3AF);
  static const active = Color(0xFFE5E7EB);
  static const accent = Color(0xFFFFFFFF);
  static const glass = Color(0xD91E293B);
  static const glassDark = Color(0xE6121824);
}

ThemeData streamingTheme() => ThemeData(
  colorScheme: const ColorScheme.dark(
    primary: StreamingPalette.accent,
    onPrimary: StreamingPalette.background,
    primaryContainer: StreamingPalette.raised,
    onPrimaryContainer: StreamingPalette.active,
    secondary: StreamingPalette.active,
    onSecondary: StreamingPalette.background,
    secondaryContainer: StreamingPalette.raised,
    onSecondaryContainer: StreamingPalette.accent,
    tertiary: StreamingPalette.muted,
    onTertiary: StreamingPalette.background,
    tertiaryContainer: StreamingPalette.surface,
    onTertiaryContainer: StreamingPalette.active,
    surface: StreamingPalette.background,
    onSurface: StreamingPalette.active,
    onSurfaceVariant: StreamingPalette.muted,
    surfaceContainerLowest: StreamingPalette.background,
    surfaceContainerLow: StreamingPalette.panel,
    surfaceContainer: StreamingPalette.surface,
    surfaceContainerHigh: StreamingPalette.surface,
    surfaceContainerHighest: StreamingPalette.raised,
    surfaceTint: Colors.transparent,
    outline: StreamingPalette.outline,
    outlineVariant: StreamingPalette.divider,
    inverseSurface: StreamingPalette.active,
    onInverseSurface: StreamingPalette.background,
    inversePrimary: StreamingPalette.raised,
  ),
  scaffoldBackgroundColor: StreamingPalette.background,
);
