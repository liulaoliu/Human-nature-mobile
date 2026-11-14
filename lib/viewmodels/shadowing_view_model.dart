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
import '../core/shadowing_cycle.dart';
import '../core/shadowing_prefs.dart';
import '../core/shadowing_take.dart';
import '../core/tts_timing.dart' show spokenWordIndex;
import '../core/word_select.dart';
import '../data/prefs_store.dart';
import '../data/repositories/article_repository.dart';
import '../models/document.dart';
import '../services/shadowing_cycler.dart';
import '../services/speech_engine_picker.dart';
import 'current_article_view_model.dart';

/// 跟读页的 ViewModel。
class ShadowingViewModel extends ChangeNotifier {
  ShadowingViewModel({
    required ArticleRepository articles,
    required SpeechPort speech,
    required RecorderPort recorder,
    PlaybackPort? playback,
    PrefsStore? prefsStore,
    CurrentArticleViewModel? currentArticle,
  })  : _articlesRepo = articles,
        _speechPort = speech,
        _recorderPort = recorder,
        _playbackPort = playback,
        // 显式转：`SpeechPort` 与 `SpeechProgressPort` 不相干，`is` 之后不提升。
        _progressPort =
            speech is SpeechProgressPort ? speech as SpeechProgressPort : null,
        _store = prefsStore ?? PrefsStore.memory(),
        _current = currentArticle {
    // 逐词高亮的数据源：系统 TTS 念到哪个词就回报哪几个字符。
    // 写成构造时注册的闭包而不是方法 —— 本类方法数已顶到 40 的门禁上限。
    // 不支持这个端口的实现（网页 / 测试替身）就整段跳过，界面也不亮。
    _progressPort?.setWordListener((int start, int end) {
      if (_disposed || !_playing) return;
      // 引擎报的区间是相对「传给 speak() 的正文」的；SystemSpeech 会先 trim，
      // 所以这里也按 trim 后的文本分词，否则前后空格会把下标整体挪位。
      final at = spokenWordIndex(text.trim(), start, end);
      if (at == highlightWord) return;
      highlightWord = at;
      notifyListeners();
    });
    speechEngine = SpeechEnginePicker(
      // `SpeechEnginePort` 和 `SpeechPort` 是不相干的两个接口，Dart 的类型提升
      // 只认子类型，所以这里显式转一次；转不出来就是「这台设备不给挑引擎」。
      port: speech is SpeechEnginePort ? speech as SpeechEnginePort : null,
      store: _store,
    );
    // 复读编排：放一句 → 我读一句 → 听我读的。
    // 编排逻辑在 services/shadowing_cycler.dart，这里只把钩子接到本类的方法上；
    // 写成公开字段而不是一堆 getter/method —— 本类方法数已顶到 40 的门禁上限。
    cycle = ShadowCycleRunner(
      hooks: ShadowCycleHooks(
        speakReference: play,
        recordOnce: () async {
          await startRecording(fromCycle: true);
          if (!_recording) return false;
          // 等这一遍录完：`_tick()` 判定说完会调 `stopRecording()`，
          // 那里 complete 掉这个 Completer；30 秒兜底防止永久挂住。
          final done = _takeDone = Completer<void>();
          await done.future.timeout(
            const Duration(seconds: 30),
            onTimeout: () {},
          );
          if (_recording) await stopRecording();
          return hasTake;
        },
        playTake: () async {
          await playTake();
          // 回放端口只保证「开始播了」，这里等它真的播完（最多 30 秒），
          // 否则下一句的标准音会和这一遍叠在一起。
          for (var i = 0; i < 300 && playingBack; i++) {
            await Future<void>.delayed(const Duration(milliseconds: 100));
          }
        },
        onStep: (ShadowCycleStep step) {
          if (!_disposed) notifyListeners();
        },
        onDone: (bool completed) {
          if (completed && hasNext) {
            // 一圈走完自动下一句，接着复读 —— 这就是「读一句，下一句」的节奏。
            next();
          }
        },
      ),
    );
  }

  final ArticleRepository _articlesRepo;
  final SpeechPort _speechPort;
  final RecorderPort _recorderPort;

  /// 逐词进度端口；设备 / 测试替身不支持时为 null。
  final SpeechProgressPort? _progressPort;

  /// 挑朗读引擎（列表 + 当前选中 + 落盘）。
  ///
  /// 公开字段而不是 getter：它本身是一组状态，塞进本类会把方法数顶穿门禁。
  late final SpeechEnginePicker speechEngine;

