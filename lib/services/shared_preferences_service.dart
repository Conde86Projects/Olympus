import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:player/models/preferences.dart';
import 'package:player/services/preferences_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Preferencias persistentes em shared_preferences (Fase 2). Uma unica
/// chave JSON reutilizando [UserPreferences.toMap]/[UserPreferences.fromMap].
/// Contratos inalterados.
class SharedPreferencesPreferencesService extends ChangeNotifier
    implements PreferencesService {
  static const _key = 'player.preferences';

  UserPreferences _current = const UserPreferences();

  @override
  UserPreferences get current => _current;

  @override
  Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_key);
      if (raw == null) return;
      _current = UserPreferences.fromMap(
          Map<String, Object?>.from(jsonDecode(raw) as Map));
    } catch (_) {
      // Preferencias corrompidas: segue com os padroes (spec 7).
      _current = const UserPreferences();
    }
    notifyListeners();
  }

  @override
  Future<void> update(UserPreferences preferences) async {
    _current = preferences;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_key, jsonEncode(preferences.toMap()));
    } catch (_) {
      // Falha de persistencia nao bloqueia a UI (spec 19).
    }
  }

  @override
  Future<void> clearLocalData() async {
    _current = const UserPreferences(showOnboarding: false);
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_key);
    } catch (_) {
      // Falha de persistencia nao bloqueia a UI (spec 19).
    }
  }
}
