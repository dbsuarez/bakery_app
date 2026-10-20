import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ThemePreset {
  final String id;
  final String label;
  final Color seedColor;
  const ThemePreset({
    required this.id,
    required this.label,
    required this.seedColor,
  });
}

const themePresets = <ThemePreset>[
  ThemePreset(
    id: 'bakery',
    label: 'Bakery Brown',
    seedColor: Color(0xFFB5651D),
  ),
  ThemePreset(id: 'cherry', label: 'Cherry', seedColor: Color(0xFFD32F2F)),
  ThemePreset(id: 'mint', label: 'Mint', seedColor: Color(0xFF00897B)),
  ThemePreset(id: 'berry', label: 'Berry', seedColor: Color(0xFF8E24AA)),
  ThemePreset(id: 'ocean', label: 'Ocean', seedColor: Color(0xFF1565C0)),
  ThemePreset(
    id: 'sunflower',
    label: 'Sunflower',
    seedColor: Color(0xFFF9A825),
  ),
];

const customPresetId = 'custom';

/// Per-device theme selection (preset color, or a custom picked color, plus
/// light/dark/system), persisted via SharedPreferences - same pattern as
/// AppLockService, never synced.
class ThemeController extends ChangeNotifier {
  static const _kPresetKey = 'theme_preset_id';
  static const _kModeKey = 'theme_mode';
  static const _kCustomColorKey = 'theme_custom_color';

  ThemePreset _preset = themePresets.first;
  Color _customColor = themePresets.first.seedColor;
  ThemeMode _mode = ThemeMode.system;

  ThemePreset get preset => _preset;
  Color get customColor => _customColor;
  bool get isCustom => _preset.id == customPresetId;
  ThemeMode get mode => _mode;

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final customValue = prefs.getInt(_kCustomColorKey);
    if (customValue != null) {
      _customColor = Color(customValue);
    }
    final presetId = prefs.getString(_kPresetKey);
    if (presetId == customPresetId) {
      _preset = ThemePreset(
        id: customPresetId,
        label: 'Custom',
        seedColor: _customColor,
      );
    } else if (presetId != null) {
      _preset = themePresets.firstWhere(
        (p) => p.id == presetId,
        orElse: () => themePresets.first,
      );
    }
    final modeName = prefs.getString(_kModeKey);
    if (modeName != null) {
      _mode = ThemeMode.values.firstWhere(
        (m) => m.name == modeName,
        orElse: () => ThemeMode.system,
      );
    }
    notifyListeners();
  }

  Future<void> setPreset(ThemePreset preset) async {
    _preset = preset;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kPresetKey, preset.id);
  }

  Future<void> setCustomColor(Color color) async {
    _customColor = color;
    _preset = ThemePreset(
      id: customPresetId,
      label: 'Custom',
      seedColor: color,
    );
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kPresetKey, customPresetId);
    await prefs.setInt(_kCustomColorKey, color.toARGB32());
  }

  Future<void> setMode(ThemeMode mode) async {
    _mode = mode;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kModeKey, mode.name);
  }

  ThemeData get lightTheme => _buildTheme(Brightness.light);

  ThemeData get darkTheme => _buildTheme(Brightness.dark);

  ThemeData _buildTheme(Brightness brightness) {
    final colors = ColorScheme.fromSeed(
      seedColor: _preset.seedColor,
      brightness: brightness,
    );
    final dark = brightness == Brightness.dark;

    return ThemeData(
      colorScheme: colors,
      useMaterial3: true,
      scaffoldBackgroundColor: dark
          ? colors.surface
          : Color.alphaBlend(
              colors.primary.withValues(alpha: 0.025),
              colors.surface,
            ),
      appBarTheme: AppBarTheme(
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        backgroundColor: colors.surface,
        foregroundColor: colors.onSurface,
        surfaceTintColor: Colors.transparent,
        titleTextStyle: TextStyle(
          color: colors.onSurface,
          fontSize: 22,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.4,
        ),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        margin: const EdgeInsets.symmetric(vertical: 4),
        color: colors.surfaceContainerLow,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: colors.outlineVariant.withValues(alpha: 0.6)),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: colors.surfaceContainerLowest,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: colors.outlineVariant),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: colors.outlineVariant),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: colors.primary, width: 2),
        ),
      ),
      listTileTheme: ListTileThemeData(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 3),
        iconColor: colors.onSurfaceVariant,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      navigationBarTheme: NavigationBarThemeData(
        height: 72,
        elevation: 0,
        backgroundColor: colors.surface,
        indicatorColor: colors.secondaryContainer,
        labelTextStyle: WidgetStateProperty.resolveWith(
          (states) => TextStyle(
            fontSize: 12,
            fontWeight: states.contains(WidgetState.selected)
                ? FontWeight.w700
                : FontWeight.w500,
          ),
        ),
      ),
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: colors.surface,
        indicatorColor: colors.secondaryContainer,
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        elevation: 2,
        highlightElevation: 3,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      dividerTheme: DividerThemeData(
        color: colors.outlineVariant.withValues(alpha: 0.65),
        thickness: 1,
        space: 1,
      ),
    );
  }
}
