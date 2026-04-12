import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Sound Service for playing audio notifications
///
/// Plays sounds when:
/// - New order arrives
/// - Order becomes ready
/// - Urgent/long waiting orders
class SoundService {
  static final SoundService _instance = SoundService._internal();
  factory SoundService() => _instance;
  SoundService._internal();

  final Set<AudioPlayer> _activePlayers = <AudioPlayer>{};
  final Set<String> _availableAssets = <String>{};
  bool _isInitialized = false;
  bool _isDisposing = false;
  bool _isMuted = false;
  static const String _newOrderAsset = 'sounds/new_order.mp3';
  static const String _bumpAsset = 'sounds/bump.mp3';

  bool get isInitialized => _isInitialized;
  bool get isMuted => _isMuted;
  bool get _hasAudioFiles => _availableAssets.isNotEmpty;

  /// Initialize the sound service
  Future<void> initialize() async {
    if (_isDisposing) return;
    if (_isInitialized) {
      if (_availableAssets.isEmpty) {
        await _loadAvailableAssets();
      }
      return;
    }

    try {
      await _loadAvailableAssets();
      _isInitialized = true;
      debugPrint('✅ SoundService initialized');
    } catch (e) {
      debugPrint('❌ Error initializing SoundService: $e');
      _isInitialized = false;
    }
  }

  Future<void> _loadAvailableAssets() async {
    _availableAssets.clear();

    for (final asset in {_newOrderAsset, _bumpAsset}) {
      try {
        await rootBundle.load('assets/$asset');
        _availableAssets.add(asset);
      } catch (e) {
        debugPrint('⚠️ Missing sound asset: assets/$asset ($e)');
      }
    }

    if (_hasAudioFiles) {
      debugPrint('✅ Audio files found: ${_availableAssets.join(', ')}');
    } else {
      debugPrint('⚠️ No audio files found, using fallback sounds');
    }
  }

  Future<void> _playAssetOrFallback(
    String asset, {
    required String label,
    bool fallbackToSystem = true,
  }) async {
    if (_isMuted) return;
    if (!_isInitialized) {
      if (fallbackToSystem) {
        _playSystemSound();
      }
      return;
    }

    if (_availableAssets.isEmpty) {
      await _loadAvailableAssets();
    }

    if (!_availableAssets.contains(asset)) {
      debugPrint('⚠️ Missing configured sound asset for $label: assets/$asset');
      if (fallbackToSystem) {
        _playSystemSound();
      }
      return;
    }

    try {
      final player = AudioPlayer();
      _activePlayers.add(player);

      try {
        await player.setReleaseMode(ReleaseMode.release);
        await player.setPlayerMode(PlayerMode.mediaPlayer);
        await player.setVolume(1.0);
      } catch (e) {
        debugPrint('⚠️ Could not fully configure audio player: $e');
      }

      try {
        await player.setAudioContext(
          AudioContext(
            android: AudioContextAndroid(
              isSpeakerphoneOn: true,
              stayAwake: true,
              contentType: AndroidContentType.sonification,
              usageType: AndroidUsageType.notification,
              audioFocus: AndroidAudioFocus.gain,
            ),
          ),
        );
      } catch (e) {
        debugPrint('⚠️ Could not set audio context: $e');
      }

      await player.play(AssetSource(asset), volume: 1.0);
      unawaited(_disposePlaybackPlayer(player));
      debugPrint('🔊 $label sound played');
    } catch (e) {
      debugPrint('⚠️ Could not play $label sound ($asset): $e');
      if (fallbackToSystem) {
        _playSystemSound();
      }
    }
  }

  Future<void> _disposePlaybackPlayer(AudioPlayer player) async {
    try {
      await player.onPlayerComplete.first.timeout(const Duration(seconds: 3));
    } catch (_) {}

    _activePlayers.remove(player);
    try {
      await player.dispose();
    } catch (e) {
      debugPrint('⚠️ Could not dispose playback player: $e');
    }
  }

  /// Play new order notification sound
  Future<void> playNewOrderSound() async {
    await _playAssetOrFallback(_newOrderAsset, label: 'New order');
  }

  /// Play order ready notification sound
  Future<void> playOrderReadySound() async {
    await _playAssetOrFallback(_bumpAsset, label: 'Order ready');
  }

  /// Play urgent notification sound
  Future<void> playUrgentSound() async {
    if (_isMuted) return;

    if (_availableAssets.contains(_newOrderAsset)) {
      await _playAssetOrFallback(_newOrderAsset, label: 'Urgent');
      await Future.delayed(const Duration(milliseconds: 200));
      await _playAssetOrFallback(
        _newOrderAsset,
        label: 'Urgent',
        fallbackToSystem: false,
      );
      return;
    }

    _playSystemSound();
    await Future.delayed(const Duration(milliseconds: 200));
    _playSystemSound();
    debugPrint('🔊 Urgent fallback sound played');
  }

  /// Play success sound
  Future<void> playSuccessSound() async {
    await _playAssetOrFallback(_bumpAsset, label: 'Success');
  }

  /// Play error sound
  Future<void> playErrorSound() async {
    await _playAssetOrFallback(_newOrderAsset, label: 'Error');
  }

  /// Play test sound
  Future<void> playTestSound() async {
    await _playAssetOrFallback(_newOrderAsset, label: 'Test');
  }

  /// Fallback to system sound
  void _playSystemSound() {
    if (_isMuted) return;

    try {
      SystemSound.play(SystemSoundType.click);
      debugPrint('🔊 System sound played');
    } catch (e) {
      debugPrint('❌ Could not play system sound: $e');
    }
  }

  /// Mute/unmute toggle
  void toggleMute() {
    _isMuted = !_isMuted;
    debugPrint(_isMuted ? '🔇 Sound muted' : '🔊 Sound unmuted');
  }

  /// Mute
  void mute() {
    _isMuted = true;
    debugPrint('🔇 Sound muted');
  }

  /// Unmute
  void unmute() {
    _isMuted = false;
    debugPrint('🔊 Sound unmuted');
  }

  /// Stop playing
  Future<void> stop() async {
    if (!_isInitialized || _activePlayers.isEmpty) return;

    final players = _activePlayers.toList(growable: false);
    _activePlayers.clear();
    for (final player in players) {
      try {
        await player.stop();
        await player.dispose();
      } catch (e) {
        debugPrint('Error stopping sound: $e');
      }
    }
  }

  /// Play bump button sound
  Future<void> playBumpSound() async {
    await _playAssetOrFallback(_bumpAsset, label: 'Bump');
  }

  /// Dispose
  Future<void> dispose() async {
    if (_isDisposing) return;
    _isDisposing = true;

    final players = _activePlayers.toList(growable: false);
    _activePlayers.clear();
    for (final player in players) {
      try {
        await player.dispose();
      } catch (e) {
        debugPrint('⚠️ SoundService dispose skipped error: $e');
      }
    }
    _availableAssets.clear();
    _isInitialized = false;
    _isDisposing = false;
    debugPrint('🗑️ SoundService disposed');
  }
}
