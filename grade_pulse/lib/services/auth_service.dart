import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// LOCAL DEMONSTRATION AUTHENTICATION
///
/// Accounts live in this device's local storage (SharedPreferences). Passwords
/// are salted and hashed (iterated SHA-256) instead of being stored in plain
/// text, but this is NOT production-grade security: there is no server, no
/// rate limiting, no email verification and no password recovery, and anyone
/// with access to the device storage can read or delete the account records.
/// Replace this class with Firebase Authentication (or another backend) before
/// handling real credentials. The rest of the app only talks to the small
/// public API below, so swapping it is straightforward.

class AppUser {
  const AppUser({
    required this.id,
    required this.name,
    required this.email,
    required this.createdAt,
  });

  final String id;
  final String name;
  final String email;
  final DateTime createdAt;

  String get initials {
    final parts = name
        .trim()
        .split(RegExp(r'\s+'))
        .where((p) => p.isNotEmpty)
        .toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts.first[0].toUpperCase();
    return (parts.first[0] + parts.last[0]).toUpperCase();
  }
}

class AuthException implements Exception {
  const AuthException(this.message);
  final String message;
  @override
  String toString() => message;
}

class AuthService {
  AuthService(this._prefs);

  static const String _usersKey = 'gp_users_v1';
  static const String _sessionKey = 'gp_session_v1';

  final SharedPreferences _prefs;

  static final RegExp _emailPattern = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]{2,}$');

  static bool isValidEmail(String email) =>
      _emailPattern.hasMatch(email.trim());

  // ---- Public API ---------------------------------------------------------

  /// Returns the signed-in user from the saved session, or null.
  AppUser? restoreSession() {
    final uid = _prefs.getString(_sessionKey);
    if (uid == null) return null;
    try {
      for (final record in _readUsers().values) {
        if (record['id'] == uid) return _toUser(record);
      }
    } on AuthException {
      return null;
    }
    return null;
  }

  Future<AppUser> signUp({
    required String name,
    required String email,
    required String password,
  }) async {
    final cleanName = name.trim();
    final cleanEmail = email.trim().toLowerCase();

    if (cleanName.isEmpty) throw const AuthException('Please enter your name.');
    if (cleanEmail.isEmpty) {
      throw const AuthException('Please enter your email address.');
    }
    if (!isValidEmail(cleanEmail)) {
      throw const AuthException('Please enter a valid email address.');
    }
    if (password.length < 8) {
      throw const AuthException('Password must be at least 8 characters.');
    }

    final users = _readUsers();
    if (users.containsKey(cleanEmail)) {
      throw const AuthException(
        'An account with this email already exists. Try signing in instead.',
      );
    }

    final salt = _randomString(16);
    final id =
        '${DateTime.now().microsecondsSinceEpoch}-${_randomString(6)}'
            .replaceAll(RegExp(r'[^A-Za-z0-9\-]'), '');
    final record = <String, dynamic>{
      'id': id,
      'name': cleanName,
      'email': cleanEmail,
      'salt': salt,
      'hash': _hash(password, salt),
      'createdAt': DateTime.now().toIso8601String(),
    };
    users[cleanEmail] = record;

    await _writeUsers(users);
    await _setSession(id);
    return _toUser(record);
  }

  Future<AppUser> signIn({
    required String email,
    required String password,
  }) async {
    final cleanEmail = email.trim().toLowerCase();
    if (cleanEmail.isEmpty) {
      throw const AuthException('Please enter your email address.');
    }
    if (!isValidEmail(cleanEmail)) {
      throw const AuthException('Please enter a valid email address.');
    }
    if (password.isEmpty) {
      throw const AuthException('Please enter your password.');
    }

    final record = _readUsers()[cleanEmail];
    // Same message for "no account" and "wrong password" on purpose.
    const failure = AuthException('Incorrect email or password.');
    if (record == null) throw failure;

    final expected = record['hash'] as String;
    final actual = _hash(password, record['salt'] as String);
    if (expected != actual) throw failure;

    await _setSession(record['id'] as String);
    return _toUser(record);
  }

  /// Updates the local demonstration account identity. Password hashes and the
  /// account ID remain unchanged; email is re-keyed only after validation.
  Future<AppUser> updateProfile({
    required String userId,
    required String name,
    required String email,
  }) async {
    final cleanName = name.trim();
    final cleanEmail = email.trim().toLowerCase();
    if (cleanName.isEmpty) throw const AuthException('Please enter your name.');
    if (cleanEmail.isEmpty || !isValidEmail(cleanEmail)) {
      throw const AuthException('Please enter a valid email address.');
    }

    final users = _readUsers();
    String? oldKey;
    Map<String, dynamic>? record;
    for (final entry in users.entries) {
      if (entry.value['id'] == userId) {
        oldKey = entry.key;
        record = Map<String, dynamic>.from(entry.value);
        break;
      }
    }
    if (oldKey == null || record == null) {
      throw const AuthException('This account could not be found. Please sign in again.');
    }
    final existing = users[cleanEmail];
    if (existing != null && existing['id'] != userId) {
      throw const AuthException('That email address is already used by another account.');
    }

    record['name'] = cleanName;
    record['email'] = cleanEmail;
    final next = Map<String, Map<String, dynamic>>.from(users)..remove(oldKey);
    next[cleanEmail] = record;
    await _writeUsers(next);
    return _toUser(record);
  }

  Future<void> signOut() async {
    final ok = await _prefs.remove(_sessionKey);
    if (!ok) throw const AuthException('Could not log out. Please try again.');
  }

  // ---- Internals ----------------------------------------------------------

  Map<String, Map<String, dynamic>> _readUsers() {
    final raw = _prefs.getString(_usersKey);
    if (raw == null) return <String, Map<String, dynamic>>{};
    try {
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      return decoded.map(
        (key, value) => MapEntry(key, Map<String, dynamic>.from(value as Map)),
      );
    } catch (_) {
      // Refuse to continue rather than silently replacing saved accounts.
      throw const AuthException(
        'Saved account data could not be read. Please reinstall or clear app data.',
      );
    }
  }

  Future<void> _writeUsers(Map<String, Map<String, dynamic>> users) async {
    final ok = await _prefs.setString(_usersKey, jsonEncode(users));
    if (!ok) {
      throw const AuthException('Could not save your account. Please retry.');
    }
  }

  Future<void> _setSession(String uid) async {
    final ok = await _prefs.setString(_sessionKey, uid);
    if (!ok) {
      throw const AuthException('Could not start your session. Please retry.');
    }
  }

  AppUser _toUser(Map<String, dynamic> record) => AppUser(
    id: record['id'] as String,
    name: record['name'] as String,
    email: record['email'] as String,
    createdAt:
        DateTime.tryParse(record['createdAt'] as String? ?? '') ??
        DateTime.now(),
  );

  String _randomString(int bytes) {
    final random = Random.secure();
    final data = List<int>.generate(bytes, (_) => random.nextInt(256));
    return base64UrlEncode(data);
  }

  String _hash(String password, String salt) {
    final input = utf8.encode('$salt:$password');
    var digest = sha256.convert(input);
    for (var i = 0; i < 5000; i++) {
      digest = sha256.convert([...digest.bytes, ...input]);
    }
    return digest.toString();
  }
}
