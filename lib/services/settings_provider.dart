import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../core/constants.dart';
import '../models/app_settings.dart';

class SettingsNotifier extends Notifier<AppSettings> {
  static const _key = 'app';

  Box<String> get _box => Hive.box<String>(AppConstants.settingsBox);

  @override
  AppSettings build() {
    final raw = _box.get(_key);
    if (raw == null) return const AppSettings();
    try {
      return AppSettings.fromMap(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return const AppSettings();
    }
  }

  Future<void> update(AppSettings s) async {
    state = s;
    await _box.put(_key, jsonEncode(s.toMap()));
  }
}

final settingsProvider =
    NotifierProvider<SettingsNotifier, AppSettings>(SettingsNotifier.new);
