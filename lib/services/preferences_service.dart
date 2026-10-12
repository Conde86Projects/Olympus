import 'package:flutter/foundation.dart';
import 'package:player/models/preferences.dart';

/// Preferencias do usuario (spec 5.3, 16). [current] nunca e null: antes de
/// [load] terminar, expoe os padroes.
abstract class PreferencesService extends ChangeNotifier {
  UserPreferences get current;

  Future<void> load();
  Future<void> update(UserPreferences preferences);

  /// Apaga preferencias e historico locais. Nunca apaga midias (spec 16).
  Future<void> clearLocalData();
}

/// Implementacao em memoria para o prototipo (Fase 1).
class InMemoryPreferencesService extends ChangeNotifier
    implements PreferencesService {
  UserPreferences _current = const UserPreferences();

  @override
  UserPreferences get current => _current;

  @override
  Future<void> load() async {}

  @override
  Future<void> update(UserPreferences preferences) async {
    _current = preferences;
    notifyListeners();
  }

  @override
  Future<void> clearLocalData() async {
    _current = const UserPreferences(showOnboarding: false);
    notifyListeners();
  }
}
