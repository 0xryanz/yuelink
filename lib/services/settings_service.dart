import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

/// Persistent settings storage using a simple JSON file.
class SettingsService {
  static const _fileName = 'settings.json';
  static Map<String, dynamic>? _cache;

  static Future<File> _getFile() async {
    final dir = await getApplicationSupportDirectory();
    return File('${dir.path}/$_fileName');
  }

  static Future<Map<String, dynamic>> load() async {
    if (_cache != null) return _cache!;
    final file = await _getFile();
    if (!await file.exists()) {
      _cache = {};
      return _cache!;
    }
    _cache = json.decode(await file.readAsString()) as Map<String, dynamic>;
    return _cache!;
  }

  static Future<void> save(Map<String, dynamic> settings) async {
    _cache = settings;
    final file = await _getFile();
    await file.writeAsString(json.encode(settings));
  }

  static Future<void> set(String key, dynamic value) async {
    final settings = await load();
    settings[key] = value;
    await save(settings);
  }

  static Future<T?> get<T>(String key) async {
    final settings = await load();
    return settings[key] as T?;
  }

  // Convenience methods

  static Future<ThemeMode> getThemeMode() async {
    final value = await get<String>('themeMode');
    switch (value) {
      case 'light':
        return ThemeMode.light;
      case 'dark':
        return ThemeMode.dark;
      default:
        return ThemeMode.system;
    }
  }

  static Future<void> setThemeMode(ThemeMode mode) async {
    await set('themeMode', mode.name);
  }

  static Future<String?> getActiveProfileId() async {
    return get<String>('activeProfileId');
  }

  static Future<void> setActiveProfileId(String? id) async {
    await set('activeProfileId', id);
  }
}
