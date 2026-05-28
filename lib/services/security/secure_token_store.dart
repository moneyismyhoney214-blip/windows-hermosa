import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../logger_service.dart';

/// One saved login the user previously authenticated with successfully.
/// Holds the password verbatim so it can be auto-typed into the password
/// field; the whole record lives in Keystore/Keychain.
class SavedAccount {
  final String email;
  final String password;
  const SavedAccount({required this.email, required this.password});

  Map<String, String> toJson() => {'email': email, 'password': password};

  static SavedAccount? fromJson(dynamic raw) {
    if (raw is! Map) return null;
    final email = raw['email']?.toString().trim() ?? '';
    final password = raw['password']?.toString() ?? '';
    if (email.isEmpty || password.isEmpty) return null;
    return SavedAccount(email: email, password: password);
  }
}

/// Encrypted-at-rest store for authentication-tier secrets: the bearer JWT
/// and the cached user payload that holds the signed-in employee's PII.
///
/// Backed by Android Keystore (AES-GCM) on Android and Keychain on iOS via
/// `flutter_secure_storage`. Earlier builds wrote these values to
/// `SharedPreferences`, which on Android lands as plaintext XML under
/// `/data/data/<app>/shared_prefs/` — readable by any process with root
/// and by `adb backup` when allowBackup defaults to true. This class
/// transparently migrates those legacy values on first read so existing
/// sessions survive the upgrade without forcing a re-login.
///
/// Migration sequence:
///   1. Try secure storage. If a value exists, return it.
///   2. Otherwise fall back to SharedPreferences. If found, copy the value
///      into secure storage and delete the plaintext copy. Return it.
///   3. Otherwise return null.
///
/// Logout clears both backends so the wipe is total even if a migration
/// failed earlier.
class SecureTokenStore {
  SecureTokenStore._();
  static final SecureTokenStore instance = SecureTokenStore._();

  static const _tag = 'secure-store';

  // Storage-key constants. Must match the legacy SharedPreferences keys
  // exactly so the migration step can find the old values.
  static const _kToken = 'auth_token';
  static const _kUser = 'user_data';
  // "Remember me" credentials. Keychain/Keystore-backed; never touched on logout.
  // Legacy single-pair keys (kept for one-way migration to the new accounts list).
  static const _kRememberEmail = 'remember_email';
  static const _kRememberPassword = 'remember_password';
  // JSON-encoded `List<{email, password}>` for the autocomplete dropdown.
  static const _kSavedAccounts = 'saved_accounts';

  // Android: prefer EncryptedSharedPreferences over the deprecated KeyStore-
  // direct flow because it's available on all API levels we ship to.
  // iOS:    Keychain with `first_unlock` accessibility so background work
  //         after the first device unlock keeps working.
  static const AndroidOptions _androidOptions = AndroidOptions(
    encryptedSharedPreferences: true,
    resetOnError: true,
  );
  static const IOSOptions _iosOptions = IOSOptions(
    accessibility: KeychainAccessibility.first_unlock,
  );

  final FlutterSecureStorage _storage = const FlutterSecureStorage(
    aOptions: _androidOptions,
    iOptions: _iosOptions,
  );

  // ─────────────────────────── Token ────────────────────────────────────

  /// Reads the JWT. Returns null if no token is stored. Triggers a one-time
  /// migration of a legacy SharedPreferences token if found.
  Future<String?> readToken() async {
    final fromSecure = await _safeRead(_kToken);
    if (fromSecure != null && fromSecure.isNotEmpty) return fromSecure;

    // Migration path: legacy SharedPreferences-resident token.
    try {
      final prefs = await SharedPreferences.getInstance();
      final legacy = prefs.getString(_kToken);
      if (legacy != null && legacy.isNotEmpty) {
        await _safeWrite(_kToken, legacy);
        await prefs.remove(_kToken);
        Log.i(_tag, 'migrated legacy token to secure storage');
        return legacy;
      }
    } catch (e) {
      Log.w(_tag, 'legacy token migration failed', error: e);
    }
    return null;
  }

