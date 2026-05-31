import 'dart:ffi';
import 'dart:io';

import 'package:sqflite_common_ffi/sqflite_ffi.dart';

bool _initialized = false;

// Held for the lifetime of the test process so the loaded sqlite3 module
// is never unloaded — once it's in the process, sqlite3's native-assets
// "process" lookup can resolve `sqlite3_initialize` & friends from it.
// ignore: unused_element
DynamicLibrary? _sqliteLib;

/// Boots sqflite's FFI backend for VM tests that hit a real SQLite engine.
///
/// macOS/Linux CI ship sqlite3 as a system library, so the process-lookup
/// strategy configured by `hooks.user_defines.sqlite3.source: process` in
/// pubspec.yaml resolves the symbols out of the box. Windows has no system
/// sqlite3, and `sqlite3_flutter_libs` only bundles the DLL next to a
/// *built* app — it isn't present for `flutter test`. So on Windows the
/// offline DB tests used to fail with:
///   "Couldn't resolve native function 'sqlite3_initialize'".
///
/// We bridge that gap on Windows by loading a sqlite3.dll into the test
/// process before the first DB call. Process-lookup then finds the symbols
/// among the loaded modules. The DLL path comes from the SQLITE3_TEST_DLL
/// env var when CI provides one (see codemagic.yaml), otherwise we fall
/// back to the standard Windows DLL search path ('sqlite3.dll' in the cwd
/// / PATH). macOS/Linux are left untouched.
void initSqfliteForTests() {
  if (_initialized) return;
  _initialized = true;

  if (Platform.isWindows) {
    final dll = Platform.environment['SQLITE3_TEST_DLL'];
    _sqliteLib = DynamicLibrary.open(
      (dll != null && dll.isNotEmpty) ? dll : 'sqlite3.dll',
    );
  }

  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
}
