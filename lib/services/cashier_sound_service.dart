import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class CashierSoundService {
  final AudioPlayer _audioPlayer = AudioPlayer(playerId: 'cashier-button');
  DateTime? _lastTapAt;
  bool _isInitialized = false;
  bool _isMuted = false;
  double _volume = 0.6;

  static const String _prefVolume = 'cashier_button_volume';
  static const String _prefMuted = 'cashier_button_muted';

  bool get isMuted => _isMuted;
  double get volume => _volume;

  bool get _isLinuxDesktop =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.linux;

  Future<void> initialize() async {
    if (_isInitialized) return;
    try {
      await _loadSettings();
      // Avoid Linux startup channel noise from audio plugin initialization.
      if (_isLinuxDesktop) {
        _isInitialized = true;
        return;
      }
      await _audioPlayer.setReleaseMode(ReleaseMode.stop);
      await _audioPlayer.setVolume(_isMuted ? 0.0 : _volume);
      _isInitialized = true;
    } catch (e) {
      debugPrint('CashierSoundService init failed: $e');
    }
  }

  Future<void> playButtonSound() async {
    if (_isMuted || _isLinuxDesktop) return;
    final now = DateTime.now();
    if (_lastTapAt != null && now.difference(_lastTapAt!).inMilliseconds < 80) {
      return;
    }
    _lastTapAt = now;

    try {
      if (!_isInitialized) {
        await initialize();
      }
      await _audioPlayer.stop();
      await _audioPlayer.play(
        AssetSource('sounds/cashier_button.mp3'),
        volume: _isMuted ? 0.0 : _volume,
      );
    } catch (e) {
      debugPrint('Cashier button sound failed: $e');
    }
  }

  Future<void> setMuted(bool value) async {
    _isMuted = value;
    if (!_isLinuxDesktop) {
      await _audioPlayer.setVolume(_isMuted ? 0.0 : _volume);
    }
    await _saveSettings();
  }

  Future<void> setVolume(double value) async {
    final normalized = value.clamp(0.0, 1.0);
    _volume = normalized;
    if (!_isMuted && !_isLinuxDesktop) {
      await _audioPlayer.setVolume(_volume);
    }
    await _saveSettings();
  }

  Future<void> _loadSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _volume = (prefs.getDouble(_prefVolume) ?? 0.6).clamp(0.0, 1.0);
      _isMuted = prefs.getBool(_prefMuted) ?? false;
    } catch (e) {
      debugPrint('CashierSoundService load settings failed: $e');
      _volume = 0.6;
      _isMuted = false;
    }
  }

  Future<void> _saveSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setDouble(_prefVolume, _volume);
      await prefs.setBool(_prefMuted, _isMuted);
    } catch (e) {
      debugPrint('CashierSoundService save settings failed: $e');
    }
  }

  Future<void> dispose() async {
    if (_isLinuxDesktop) return;
    await _audioPlayer.dispose();
  }
}
