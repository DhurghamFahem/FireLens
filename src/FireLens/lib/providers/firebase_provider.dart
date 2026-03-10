import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/schema_model.dart';

const _kAppName = 'fire_lens_runtime';

class FirebaseProvider extends ChangeNotifier {
  FirebaseApp? _app;
  FirebaseConfig? _config;
  bool _isConnected = false;
  String? _error;
  bool _isLoading = false;

  bool get isConnected => _isConnected;
  FirebaseConfig? get config => _config;
  String? get error => _error;
  bool get isLoading => _isLoading;

  // Safe accessor — throws if not connected
  FirebaseApp get app {
    assert(_app != null, 'Firebase is not initialized.');
    return _app!;
  }

  Future<void> loadSavedConfig() async {
    final prefs = await SharedPreferences.getInstance();
    final apiKey = prefs.getString('apiKey');
    if (apiKey == null || apiKey.isEmpty) return;

    final config = FirebaseConfig.fromMap({
      'apiKey': prefs.getString('apiKey') ?? '',
      'projectId': prefs.getString('projectId') ?? '',
      'appId': prefs.getString('appId') ?? '',
      'messagingSenderId': prefs.getString('messagingSenderId') ?? '',
      'storageBucket': prefs.getString('storageBucket') ?? '',
      if (prefs.getString('authDomain') != null)
        'authDomain': prefs.getString('authDomain')!,
    });

    if (config.isValid) {
      await connect(config);
    }
  }

  Future<bool> connect(FirebaseConfig config) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      // Delete previous app instance if it exists
      try {
        final existing = Firebase.app(_kAppName);
        await existing.delete();
      } catch (_) {
        // No existing app — fine
      }

      final firebaseApp = await Firebase.initializeApp(
        name: _kAppName,
        options: FirebaseOptions(
          apiKey: config.apiKey,
          projectId: config.projectId,
          appId: config.appId,
          messagingSenderId: config.messagingSenderId,
          storageBucket: config.storageBucket,
          authDomain: config.authDomain,
        ),
      );

      _app = firebaseApp;
      _config = config;
      _isConnected = true;
      await _saveConfig(config);
      return true;
    } catch (e) {
      _error = e.toString();
      _isConnected = false;
      return false;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> disconnect() async {
    try {
      final existing = Firebase.app(_kAppName);
      await existing.delete();
    } catch (_) {}

    _app = null;
    _config = null;
    _isConnected = false;
    _error = null;
    await _clearConfig();
    notifyListeners();
  }

  Future<void> _saveConfig(FirebaseConfig config) async {
    final prefs = await SharedPreferences.getInstance();
    final map = config.toMap();
    for (final entry in map.entries) {
      await prefs.setString(entry.key, entry.value);
    }
  }

  Future<void> _clearConfig() async {
    final prefs = await SharedPreferences.getInstance();
    for (final key in [
      'apiKey',
      'projectId',
      'appId',
      'messagingSenderId',
      'storageBucket',
      'authDomain',
    ]) {
      await prefs.remove(key);
    }
  }
}
