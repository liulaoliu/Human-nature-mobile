/// 跟读：一句一句「听标准音 → 自己读 → 当场判一下 → 听自己读的」。
///
/// 三层分工（和别的模块一致）：
///   - **纯函数**在 `core/recording.dart`（上限 / 阈值）、`core/shadowing_take.dart`
///     （底噪跟踪、什么时候收、读得算不算过）、`core/shadowing_prefs.dart`
///     （显示模式 / 麦克风 / 静音时长 / 回放放大）、`core/tts_timing.dart`
///     （将来做逐词高亮时用）；
///   - **本文件**只做状态编排：文章 → 句子 → 读 → 录 → 判 → 回放 → 下一句；
///   - **平台能力**通过 `core/ports.dart` 的 `SpeechPort` / `RecorderPort` /
///     `PlaybackPort` 注入，所以整条流程能用假实现跑测试，
///     不需要真麦克风、真语音引擎、真播放器。
///
/// 一条硬约束：**录音不留档**。临时文件只活到下一次换句 / 退出页面 / 下次开录
/// （中间那段时间是给用户回放自己读的那一遍），之后 `clearTake()` 删掉；
/// 音频绝不上传、不进任何存储，跟读记录里只有时长。
library;

import 'dart:async';

import 'package:flutter/foundation.dart';

import '../core/ports.dart';
import '../core/recording.dart';
import '../core/shadowing_prefs.dart';
import '../core/shadowing_take.dart';
import '../core/word_select.dart';
import '../data/prefs_store.dart';
import '../data/repositories/article_repository.dart';
import '../models/document.dart';
import '../services/speech_engine_picker.dart';

/// 跟读页的 ViewModel。
class ShadowingViewModel extends ChangeNotifier {
  ShadowingViewModel({
    required ArticleRepository articles,
    required SpeechPort speech,
    required RecorderPort recorder,
    PlaybackPort? playback,
    PrefsStore? prefsStore,
  })  : _articlesRepo = articles,
        _speechPort = speech,
        _recorderPort = recorder,
        _playbackPort = playback,
        _store = prefsStore ?? PrefsStore.memory() {
    speechEngine = SpeechEnginePicker(
      // `SpeechEnginePort` 和 `SpeechPort` 是不相干的两个接口，Dart 的类型提升
      // 只认子类型，所以这里显式转一次；转不出来就是「这台设备不给挑引擎」。
      port: speech is SpeechEnginePort ? speech as SpeechEnginePort : null,
      store: _store,
    );
  }

  final ArticleRepository _articlesRepo;
  final SpeechPort _speechPort;
  final RecorderPort _recorderPort;

  /// 挑朗读引擎（列表 + 当前选中 + 落盘）。
  ///
  /// 公开字段而不是 getter：它本身是一组状态，塞进本类会把方法数顶穿门禁。
  late final SpeechEnginePicker speechEngine;

  /// 回放器可为空：不传就是「只跟读不回放」。
  ///
  /// 为什么允许为空而不是必填：widget 测试不起平台通道，
  /// 而 `AudioPlayer` 一构造就要碰通道 —— 和 `DeviceRecorder` 一个道理。
  final PlaybackPort? _playbackPort;

  final PrefsStore _store;

  List<ArticleRow> _library = const <ArticleRow>[];
  SavedArticle? _article;
  int _index = 0;

  ShadowingPrefs _prefs = defaultShadowingPrefs;
  TakeTracker? _tracker;
  Timer? _poll;

  bool _busy = false;
  bool _playing = false;
  bool _recording = false;
  int _elapsedMs = 0;
  double _level = 0;
  TakeVerdict? _verdict;
  String? _error;
  String _notice = '';
  bool _disposed = false;

  /// 文章列表（挑一篇来跟）。
  List<ArticleRow> get library => _library;

  /// 当前文章。
  SavedArticle? get article => _article;

  /// 当前句子的序号（0 起）。
  int get index => _index;

  /// 当前文章的句子。
  List<Sentence> get sentences => _article?.sentences ?? const <Sentence>[];

  /// 当前句子；没文章时 null。
  Sentence? get sentence =>
      _index >= 0 && _index < sentences.length ? sentences[_index] : null;

  /// 当前句子正文。
  String get text => sentence?.text ?? '';

  /// 本机偏好。
  ShadowingPrefs get prefs => _prefs;

