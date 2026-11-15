/// 朗读实现：微软 Edge 在线朗读（`flutter_edge_tts`）。
///
/// 为什么要有这一档：系统 TTS 在不少安卓机上音色生硬，离线神经档又吃内存，
/// 而 Edge 的英文音色是目前免费方案里最像真人的 —— Web 版当年就是用它。
/// 代价是**必须联网**：合成走 WebSocket，断网 / 被墙 / 微软改协议都会失败。
/// 失败不吞 —— 往上抛，由 `PickSpeech` 那一层退回系统朗读，用户最多听到一次
/// 「这条用了系统音」，而不是整页哑掉。
///
/// 逐词进度：Edge 的 metadata 里带 `WordBoundary`（offset 是 100ns 刻度），
/// 所以这一档**能**实现 [SpeechProgressPort]，跟读高亮在联网时是亮的。
/// 老版本 `flutter_edge_tts 0.0.3` 会引入 `audio_decode`，和 `neural_tts`
/// 依赖的 `espeak` 抢 `native_toolchain_c` 版本，所以锁在 0.0.2。
library;

import 'dart:async';
import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_edge_tts/flutter_edge_tts.dart';
import 'package:path_provider/path_provider.dart';

import '../core/ports.dart';
import '../core/tts_provider.dart';

/// 一条逐词边界：原文里的字符区间 + 在音频里什么时候开始。
class EdgeWordSpan {
  const EdgeWordSpan({
    required this.start,
    required this.end,
    required this.at,
  });

  /// 相对传给 `speak()` 的文本的字符区间（左闭右开）。
  final int start;
  final int end;

  /// 音频里这一词的起始时间。
  final Duration at;
}

/// 把 Edge 的 metadata 边界换算成「原文里的字符区间 + 时间点」。
///
/// 为什么要自己走一遍原文：metadata 里的 `Text` 只给词本身（还可能带标点），
/// 拿它 `indexOf` 整篇会命中错的位置，所以用游标从上次结束处往后找，
/// 找不到就跳过这一条（宁可不亮，也不亮错位置）。
List<EdgeWordSpan> edgeWordSpans(
  String text,
  List<EdgeTtsMetadataItem> items,
) {
  final spans = <EdgeWordSpan>[];
  var cursor = 0;
  for (final item in items) {
    final word = (item.data.text?.text ?? '').trim();
    if (word.isEmpty) continue;
    final at = Duration(microseconds: item.data.offset ~/ 10);
    final lower = text.toLowerCase();
    var index = lower.indexOf(word.toLowerCase(), cursor);
    if (index < 0) {
      // 兜底：从头上再找一次（微软偶尔会把同一个词拆两段报）。
      index = lower.indexOf(word.toLowerCase());
      if (index < 0) continue;
    }
    spans.add(EdgeWordSpan(start: index, end: index + word.length, at: at));
    cursor = index + word.length;
  }
  return spans;
}

/// Edge 在线朗读。
class EdgeSpeech implements SpeechPort, SpeechProgressPort {
  EdgeSpeech({this.rate = 0.45, String? voice})
    : _voiceId = (voice == null || voice.trim().isEmpty)
          ? defaultTtsVoice(TtsProvider.edge)
          : parseTtsVoice(voice, TtsProvider.edge);

  /// 语速（0–1 档，和其它两档同一套刻度）。
  double rate;

  /// 音色 id（`en-US-AriaNeural` 这种）。
  String? _voiceId;

  FlutterEdgeTts? _client;
  AudioPlayer? _playerInstance;
  final List<StreamSubscription<Object?>> _subs = <StreamSubscription<Object?>>[];
  final List<Timer> _timers = <Timer>[];
  Completer<void>? _done;

  void Function(int start, int end)? _wordListener;
  bool _speaking = false;

  @override
  bool get isSpeaking => _speaking;

  /// 当前音色 id。
  String? get voiceId => _voiceId;

  AudioPlayer get _player => _playerInstance ??= _buildPlayer();

