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
  ThemePreset(id: 'bakery', label: 'Bakery Brown', seedColor: Color(0xFFB5651D)),
  ThemePreset(id: 'cherry', label: 'Cherry', seedColor: Color(0xFFD32F2F)),
  ThemePreset(id: 'mint', label: 'Mint', seedColor: Color(0xFF00897B)),
  ThemePreset(id: 'berry', label: 'Berry', seedColor: Color(0xFF8E24AA)),
  ThemePreset(id: 'ocean', label: 'Ocean', seedColor: Color(0xFF1565C0)),
  ThemePreset(id: 'sunflower', label: 'Sunflower', seedColor: Color(0xFFF9A825)),
];

const customPresetId = 'custom';

/// Per-device theme selection (preset color, or a custom picked color, plus
/// light/dark/system), persisted via SharedPreferences - same pattern as
/// AppLockService, never synced.
class ThemeController extends ChangeNotifier {
  static const _kPresetKey = 'theme_preset_id';
  static const _kModeKey = 'theme_mode';
  static const _kCustomColorKey = 'theme_custom_color';
  static const _kShowCardDescriptionsKey = 'show_dashboard_card_descriptions';

  ThemePreset _preset = themePresets.first;
  Color _customColor = themePresets.first.seedColor;
  ThemeMode _mode = ThemeMode.system;
  bool _showCardDescriptions = true;

  ThemePreset get preset => _preset;
  Color get customColor => _customColor;
  bool get isCustom => _preset.id == customPresetId;
  ThemeMode get mode => _mode;
  bool get showCardDescriptions => _showCardDescriptions;

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
    _showCardDescriptions =
        prefs.getBool(_kShowCardDescriptionsKey) ?? true;
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
    _preset = ThemePreset(id: customPresetId, label: 'Custom', seedColor: color);
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

  Future<void> setShowCardDescriptions(bool value) async {
    _showCardDescriptions = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kShowCardDescriptionsKey, value);
  }

  ThemeData get lightTheme => ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: _preset.seedColor,
          brightness: Brightness.light,
        ),
        useMaterial3: true,
      );

  ThemeData get darkTheme => ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: _preset.seedColor,
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      );
}