  /// 复读编排（放一句 → 我读一句 → 听我读的）。
  ///
  /// 同样是公开字段：编排逻辑在 `services/shadowing_cycler.dart`，
  /// 本类只提供钩子，加 getter 会顶穿方法数门禁。
  late final ShadowCycleRunner cycle;

  /// 回放器可为空：不传就是「只跟读不回放」。
  ///
  /// 为什么允许为空而不是必填：widget 测试不起平台通道，
  /// 而 `AudioPlayer` 一构造就要碰通道 —— 和 `DeviceRecorder` 一个道理。
  final PlaybackPort? _playbackPort;

  final PrefsStore _store;

  /// 全局「当前文章」：只读，用来决定第一次进来跟哪一篇。
  ///
  /// 跟读**不写回**它 —— 页内「换一篇」只是这一页的临时选择。
  /// 直接读 `_current?.articleId` 而不加 getter：本类方法数已顶到门禁上限。
  final CurrentArticleViewModel? _current;

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

  /// 这一遍录音什么时候「录完了」（给复读编排器等）。
  Completer<void>? _takeDone;

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

  /// 当前朗读到第几个词（0 起）；不朗读 / 停 / 换句时为 null。
  ///
  /// 公开可变字段而不是 getter：本类方法数已顶到 40 的门禁上限。
  /// 只有构造时注册的进度回调会写它，页面只读。
  int? highlightWord;

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
  ///
  /// 全局「当前文章」有篇、这一页还没打开过任何一篇时，直接打开那一篇：
  /// 在精读里选了哪篇，进跟读就接着跟哪篇。
  Future<void> bootstrap() async {
    _busy = true;
    _error = null;
    notifyListeners();
    String? autoOpen;
    try {
      _library = await _articlesRepo.list();
      _prefs = _store.loadShadowingPrefs();
      // 把存下来的语速同步给朗读器，否则第一次读还是默认速度。
      await _speechPort.setRate(_prefs.speechRate);
      await speechEngine.load();
      final global = _current?.articleId;
      if (_article == null && global != null) autoOpen = global;
    } catch (e) {
      _error = '读不到文章列表：$e';
    } finally {
      _busy = false;
      notifyListeners();
    }
    if (autoOpen != null) await openArticle(autoOpen);
  }

  /// 打开一篇（`null` = 回到本页的选文章列表）。
  ///
  /// `null` 不是「回落到全局当前篇」：这是「换一篇」按下去的语义，
  /// 要真的回列表让用户挑。全局当前篇只在 [bootstrap] 第一次进来时用。
  Future<void> openArticle(String? id) async {
    cycle.stop();
    await stopRecording(discard: true);
    await stopPlaying();
    highlightWord = null;
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
    // 换句了，复读这一圈就作废（不然它会在新句子上接着放旧的录音）。
    cycle.stop();
    if (_recording) unawaited(stopRecording(discard: true));
    if (_playing) unawaited(stopPlaying());
    // 换句了，上一句的录音就没用了 —— 顺手删掉，免得攒文件。
    unawaited(clearTake());
    _index = at;
    _verdict = null;
    _elapsedMs = 0;
    highlightWord = null;
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
    highlightWord = null;
    notifyListeners();
    try {
      await _speechPort.speak(text);
    } catch (e) {
      _error = '朗读失败：$e';
    } finally {
      _playing = false;
      // 读完了，最后一个词也不该继续亮着。
      highlightWord = null;
      if (!_disposed) notifyListeners();
    }
  }

  /// 停掉朗读。
  Future<void> stopPlaying() async {
    if (!_playing) return;
    await _speechPort.stop();
    _playing = false;
    highlightWord = null;
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
  ///
  /// [fromCycle] 是复读编排器自己调时传 true：否则「用户手动开录就停掉复读」那条
  /// 会把编排器自己停掉（这个坑踩过）。
  Future<void> startRecording({bool fromCycle = false}) async {
    if (!hasArticle || _recording) return;
    // 用户手动开录 = 他不想等编排器排的步子了，这一圈到此为止
    // （否则编排器会在录音结束后又自己放一遍回放，用户没点它就出声）。
    if (!fromCycle && cycle.running) cycle.stop();
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
      // 告诉复读编排器「这一遍录完了」。
      final done = _takeDone;
      _takeDone = null;
      if (done != null && !done.isCompleted) done.complete();
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
    // 别再让引擎往一个已经销毁的 ViewModel 上回调。
    _progressPort?.setWordListener(null);
    // 复读先停：它会在 await 之间往回回调本类。
    cycle.stop();
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