  AudioPlayer _buildPlayer() {
    final p = AudioPlayer();
    p.setReleaseMode(ReleaseMode.stop);
    _subs.add(
      p.onPlayerComplete.listen((_) {
        _finish();
      }),
    );
    return p;
  }

  FlutterEdgeTts _clientFor(String voice) => _client ??= FlutterEdgeTts(
    voice: voice,
    // 要逐词边界就得开这个开关（关着只有整句一条）。
    enableWordBoundary: true,
    enableSentenceBoundary: false,
  );

  @override
  void setWordListener(void Function(int start, int end)? listener) {
    _wordListener = listener;
  }

  /// 换音色：重建 client（音色是构造参数，不能就地改）。
  Future<void> setVoice(String? id) async {
    final next = parseTtsVoice(id, TtsProvider.edge);
    if (next == _voiceId) return;
    _voiceId = next;
    final old = _client;
    _client = null;
    try {
      await old?.close();
    } catch (e) {
      debugPrint('Edge 关闭连接失败：$e');
    }
  }

  @override
  Future<void> setRate(double value) async {
    rate = value.clamp(0.1, 1.0);
  }

  @override
  Future<void> speak(String text) async {
    final raw = text.trim();
    if (raw.isEmpty) return;
    _speaking = true;
    final done = Completer<void>();
    _done = done;
    try {
      final voice = _voiceId ?? defaultTtsVoice(TtsProvider.edge)!;
      final client = _clientFor(voice);
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/edge_tts_${DateTime.now().microsecondsSinceEpoch}.mp3');
      final result = await client.synthesizeToFile(
        raw,
        audioFilePath: file.path,
        prosody: EdgeTtsProsody(rate: edgeRateOf(rate)),
      );
      if (!_speaking) return; // 合成期间用户点了停
      _lastFile = File(result.audioFilePath);
      _scheduleWordSpans(raw, result.result.metadata);
      await _player.stop();
      await _player.play(DeviceFileSource(result.audioFilePath));
      // 等播完（或 stop / 出错）再返回 —— SpeechPort 的约定是「读完才回」。
      await done.future;
    } catch (e) {
      debugPrint('Edge 朗读失败：$e');
      _speaking = false;
      rethrow;
    } finally {
      if (identical(_done, done)) _done = null;
      _cancelTimers();
      _speaking = false;
      _cleanupTemp();
    }
  }

  void _scheduleWordSpans(String text, List<EdgeTtsMetadataItem> items) {
    _cancelTimers();
    final listener = _wordListener;
    if (listener == null) return;
    for (final s in edgeWordSpans(text, items)) {
      _timers.add(
        Timer(s.at, () {
          listener(s.start, s.end);
        }),
      );
    }
  }

  void _cancelTimers() {
    for (final t in _timers) {
      t.cancel();
    }
    _timers.clear();
  }

  void _finish() {
    final done = _done;
    if (done != null && !done.isCompleted) done.complete();
  }

  /// 合成出的 mp3 放在临时目录，播完就删（一首几秒的音频几十 KB，
  /// 不删的话跟读练十篇就攒几 MB）。
  void _cleanupTemp() {
    final f = _lastFile;
    _lastFile = null;
    if (f == null) return;
    unawaited(() async {
      try {
        if (await f.exists()) await f.delete();
      } catch (e) {
        debugPrint('清临时音频失败：$e');
      }
    }());
  }

  File? _lastFile;

  @override
  Future<void> stop() async {
    _speaking = false;
    _cancelTimers();
    _finish();
    try {
      await _playerInstance?.stop();
    } catch (e) {
      debugPrint('Edge 停止失败：$e');
    }
  }

  /// 页面销毁时调。
  Future<void> dispose() async {
    await stop();
    for (final s in _subs) {
      await s.cancel();
    }
    _subs.clear();
    final p = _playerInstance;
    _playerInstance = null;
    try {
      await p?.dispose();
    } catch (e) {
      debugPrint('释放 Edge 播放器失败：$e');
    }
    final c = _client;
    _client = null;
    try {
      await c?.close();
    } catch (e) {
      debugPrint('关闭 Edge 连接失败：$e');
    }
  }
}
