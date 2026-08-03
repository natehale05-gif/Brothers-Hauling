import 'dart:convert';
import 'dart:typed_data';

import 'package:shared_preferences/shared_preferences.dart';

/// Somewhere on the device to put things that must outlive the process.
///
/// Deliberately tiny, and deliberately an interface. Every platform has a
/// different answer — a plist, SharedPreferences, the registry, a file under
/// XDG, IndexedDB — and tests want none of them. The board and its queue only
/// need get/put/delete over strings and bytes.
abstract class Store {
  Future<String?> readString(String key);
  Future<void> writeString(String key, String value);

  Future<Uint8List?> readBytes(String key);
  Future<void> writeBytes(String key, Uint8List value);

  Future<void> delete(String key);

  /// Keys currently held, for sweeping orphans.
  Future<Set<String>> keys();
}

/// Backed by `shared_preferences`, which ships an implementation for all six
/// target platforms.
///
/// Bytes are base64'd rather than stored raw, because the underlying stores
/// only agree on strings. That costs a third in size, which is why photo
/// pixels are kept out of the board record and written under their own keys —
/// they are read once when the board loads and are never rewritten as part of
/// an ordinary board update.
class PrefsStore implements Store {
  PrefsStore(this._prefs);

  static Future<PrefsStore> open() async =>
      PrefsStore(await SharedPreferences.getInstance());

  final SharedPreferences _prefs;

  @override
  Future<String?> readString(String key) async => _prefs.getString(key);

  @override
  Future<void> writeString(String key, String value) async =>
      _prefs.setString(key, value);

  @override
  Future<Uint8List?> readBytes(String key) async {
    final encoded = _prefs.getString(key);
    if (encoded == null) return null;
    try {
      return base64Decode(encoded);
    } on FormatException {
      // A truncated write from a process the OS killed mid-save. Treat it as
      // absent; the caller drops the photo rather than showing a broken one.
      return null;
    }
  }

  @override
  Future<void> writeBytes(String key, Uint8List value) async =>
      _prefs.setString(key, base64Encode(value));

  @override
  Future<void> delete(String key) async => _prefs.remove(key);

  @override
  Future<Set<String>> keys() async => _prefs.getKeys();
}

/// In-process store for tests and for the no-backend demo build.
class MemoryStore implements Store {
  MemoryStore([Map<String, Object>? seed]) : _data = {...?seed};

  final Map<String, Object> _data;

  /// Set to fail the next write, to exercise the paths that matter when a
  /// device is out of space or the platform channel is gone.
  Object? failNextWrite;

  void _maybeFail() {
    final failure = failNextWrite;
    if (failure == null) return;
    failNextWrite = null;
    throw failure;
  }

  @override
  Future<String?> readString(String key) async => _data[key] as String?;

  @override
  Future<void> writeString(String key, String value) async {
    _maybeFail();
    _data[key] = value;
  }

  @override
  Future<Uint8List?> readBytes(String key) async => _data[key] as Uint8List?;

  @override
  Future<void> writeBytes(String key, Uint8List value) async {
    _maybeFail();
    _data[key] = value;
  }

  @override
  Future<void> delete(String key) async => _data.remove(key);

  @override
  Future<Set<String>> keys() async => _data.keys.toSet();
}
