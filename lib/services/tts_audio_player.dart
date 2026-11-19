/// 顺序播放「离线朗读」整篇音频的播放器。
///
/// 与 `AudioPlayback`（跟读回放）分开：那边只放一段录音、不等播完；
/// 这里要**一句接一句**放完整篇，还要把「当前第几句」回传给界面高亮。
///
/// 只用 audioplayers 的本地文件播放；缓存文件是 AAC（编码器故障时是 WAV），
/// 与点句朗读播缓存走同一条路（`KokoroSpeech._playCached`），真机验证过。
library;

import 'dart:async';
import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';

/// 播放器接口（测试里换成假实现，不碰平台通道）。
abstract interface class TtsAudioSequencePlayback {
  /// 依次播放 [files]；每切到第 i 个文件前调 [onIndex]（从 0 开始）。
  ///
  /// [rate] 是**播放速率**（1.0 = 原速）。调用方传的是「朗读语速」换算出来的倍数，
  /// 与生成音频时的采样率无关 —— 变速只在这一层做（33.10）。
  ///
  /// 正常播完 / 被 [stop] 打断都正常返回；播放器本身出错才抛异常。
  Future<void> play(
    List<File> files, {
    required void Function(int index) onIndex,
    double rate,
  });

  /// 立刻停下（正在 await 的 [play] 随后返回）。
  Future<void> stop();

  Future<void> dispose();
}

/// 基于 audioplayers 的实现。
class TtsAudioSequencePlayer implements TtsAudioSequencePlayback {
  AudioPlayer? _player;
  bool _stopped = false;

  /// 当前这一句播完的信号；[stop] 时手动完成，让等待方醒过来。
  Completer<void>? _finished;
  StreamSubscription<void>? _completeSub;

  AudioPlayer get _instance =>
      _player ??= AudioPlayer(playerId: 'tts_audio_article');

  @override
  Future<void> play(
    List<File> files, {
    required void Function(int index) onIndex,
    double rate = 1.0,
  }) async {
    _stopped = false;
    final player = _instance;
    try {
      await player.setReleaseMode(ReleaseMode.stop);
      // 整篇朗读也要跟「朗读语速」走（33.10）：以前只有点句朗读的缓存播放会
      // setPlaybackRate，整篇播放固定原速，同一个词两处听起来快慢不一样。
      // 变速失败不致命（有些平台/旧版本不支持），退化成原速继续播。
      try {
        await player.setPlaybackRate(rate);
      } on Exception catch (e) {
        debugPrint('整篇朗读变速失败，按原速播放：$e');
      }
      for (var i = 0; i < files.length; i++) {
        if (_stopped) break;
        onIndex(i);
        final done = Completer<void>();
        _finished = done;
        await _completeSub?.cancel();
        _completeSub = player.onPlayerComplete.listen((_) {
          if (!done.isCompleted) done.complete();
        });
        try {
          await player.play(DeviceFileSource(files[i].path));
          await done.future;
        } on Exception catch (e) {
          if (_stopped) break;
          debugPrint('离线朗读播放失败（第 ${i + 1} 句）：$e');
          rethrow;
        }
      }
    } finally {
      _finished = null;
      await _completeSub?.cancel();
      _completeSub = null;
    }
  }

  @override
  Future<void> stop() async {
    _stopped = true;
    final done = _finished;
    if (done != null && !done.isCompleted) done.complete();
    final player = _player;
    if (player == null) return;
    try {
      await player.stop();
    } catch (e) {
      debugPrint('停止离线朗读播放失败：$e');
    }
  }

  @override
  Future<void> dispose() async {
    await stop();
    final player = _player;
    _player = null;
    try {
      await player?.dispose();
    } catch (e) {
      debugPrint('释放离线朗读播放器失败：$e');
    }
  }
}