  Future<void> writeToken(String token) async {
    await _safeWrite(_kToken, token);
    // Defense-in-depth: nuke any stale plaintext copy.
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_kToken);
    } catch (_) {/* ignore — already removed or prefs unavailable */}
  }

  Future<void> deleteToken() async {
    await _safeDelete(_kToken);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_kToken);
    } catch (_) {/* ignore */}
  }

  // ─────────────────────────── User payload ─────────────────────────────

  /// Returns the cached user JSON string. Migrates from SharedPreferences
  /// the same way [readToken] does.
  Future<String?> readUser() async {
    final fromSecure = await _safeRead(_kUser);
    if (fromSecure != null && fromSecure.isNotEmpty) return fromSecure;

    try {
      final prefs = await SharedPreferences.getInstance();
      final legacy = prefs.getString(_kUser);
      if (legacy != null && legacy.isNotEmpty) {
        await _safeWrite(_kUser, legacy);
        await prefs.remove(_kUser);
        Log.i(_tag, 'migrated legacy user payload to secure storage');
        return legacy;
      }
    } catch (e) {
      Log.w(_tag, 'legacy user migration failed', error: e);
    }
    return null;
  }

  Future<void> writeUser(String jsonString) async {
    await _safeWrite(_kUser, jsonString);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_kUser);
    } catch (_) {/* ignore */}
  }

  Future<void> deleteUser() async {
    await _safeDelete(_kUser);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_kUser);
    } catch (_) {/* ignore */}
  }

  /// Wipes every credential-tier value (token + user) from both backends.
  /// Called from `AuthService.logout()`. Does NOT clear "remember me"
  /// credentials — those survive logout so the next login can prefill.
  Future<void> clearAll() async {
    await deleteToken();
    await deleteUser();
  }

  // ─────────────────── Saved accounts (autocomplete) ────────────────────

  /// Returns every account the user has previously signed in with on this
  /// device. Most-recently-used first. Empty list if none saved yet.
  /// Transparently migrates the legacy single-pair keys on first read.
  Future<List<SavedAccount>> readAccounts() async {
    final raw = await _safeRead(_kSavedAccounts);
    final accounts = <SavedAccount>[];
    if (raw != null && raw.isNotEmpty) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is List) {
          for (final entry in decoded) {
            final account = SavedAccount.fromJson(entry);
            if (account != null) accounts.add(account);
          }
        }
      } catch (e) {
        Log.w(_tag, 'saved_accounts JSON is corrupt — dropping', error: e);
        await _safeDelete(_kSavedAccounts);
      }
    }

    // Legacy single-pair migration: fold it in once, then delete the old keys.
    if (accounts.isEmpty) {
      final email = await _safeRead(_kRememberEmail);
      final password = await _safeRead(_kRememberPassword);
      if (email != null && email.isNotEmpty &&
          password != null && password.isNotEmpty) {
        accounts.add(SavedAccount(email: email, password: password));
        await _safeWrite(_kSavedAccounts,
            jsonEncode(accounts.map((a) => a.toJson()).toList()));
        await _safeDelete(_kRememberEmail);
        await _safeDelete(_kRememberPassword);
        Log.i(_tag, 'migrated legacy remember-me pair to accounts list');
      }
    }

    return accounts;
  }

  /// Save/update an account. Matching is by email (case-insensitive). The
  /// entry is moved to the top of the list so the most-recent login wins
  /// the auto-prefill on next launch.
  Future<void> upsertAccount(String email, String password) async {
    final trimmed = email.trim();
    if (trimmed.isEmpty || password.isEmpty) return;
    final existing = await readAccounts();
    existing.removeWhere(
        (a) => a.email.toLowerCase() == trimmed.toLowerCase());
    existing.insert(0, SavedAccount(email: trimmed, password: password));
    // Cap at 10 entries — beyond that the dropdown becomes noise.
    final capped = existing.take(10).toList();
    await _safeWrite(_kSavedAccounts,
        jsonEncode(capped.map((a) => a.toJson()).toList()));
  }

  /// Remove an account by email (case-insensitive). No-op if not found.
  Future<void> deleteAccount(String email) async {
    final trimmed = email.trim();
    if (trimmed.isEmpty) return;
    final existing = await readAccounts();
    final filtered = existing
        .where((a) => a.email.toLowerCase() != trimmed.toLowerCase())
        .toList();
    if (filtered.length == existing.length) return;
    if (filtered.isEmpty) {
      await _safeDelete(_kSavedAccounts);
    } else {
      await _safeWrite(_kSavedAccounts,
          jsonEncode(filtered.map((a) => a.toJson()).toList()));
    }
  }

  Future<void> clearAccounts() async {
    await _safeDelete(_kSavedAccounts);
    await _safeDelete(_kRememberEmail);
    await _safeDelete(_kRememberPassword);
  }

  // ─────────────────────────── Internal ─────────────────────────────────

  /// Wraps `_storage.read` so a runtime failure in the platform plugin
  /// (e.g. Keystore not available) degrades to "no value" instead of
  /// taking down the whole boot path.
  Future<String?> _safeRead(String key) async {
    try {
      return await _storage.read(key: key);
    } catch (e) {
      Log.w(_tag, 'secure read failed for "$key"', error: e);
      return null;
    }
  }

  Future<void> _safeWrite(String key, String value) async {
    try {
      await _storage.write(key: key, value: value);
    } catch (e) {
      Log.e(_tag, 'secure write failed for "$key" — '
          'falling back to SharedPreferences so session is preserved',
          error: e);
      // Fallback: at least keep the session alive on this device. Logged
      // as an error so the user can see it should they enable telemetry.
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(key, value);
      } catch (_) {/* surrender */}
    }
  }

  Future<void> _safeDelete(String key) async {
    try {
      await _storage.delete(key: key);
    } catch (e) {
      Log.w(_tag, 'secure delete failed for "$key"', error: e);
    }
  }
}

/// Top-level accessor so call-sites don't have to type `.instance` every
/// time.
final SecureTokenStore secureTokenStore = SecureTokenStore.instance;
