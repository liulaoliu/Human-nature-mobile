/// 逐句速读的 ViewModel。
///
/// 三层分工（和别的模块一致）：
///   - **纯函数**在 `core/speed_read.dart`（目标时长、挖空出题、判分、结算）
///     与 `core/speed_read_prefs.dart`（偏好解析）、`core/doc_signature.dart`
///     （文章键）；
///   - **本文件**只做状态编排：文章 → 句子 → 阶段 → 计时 → 下一句；
///   - **计时由界面驱动**：[tick] 只负责通知刷新，读秒本身从 [elapsedMs]
///     现算 —— 这样测试里不用等真时钟。
library;

import 'package:flutter/foundation.dart';

// 这里必须带前缀：本类有一个同名 getter `articleKey`，不带前缀会被它遮住。
import '../core/doc_signature.dart' as sig;
import '../core/speed_read.dart';
import '../core/speed_read_prefs.dart';
import '../data/prefs_store.dart';
import '../data/repositories/article_repository.dart';
import '../models/document.dart';

/// 速读页的 ViewModel。
class SpeedReadViewModel extends ChangeNotifier {
  SpeedReadViewModel({
    required ArticleRepository articles,
    PrefsStore? prefsStore,
    DateTime Function()? now,
  })  : _articlesRepo = articles,
        _store = prefsStore ?? PrefsStore.memory(),
        _now = now ?? DateTime.now;

  final ArticleRepository _articlesRepo;
  final PrefsStore _store;
  final DateTime Function() _now;

  List<ArticleRow> _library = const <ArticleRow>[];
  SavedArticle? _article;
  String _articleKey = '';
  int _index = 0;
  SpeedReadPhase _phase = SpeedReadPhase.read;
  int _wpm = defaultWpm;
  bool _autoDrill = true;
  DateTime? _startedAt;
  int _readMs = 0;
  bool _slow = false;
  SpeedReadDrill? _drill;
  String _picked = '';
  bool? _drillOk;
  List<SpeedRow> _rows = const <SpeedRow>[];
  bool _busy = false;
  String? _error;
  bool _disposed = false;

  /// 文章列表（挑一篇来速读）。
  List<ArticleRow> get library => _library;

  /// 当前文章。
  SavedArticle? get article => _article;

  /// 当前文章的键（`标识@正文签名`），游标按它存。
  String get articleKey => _articleKey;

  /// 当前文章的句子。
  List<Sentence> get sentences => _article?.sentences ?? const <Sentence>[];

  /// 当前句子；没有文章或读到末尾是 null。
  Sentence? get sentence =>
      _index >= 0 && _index < sentences.length ? sentences[_index] : null;

  /// 当前句子序号（0 起）。
  int get index => _index;

  /// 总句数。
  int get total => sentences.length;

  /// 阶段。
  SpeedReadPhase get phase => _phase;

  /// 语速（词/分钟）。
  int get wpm => _wpm;

  /// 超时是否自动进入拷打。
  bool get autoDrill => _autoDrill;

  /// 这句已经读了多久（毫秒）；揭晓后是定格的用时。
  int get elapsedMs {
    final t0 = _startedAt;
    if (_phase != SpeedReadPhase.read || t0 == null) return _readMs;
    final ms = _now().difference(t0).inMilliseconds;
    return ms < 0 ? 0 : ms;
  }

  /// 揭晓时定格的用时。
  int get readMs => _readMs;

  /// 这句是不是超时了（算「不太理解」）。
  bool get slow => _slow;

  /// 当前这句的拷打题；没出题是 null。
  SpeedReadDrill? get drill => _drill;

  /// 拷打时选中的选项。
  String get picked => _picked;

  /// 拷打对错；还没答是 null。
  bool? get drillOk => _drillOk;

  /// 本轮已读的句子成绩。
  List<SpeedRow> get rows => _rows;

  /// 当前这句的目标时长（毫秒）。
  int get target => sentence == null ? 0 : targetMs(sentence!.text, wpm: _wpm);

  /// 有文章可读吗。
  bool get hasArticle => _article != null && sentences.isNotEmpty;

  bool get busy => _busy;
  String? get error => _error;

  /// 读文章列表 + 本机偏好。
  Future<void> bootstrap() async {
    _busy = true;
    _error = null;
    notifyListeners();
    try {
      _library = await _articlesRepo.list();
      _wpm = _store.loadSpeedWpm();
      _autoDrill = _store.loadSpeedAutoDrill();
    } catch (e) {
      _error = '读不到文章列表：$e';
    } finally {
      _busy = false;
      if (!_disposed) notifyListeners();
    }
  }

