/// 「预生成朗读」的状态机与写入方。
///
/// 精读页只读这里的 [status] / [entry] / 进度；生成、取消、删除都走这里。
/// 这样 `ReaderViewModel` 不用再背一套缓存状态（也就不会变成上帝类）。
library;

import 'dart:async';

import 'package:flutter/foundation.dart';

import '../core/tts_provider.dart' show TtsProvider, defaultTtsVoice;
import '../data/tts_prefs.dart';
import '../models/document.dart';
import '../models/tts_audio.dart';
import '../services/tts_audio_cache.dart';
import '../services/tts_audio_service.dart';

/// 离线朗读的生成状态。
enum OfflineAudioStatus { idle, generating, ready, failed }

/// 某一篇文章的离线朗读状态。
class OfflineAudioViewModel extends ChangeNotifier {
  OfflineAudioViewModel({
    TtsAudioCache? cache,
    TtsAudioService? service,
    this.prefs,
    this.synthesizeToFile,
    this.onCancel,
  }) : _cache = cache ?? service?.cache,
       _service =
           service ?? (cache == null ? null : TtsAudioService(cache: cache));

  final TtsAudioCache? _cache;
  final TtsAudioService? _service;
  final TtsPrefs? prefs;

  /// 逐句合成；返回**实际**写出的文件路径（原生可能把 `.aac` 退成 `.wav`）。
  final Future<String> Function(String text, String path)? synthesizeToFile;

  /// 取消时通知原生停止（否则只能等当前这一句合成完）。
  final Future<void> Function()? onCancel;

  String? _articleId;
  OfflineAudioStatus _status = OfflineAudioStatus.idle;
  int _done = 0;
  int _total = 0;
  int _bytes = 0;
  String? _error;
  bool _cancel = false;
  TtsAudioEntry? _entry;
  int _generation = 0;

  String? get articleId => _articleId;
  OfflineAudioStatus get status => _status;
  int get done => _done;
  int get total => _total;
  int get bytes => _bytes;
  String? get error => _error;
  TtsAudioEntry? get entry => _entry;
  bool get supported => _service != null && synthesizeToFile != null;

  /// 打开 / 切换文章时调；读一遍缓存状态。
  Future<void> load(String articleId) async {
    _articleId = articleId;
    _generation++;
    await _load(articleId);
    notifyListeners();
  }

  /// 重新读一遍当前文章（生成 / 删除后调）。
  Future<void> refresh() async {
    final id = _articleId;
    if (id == null) return;
    await _load(id);
    notifyListeners();
  }

  Future<void> _load(String articleId) async {
    final cache = _cache;
    if (cache == null) return;
    try {
      final entry = await cache.entryOf(articleId);
      _entry = entry;
      _bytes = entry?.bytes ?? 0;
      _done = 0;
      _total = entry?.sentenceCount ?? 0;
      _error = null;
      _status = entry == null
          ? OfflineAudioStatus.idle
          : OfflineAudioStatus.ready;
      if (entry != null) unawaited(cache.touch(articleId));
    } catch (e) {
      debugPrint('读取离线朗读状态失败：$e');
    }
  }

  /// 生成整篇。只有 Kokoro 档支持；音色取全局朗读设置。
  Future<void> generate(SavedArticle article) async {
    final service = _service;
    final synthesize = synthesizeToFile;
    final prefs = this.prefs;
    if (_status == OfflineAudioStatus.generating) return;
    if (service == null || synthesize == null || prefs == null) {
      _status = OfflineAudioStatus.failed;
      _error = '离线朗读没有接上，重启 App 再试';
      notifyListeners();
      return;
    }
    if (prefs.loadProvider() != TtsProvider.kokoro) {
      _status = OfflineAudioStatus.failed;
      _error = '先把朗读档位切到 Kokoro，再来生成离线音频';
      notifyListeners();
      return;
    }

    _articleId = article.id;
    final voice =
        prefs.loadVoice(TtsProvider.kokoro) ??
        defaultTtsVoice(TtsProvider.kokoro) ??
        'af_heart';
    _status = OfflineAudioStatus.generating;
    _error = null;
    _done = 0;
    _total = article.sentences.where((s) => s.text.trim().isNotEmpty).length;
    _bytes = 0;
    _cancel = false;
    notifyListeners();

    final articleId = article.id;
    final token = ++_generation;
    bool live() => token == _generation && _articleId == articleId;
    try {
      final result = await service.generate(
        article,
        voice: voice,
        synthesize: synthesize,
        isCancelled: () => _cancel,
        onProgress: (done, total) {
          if (!live()) return;
          _done = done;
          _total = total;
          notifyListeners();
        },
      );
      if (!live()) return;
      _entry = result.entry;
      _bytes = result.entry.bytes;
      _done = result.entry.sentenceCount;
      _total = result.entry.sentenceCount;
      _status = OfflineAudioStatus.ready;
      _error = null;
    } on TtsAudioCancelled {
      if (!live()) return;
      _status = _entry == null
          ? OfflineAudioStatus.idle
          : OfflineAudioStatus.ready;
      _done = 0;
      _total = _entry?.sentenceCount ?? 0;
      _error = null;
    } catch (e) {
      if (!live()) return;
      _status = OfflineAudioStatus.failed;
      _error = _message(e);
    } finally {
      if (token == _generation) {
        _cancel = false;
        notifyListeners();
      }
    }
  }

  /// 取消正在跑的生成。除了在句子之间检查，还会通知原生停掉当前合成。
  void cancel() {
    if (_status != OfflineAudioStatus.generating) return;
    _cancel = true;
    final cb = onCancel;
    if (cb != null) {
      unawaited(
        cb().catchError((Object e) {
          debugPrint('取消离线朗读时停止原生合成失败：$e');
        }),
      );
    }
    notifyListeners();
  }

  /// 删掉当前文章的离线音频。
  Future<void> delete() async {
    final id = _articleId;
    if (id == null) return;
    await deleteFor(id);
  }

  /// 删掉指定文章的离线音频（删文章时也调）。
  Future<void> deleteFor(String articleId) async {
    final cache = _cache;
    if (cache == null) return;
    try {
      await cache.deleteArticle(articleId);
      if (_articleId != articleId) return;
      _entry = null;
      _bytes = 0;
      _done = 0;
      _total = 0;
      _error = null;
      _status = OfflineAudioStatus.idle;
    } catch (e) {
      if (_articleId != articleId) return;
      _status = OfflineAudioStatus.failed;
      _error = '删除失败：${_short(e)}';
    }
    notifyListeners();
  }

  /// 关掉文章（返回列表）时清状态；正在跑的生成结果不再回填。
  void clear() {
    _articleId = null;
    _generation++;
    _status = OfflineAudioStatus.idle;
    _entry = null;
    _bytes = 0;
    _done = 0;
    _total = 0;
    _error = null;
    notifyListeners();
  }

  String _message(Object error) => '生成失败：${_short(error)}';

  String _short(Object error) {
    final full = error.toString().replaceAll(RegExp(r'\s+'), ' ').trim();
    if (full.length <= 120) return full;
    return '${full.substring(0, 120)}…';
  }
}
