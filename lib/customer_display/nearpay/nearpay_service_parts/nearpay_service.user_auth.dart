part of '../nearpay_service.dart';

// User-uuid persistence + active-user resolution + terminal-selection
// helpers extracted from nearpay_service.dart. All methods touch only
// instance state via the extension target (`_userUuid`, `_terminalUuid`,
// `_tid`, `_sdk`), so the behaviour is byte-identical to the inline
// originals.

extension _NearPayServiceUserAuth on NearPayService {
  Future<void> _persistUserUuid(String? userUuid) async {
    final normalized = userUuid?.trim();
    if (normalized == null || normalized.isEmpty) {
      return;
    }
    _userUuid = normalized;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('np_terminal_user_uuid', normalized);
  }

  Future<String?> _loadSavedUserUuid() async {
    final current = _userUuid?.trim();
    if (current != null && current.isNotEmpty) {
      return current;
    }
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString('np_terminal_user_uuid')?.trim();
    if (saved != null && saved.isNotEmpty) {
      _userUuid = saved;
      return saved;
    }
    return null;
  }

  // Reserved fallback for the full documented SDK flow.
  // ignore: unused_element
  Future<NearpayUser> _resolveActiveUser() async {
    if (_sdk == null) {
      throw Exception('NearPay SDK not initialized');
    }

    final savedUserUuid = await _loadSavedUserUuid();
    if (savedUserUuid != null && savedUserUuid.isNotEmpty) {
      _npLog('🔄 Resolving active user via getUser(uuid)...');
      _npLogDetail('User Resolution Params', {
        'user_uuid': _maskId(savedUserUuid),
      });
      try {
        final user = await _sdk!.getUser(uuid: savedUserUuid);
        await _persistUserUuid(user.userUUID);
        _npLog('✅ Active user resolved from saved userUUID');
        return user;
      } catch (e) {
        _npLog('⚠️ getUser(saved userUUID) failed: $e');
      }
    }

    _npLog('🔄 Falling back to SDK getUsers()...');
    final sdkUsers = await _sdk!.getUsers();
    final validUsers = sdkUsers.where((u) {
      final uuid = u.userUUID?.trim();
      return uuid != null && uuid.isNotEmpty;
    }).toList();

    if (validUsers.isEmpty) {
      throw Exception('No authenticated SDK users found after jwtLogin');
    }

    final resolvedUser = validUsers.first;
    await _persistUserUuid(resolvedUser.userUUID);
    _npLog('✅ Active user resolved from getUsers() fallback');
    return resolvedUser;
  }

  TerminalConnectionModel? _selectTerminalConnection(
    List<TerminalConnectionModel> terminals,
  ) {
    if (terminals.isEmpty) return null;

    for (final terminal in terminals) {
      if (_terminalUuid != null &&
          _terminalUuid!.isNotEmpty &&
          terminal.uuid == _terminalUuid) {
        return terminal;
      }
      if (_tid != null && _tid!.isNotEmpty && terminal.tid == _tid) {
        return terminal;
      }
    }

    return terminals.first;
  }
}