  /// 正在读标准音。
  bool get playing => _playing;

  /// 正在录。
  bool get recording => _recording;

  /// 正在回放自己刚读的那一遍。
  bool get playingBack => _playbackPort?.isPlaying ?? false;

  /// 有没有可以回放的录音（录完且没换句 / 没重录时才有）。
  bool get hasTake => (_recorderPort.lastPath ?? '').isNotEmpty;

  /// 这次录了多久（毫秒）。
  int get elapsedMs => _elapsedMs;

  /// 当前电平 0–1（界面画音量条）。
  double get level => _level;

  /// 上一次的判定；还没录过是 null。
  TakeVerdict? get verdict => _verdict;

  bool get busy => _busy;
  String? get error => _error;
  String get notice => _notice;

  /// 有文章可跟吗。
  bool get hasArticle => _article != null && sentences.isNotEmpty;

  /// 还有下一句吗。
  bool get hasNext => _index + 1 < sentences.length;

  /// 还有上一句吗。
  bool get hasPrev => _index > 0;

  /// 这句的参考时长（秒）：按平均朗读速度估，用于「读得太快/太慢」的判断。
  double get estimatedSec {
    final n = wordSpans(text).length;
    if (n == 0) return 0;
    // 每分钟约 150 词 → 每秒 2.5 词。
    return n / 2.5;
  }

  /// 这次录音的兜底上限（毫秒）。
  int get capMs => recordCapMs(estimatedSec);

