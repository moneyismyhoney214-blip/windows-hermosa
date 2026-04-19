import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:vibration/vibration.dart';

/// Plays the request-waiter sound and triggers a vibration pattern.
///
/// Used when another waiter sends a [WaiterMessage.isCall] to this device.
///
/// Reliability notes:
///   * The sound is played twice with a short gap — one-shot playback on
///     older Android builds sometimes drops due to audio focus contention,
///     and a restaurant bell is expected to ring more than once anyway.
///   * Vibration fires in parallel with audio so a muted device still
///     alerts physically.
///   * Calls are debounced: two calls arriving within 900ms collapse into
///     one play to avoid echo/stutter when multiple peers ring at once.
class WaiterNotificationService {
  static const _soundAssetPath = 'waiter_module/sounds/requestwaiter.mp3';
  static const _repeatGap = Duration(milliseconds: 700);
  static const _debounceWindow = Duration(milliseconds: 900);

  final AudioPlayer _player = AudioPlayer(playerId: 'waiter_call_bell');
  bool? _vibratorAvailable;
  DateTime? _lastPlayAt;

  Future<void> playCall() async {
    final now = DateTime.now();
    if (_lastPlayAt != null && now.difference(_lastPlayAt!) < _debounceWindow) {
      return; // already ringing
    }
    _lastPlayAt = now;

    // Run audio + vibration in parallel — neither should starve the other.
    await Future.wait([
      _playSoundTwice(),
      _vibrate(),
    ]);
  }

  Future<void> _playSoundTwice() async {
    await _playSoundOnce();
    await Future.delayed(_repeatGap);
    await _playSoundOnce();
  }

  Future<void> _playSoundOnce() async {
    try {
      await _player.stop();
      await _player.setReleaseMode(ReleaseMode.stop);
      await _player.play(AssetSource(_soundAssetPath));
    } catch (e) {
      debugPrint('⚠️ Waiter call sound failed: $e');
    }
  }

  Future<void> _vibrate() async {
    try {
      _vibratorAvailable ??= await Vibration.hasVibrator();
      if (_vibratorAvailable == true) {
        await Vibration.vibrate(pattern: [0, 400, 200, 400, 200, 600]);
      }
    } catch (e) {
      debugPrint('⚠️ Waiter call vibration failed: $e');
    }
  }

  Future<void> dispose() async {
    try {
      await _player.dispose();
    } catch (_) {}
  }
}
