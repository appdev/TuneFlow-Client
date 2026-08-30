import 'package:shared_preferences/shared_preferences.dart';

final class RadioPreferences {
  RadioPreferences({SharedPreferencesAsync? preferences})
    : _preferences = preferences ?? _tryPreferences();
  static const key = 'player_auto_radio_continuation_v1';
  final SharedPreferencesAsync? _preferences;
  bool _memory = false;
  Future<bool> readAutoContinuation() async =>
      await _preferences?.getBool(key) ?? _memory;
  Future<void> writeAutoContinuation(bool value) async {
    _memory = value;
    await _preferences?.setBool(key, value);
  }
}

SharedPreferencesAsync? _tryPreferences() {
  try {
    return SharedPreferencesAsync();
  } on StateError {
    return null;
  }
}