  /// 读文章列表 + 本机偏好。
  Future<void> bootstrap() async {
    _busy = true;
    _error = null;
    notifyListeners();
    try {
      _library = await _articlesRepo.list();
      _prefs = _store.loadShadowingPrefs();
      // 把存下来的语速同步给朗读器，否则第一次读还是默认速度。
      await _speechPort.setRate(_prefs.speechRate);
      await speechEngine.load();
    } catch (e) {
      _error = '读不到文章列表：$e';
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  /// 打开一篇（`null` = 回到选文章）。
  Future<void> openArticle(String? id) async {
    await stopRecording(discard: true);
    await stopPlaying();
    await clearTake();
    if (id == null) {
      _article = null;
      _index = 0;
      _verdict = null;
      notifyListeners();
      return;
    }
    _busy = true;
    _error = null;
    notifyListeners();
    try {
      _article = await _articlesRepo.load(id);
      _index = 0;
      _verdict = null;
      if (_article == null) _error = '这篇文章找不到了';
    } catch (e) {
      _error = '打不开这篇文章：$e';
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  /// 跳到第几句。
  void select(int at) {
    if (at < 0 || at >= sentences.length || at == _index) return;
    if (_recording) unawaited(stopRecording(discard: true));
    if (_playing) unawaited(stopPlaying());
    // 换句了，上一句的录音就没用了 —— 顺手删掉，免得攒文件。
    unawaited(clearTake());
    _index = at;
    _verdict = null;
    _elapsedMs = 0;
    notifyListeners();
  }

  /// 下一句。
  void next() => select(_index + 1);

  /// 上一句。
  void prev() => select(_index - 1);

  /// 读这一句。
  Future<void> play() async {
    if (!hasArticle || _playing) return;
    _playing = true;
    _error = null;
    notifyListeners();
    try {
      await _speechPort.speak(text);
    } catch (e) {
      _error = '朗读失败：$e';
    } finally {
      _playing = false;
      if (!_disposed) notifyListeners();
    }
  }

  /// 停掉朗读。
  Future<void> stopPlaying() async {
    if (!_playing) return;
    await _speechPort.stop();
    _playing = false;
    if (!_disposed) notifyListeners();
  }

  /// 听自己刚读的那一遍。
  ///
  /// 没有录音时给一句提示而不是静默 —— 用户点了按钮总得知道为什么没声音。
  Future<void> playTake() async {
    final playback = _playbackPort;
    final path = _recorderPort.lastPath;
    if (playback == null) {
      _notice = '这台设备没有回放功能';
      notifyListeners();
      return;
    }
    if ((path ?? '').isEmpty) {
      _notice = '先读一遍，才有的听';
      notifyListeners();
      return;
    }
    _error = null;
    _notice = '';
    try {
      // 标准音和回放同时出声只会互相盖住，先把标准音停了。
      await stopPlaying();
      await playback.play(path!);
    } catch (e) {
      _error = '回放失败：$e';
    } finally {
      if (!_disposed) notifyListeners();
    }
  }

  /// 停掉回放。
  Future<void> stopPlayback() async {
    await _playbackPort?.stop();
    if (!_disposed) notifyListeners();
  }

  /// 删掉这次录的临时文件（换句 / 退出时调）。
  Future<void> clearTake() async {
    if ((_recorderPort.lastPath ?? '').isEmpty) return;
    await stopPlayback();
    await _recorderPort.clearTake();
    if (!_disposed) notifyListeners();
  }

  /// 开始录这一句。
  Future<void> startRecording() async {
    if (!hasArticle || _recording) return;
    _error = null;
    _notice = '';
    _verdict = null;
    _elapsedMs = 0;
    _level = 0;
    // 重录之前把上一条回放停掉：一边放旧的一边录新的，
    // 麦克风会把回放也录进去。
    await stopPlayback();
    try {
      if (!await _recorderPort.ensurePermission()) {
        _error = '没拿到麦克风权限，去系统设置里开一下';
        notifyListeners();
        return;
      }
      await _recorderPort.start();
      _tracker = TakeTracker(hangoverMs: _prefs.hangoverMs);
      _tracker!.start(Duration.zero);
      _recording = true;
      _poll?.cancel();
      _poll = Timer.periodic(
        const Duration(milliseconds: levelPushMs),
        (_) => unawaited(_tick()),
      );
      notifyListeners();
    } catch (e) {
      _error = '开不了录音：$e';
      _recording = false;
      notifyListeners();
    }
  }

  Future<void> _tick() async {
    final tracker = _tracker;
    if (!_recording || tracker == null) return;
    final level = await _recorderPort.amplitude();
    _level = level;
    _elapsedMs += levelPushMs;
    final at = Duration(milliseconds: _elapsedMs);
    tracker.observe(level, at);
    if (!_disposed) notifyListeners();
    if (tracker.shouldStop(at) || tracker.reachedCap(at, capMs)) {
      await stopRecording();
    }
  }

  /// 停止录音并判一下（`discard: true` 是放弃，不判定）。
  Future<void> stopRecording({bool discard = false}) async {
    if (!_recording) return;
    _recording = false;
    _poll?.cancel();
    _poll = null;
    final tracker = _tracker;
    _tracker = null;
    try {
      if (discard) {
        await _recorderPort.discard();
        _elapsedMs = 0;
        _level = 0;
      } else {
        final ms = await _recorderPort.stop();
        _elapsedMs = ms ?? _elapsedMs;
        _verdict = judgeTake(
          elapsedMs: _elapsedMs,
          voiceHeard: tracker?.voiceHeard ?? false,
          estimatedSec: estimatedSec,
        );
      }
    } catch (e) {
      _error = '收录音失败：$e';
    } finally {
      _level = 0;
      if (!_disposed) notifyListeners();
    }
  }

  /// 换显示模式（整篇 / 聚焦 / 单块），存本机。
  Future<void> setViewMode(ShadowingViewMode mode) async {
    _prefs = _prefs.copyWith(viewMode: mode);
    await _store.saveShadowingPrefs(_prefs);
    if (!_disposed) notifyListeners();
  }

  /// 调朗读语速，存本机。
  Future<void> setRate(double rate) async {
    final next = rate.clamp(0.1, 1.0);
    _prefs = _prefs.copyWith(speechRate: next);
    await _speechPort.setRate(next);
    await _store.saveShadowingPrefs(_prefs);
    if (!_disposed) notifyListeners();
  }

  /// 调「说完静音多久算读完」，存本机。
  Future<void> setHangover(int ms) async {
    _prefs = _prefs.copyWith(hangoverMs: ms);
    await _store.saveShadowingPrefs(_prefs);
    if (!_disposed) notifyListeners();
  }

  void clearNotice() {
    if (_notice.isEmpty) return;
    _notice = '';
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _poll?.cancel();
    _poll = null;
    if (_recording) {
      _recording = false;
      unawaited(_recorderPort.discard());
    }
    if (_playing) {
      _playing = false;
      unawaited(_speechPort.stop());
    }
    // 页面走了，临时录音没有留着的理由（尤其是用户的声音）。
    unawaited(_recorderPort.clearTake());
    unawaited(_playbackPort?.dispose() ?? Future<void>.value());
    super.dispose();
  }
}
