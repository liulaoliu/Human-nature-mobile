/// 回放实现：`audioplayers` 的本地文件播放器。
///
/// 用途只有一个 —— 跟读录完之后「听自己读的」。所以：
///   - 只播本地临时文件，不碰网络；
///   - 播放器**懒创建**：`AudioPlayer()` 一构造就去建平台通道，
///     widget 测试里没有插件实现会抛 `MissingPluginException`
///     （和 `DeviceRecorder` 同一个理由）；
///   - 进度靠事件缓存，`progress` 是纯读，不去 await 任何东西。
library;

import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';

import '../core/ports.dart';

/// 基于 `audioplayers` 的本地文件回放。
class AudioPlayback implements PlaybackPort {
  AudioPlayer? _playerInstance;
  Duration _position = Duration.zero;
  Duration? _duration;
  bool _playing = false;
  final List<StreamSubscription<Object?>> _subs = [];

  AudioPlayer get _player => _playerInstance ??= _build();

  AudioPlayer _build() {
    final p = AudioPlayer();
    // 跟读回放只放一次，放完就停（不进 loop）。
    p.setReleaseMode(ReleaseMode.stop);
    _subs
      ..add(p.onPositionChanged.listen((pos) {
        _position = pos;
      }))
      ..add(p.onDurationChanged.listen((d) {
        _duration = d == Duration.zero ? null : d;
      }))
      ..add(p.onPlayerStateChanged.listen((s) {
        _playing = s == PlayerState.playing;
      }))
      ..add(p.onPlayerComplete.listen((_) {
        _playing = false;
        _position = Duration.zero;
      }));
    return p;
  }

  @override
  bool get isPlaying => _playing;

  @override
  double? get progress {
    final total = _duration;
    if (total == null || total.inMilliseconds <= 0) return null;
    final ratio = _position.inMilliseconds / total.inMilliseconds;
    return ratio.clamp(0.0, 1.0);
  }

  @override
  Future<void> play(String path) async {
    if (path.trim().isEmpty) return;
    try {
      _position = Duration.zero;
      _duration = null;
      await _player.stop();
      await _player.play(DeviceFileSource(path));
      _playing = true;
    } catch (e) {
      debugPrint('回放失败：$e');
      _playing = false;
      rethrow;
    }
  }

  @override
  Future<void> stop() async {
    _playing = false;
    _position = Duration.zero;
    final p = _playerInstance;
    // 没播过就别为了一次 stop 去建播放器。
    if (p == null) return;
    try {
      await p.stop();
    } catch (e) {
      debugPrint('停止回放失败：$e');
    }
  }

  @override
  Future<void> dispose() async {
    await stop();
    for (final s in _subs) {
      await s.cancel();
    }
    _subs.clear();
    final p = _playerInstance;
    _playerInstance = null;
    _duration = null;
    try {
      await p?.dispose();
    } catch (e) {
      debugPrint('释放回放器失败：$e');
    }
  }
}