  /// 打开一篇（`null` = 回到选文章）。
  Future<void> openArticle(String? id) async {
    _startedAt = null;
    _readMs = 0;
    _slow = false;
    _drill = null;
    _picked = '';
    _drillOk = null;
    _rows = const <SpeedRow>[];
    _phase = SpeedReadPhase.read;
    if (id == null) {
      _article = null;
      _articleKey = '';
      _index = 0;
      _error = null;
      if (!_disposed) notifyListeners();
      return;
    }
    _busy = true;
    _error = null;
    if (!_disposed) notifyListeners();
    try {
      final loaded = await _articlesRepo.load(id);
      _article = loaded;
      if (loaded == null) {
        _error = '这篇文章找不到了';
        _articleKey = '';
        _index = 0;
      } else {
        _articleKey = sig.articleKey(loaded.id, loaded.sentences);
        _index = clampCursor(_store.loadSpeedCursor(_articleKey), loaded.sentences.length);
        // 计时从「打开这篇文章」这一刻开始，否则第一句的用时永远是 0。
        _startedAt = _now();
      }
    } catch (e) {
      _error = '打不开这篇文章：$e';
    } finally {
      _busy = false;
      if (!_disposed) notifyListeners();
    }
  }

  /// 界面每 250ms 调一次，只为刷新读秒。
  ///
  /// 读秒本身由 [elapsedMs] 现算，所以这个函数不推进任何状态 ——
  /// 掉帧或页面不可见时不会把时间算错。
  void tick() {
    if (_phase != SpeedReadPhase.read) return;
    if (!_disposed) notifyListeners();
  }

  /// 「下一句」（底部常驻）：按当前阶段往前推一步。
  ///
  /// `read` → 定格用时；超时且开了自动拷打就**直接进拷打**，否则停在揭晓；
  /// `reveal` → 记成绩翻下一句；`drill` → 不想被拷打，跳过不记对错；
  /// `drillAnswer` → 记成绩翻下一句。
  void advance() {
    final s = sentence;
    if (s == null) return;
    if (_phase == SpeedReadPhase.read) {
      final ms = elapsedMs < 1 ? 1 : elapsedMs;
      _readMs = ms;
      _slow = ms > target;
      _drill = pickDrill(s, pool: _pool());
      _picked = '';
      _drillOk = null;
      // 超时自动进拷打：不再等用户点「拷打」。不想被拷打就按「下一句」跳过。
      _phase = _slow && _autoDrill && _drill != null
          ? SpeedReadPhase.drill
          : SpeedReadPhase.reveal;
      _startedAt = null;
      if (!_disposed) notifyListeners();
      return;
    }
    if (_phase == SpeedReadPhase.reveal) {
      _finish(null);
      return;
    }
    if (_phase == SpeedReadPhase.drill) {
      _finish(null);
      return;
    }
    if (_phase == SpeedReadPhase.drillAnswer) _finish(_drillOk);
  }

  /// 前后翻句：只移动游标、不记成绩。
  void go(int dir) {
    if (dir == 0) return;
    final n = sentences.length;
    if (n == 0) return;
    final next = (_index + dir).clamp(0, n - 1);
    if (next == _index) return;
    _index = next;
    _resetSentence();
    unawaitedSave();
    if (!_disposed) notifyListeners();
  }

  /// 拷打时选一个选项。
  void chooseDrill(String option) {
    if (_phase != SpeedReadPhase.drill) return;
    final d = _drill;
    if (d == null) return;
    _picked = option;
    _drillOk = checkDrill(d, option);
    _phase = SpeedReadPhase.drillAnswer;
    if (!_disposed) notifyListeners();
  }

  /// 从第一句重来。
  void restart() {
    _rows = const <SpeedRow>[];
    _index = 0;
    _resetSentence();
    unawaitedSave();
    if (!_disposed) notifyListeners();
  }

  /// 调语速，存本机。
  Future<void> setWpm(int wpm) async {
    final next = clampWpm(wpm);
    if (next == _wpm) return;
    _wpm = next;
    if (!_disposed) notifyListeners();
    await _store.saveSpeedWpm(next);
  }

  /// 调「超时自动拷打」，存本机。
  Future<void> setAutoDrill(bool on) async {
    if (on == _autoDrill) return;
    _autoDrill = on;
    if (!_disposed) notifyListeners();
    await _store.saveSpeedAutoDrill(on);
  }

  /// 记这一句的成绩并翻下一句。
  void _finish(bool? ok) {
    final s = sentence;
    if (s == null) return;
    final words = wordCount(s.text);
    _rows = <SpeedRow>[
      ..._rows,
      SpeedRow(words: words, ms: _readMs, slow: _slow, drillOk: ok),
    ];
    _index = _index + 1;
    _resetSentence();
    unawaitedSave();
    if (!_disposed) notifyListeners();
  }

  /// 回一句的初始态（翻句 / 重来 / 下一句都走这里）。
  void _resetSentence() {
    _phase = SpeedReadPhase.read;
    _readMs = 0;
    _slow = false;
    _drill = null;
    _picked = '';
    _drillOk = null;
    _startedAt = _now();
  }

  /// 干扰项池：整篇实词，去重。
  List<String> _pool() {
    final out = <String>{};
    for (final s in sentences) {
      out.addAll(contentWords(s.text));
    }
    return out.toList();
  }

  /// 把游标写回本机：读完最后一句就归零，下次从第一句开始。
  void unawaitedSave() {
    if (_articleKey.isEmpty) return;
    final next = _index >= sentences.length ? 0 : _index;
    _store.saveSpeedCursor(_articleKey, next);
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
