/// 「朗读全文」：只播已经离线生成好的整篇音频。
///
/// 为什么不在线合成：Kokoro 在这台手机上约 5–7 秒一句，点一下要等十几秒才出声，
/// 而且会跟正在跑的预生成抢 CPU（用户 2026-11-17 明确：朗读全文只针对已生成的篇）。
/// 所以这里只认 `TtsAudioCache` 里的文件；没生成过就提示先生成。
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../core/tts_provider.dart' show neuralRateOf;
import '../core/tts_text.dart' show normalizeTtsText;
import '../models/document.dart';
import '../services/tts_audio_cache.dart';
import '../services/tts_audio_player.dart';

/// 整篇离线朗读的播放状态。
class ArticleAudioViewModel extends ChangeNotifier {
  ArticleAudioViewModel({
    TtsAudioCache? audioCache,
    TtsAudioSequencePlayback? player,
    this.rateOf,
  }) : _cache = audioCache,
       _player = player ?? TtsAudioSequencePlayer();

  final TtsAudioCache? _cache;
  final TtsAudioSequencePlayback _player;

  /// 当前朗读语速的读数（0.1–1.5 那种「档位值」）。
  ///
  /// 用一个回调而不是注入 `TtsViewModel`：这个 VM 只关心「开播这一刻该多快」，
  /// 而且单测里能直接给个常量，不必拖起整个朗读设置链路（33.10）。
  final double Function()? rateOf;
  String? _articleId;
  String? _sentenceId;
  bool _playing = false;
  String? _error;
  int _token = 0;
  bool _disposed = false;

  /// 正在朗读全文（含两句之间的间隙）。
  bool get playing => _playing;

  /// 正在播的那一篇（换篇时界面据此判断要不要显示成「播放中」）。
  String? get articleId => _articleId;

  /// 正在播的那一句（界面高亮用）；没在播时为 null。
  String? get sentenceId => _sentenceId;

  /// 上一次启动失败的原因（没生成 / 文件缺失 / 播放器报错）。
  String? get error => _error;

  /// 从 [fromSentenceId]（没给 / 找不到就从头）开始，播完整篇。
  ///
  /// 返回时只表示「已经开播 / 启动失败」，不等待整篇播完。
  Future<void> play(SavedArticle article, {String? fromSentenceId}) async {
    final cache = _cache;
    final token = ++_token;
    _error = null;
    await _player.stop();
    if (_disposed || token != _token) return;
    if (cache == null) {
      _fail('离线朗读没有接上，重启 App 再试');
      return;
    }

    final entry = await cache.entryOf(article.id);
    if (_disposed || token != _token) return;
    if (entry == null) {
      _fail('这篇还没生成离线朗读；先在右上角 ⋮ →「生成离线朗读」里生成一遍');
      return;
    }

    final ids = <String>[];
    final files = <File>[];
    String? missing;
    // 用同一个 normalizeTtsText 算 key —— 生成时就是这个文本进的缓存。
    final sentences = article.sentences
        .where((s) => normalizeTtsText(s.text).isNotEmpty)
        .toList();
    for (var i = 0; i < sentences.length; i++) {
      final text = normalizeTtsText(sentences[i].text);
      final file = await cache.fileFor(entry, text);
      if (_disposed || token != _token) return;
      if (file == null) {
        missing ??= '第 ${i + 1} 句';
        continue;
      }
      ids.add(sentences[i].id);
      files.add(file);
    }
    if (missing != null) {
      _fail('离线音频不完整（$missing 缺文件），重新生成一遍');
      return;
    }
    if (files.isEmpty) {
      _fail('这篇没有可朗读的句子');
      return;
    }

    var start = 0;
    if (fromSentenceId != null) {
      final i = ids.indexOf(fromSentenceId);
      if (i >= 0) start = i;
    }

    _articleId = article.id;
    _playing = true;
    _sentenceId = ids[start];
    _notify();
    unawaited(_run(token, start, ids, files.sublist(start)));
  }

  Future<void> _run(
    int token,
    int start,
    List<String> ids,
    List<File> files,
  ) async {
    // 变速倍数在**开播那一刻**取一次：整篇播到一半改设置不该突然变调。
    final rate = neuralRateOf(rateOf?.call() ?? 0.45).toDouble();
    try {
      await _player.play(
        files,
        rate: rate,
        onIndex: (i) {
          if (_disposed || token != _token) return;
          _sentenceId = ids[start + i];
          _notify();
        },
      );
    } catch (e) {
      if (!_disposed && token == _token) _error = '播放失败：$e';
    } finally {
      if (!_disposed && token == _token) {
        _playing = false;
        _sentenceId = null;
        _articleId = null;
        _notify();
      }
    }
  }

  /// 停下整篇朗读（界面上的「停止」）。
  Future<void> stop() async {
    _token++;
    _playing = false;
    _sentenceId = null;
    _articleId = null;
    _notify();
    await _player.stop();
  }

  void _fail(String message) {
    _error = message;
    _playing = false;
    _sentenceId = null;
    _articleId = null;
    _notify();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _token++;
    unawaited(_player.dispose());
    super.dispose();
  }
}
