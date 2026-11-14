/// 快速拷打（首页「拷打」入口）的会话状态机。
///
/// 三层分工：
///   - **规则**在 `core/quiz_pool.dart`（考哪些词、怎么出卷）与
///     `core/quiz_drill.dart`（哪几档、每档什么题型、每档多少题）；
///   - **本文件**只编排：选档 → 出卷 → 判分 → 下一题 → 结算 → 错题重做；
///     读词库 / 出卷 / 判分落盘交给 `drill_prep.dart` 的 [DrillPrep]；
///   - **界面**只读 getter、只调方法。
///
/// 判分口径照 Web 版考试：答对 = SRS `good`，答错 = SRS `again`（记 lapse），
/// 同时进错题本、写一条答题事件。答题事件用于热力图与题型正确率。
///
/// **落盘不挡界面**：判分立刻出结果并翻到下一题，写词库在背后合并进行
/// （背单词那边踩过「点下一个卡一秒」，这里是同一个坑）。
library;

import 'dart:async';

import 'package:flutter/foundation.dart';

import '../core/ports.dart' show SpeechPort;
import '../core/quiz.dart';
import '../core/quiz_drill.dart';
import '../core/quiz_pool.dart' show quizStudyableItems;
import '../core/quiz_warmup.dart' as warm;
import '../data/prefs_store.dart';
import '../data/repositories/article_repository.dart' show ArticleRepository;
import '../data/repositories/learning_repository.dart';
import '../data/repositories/vocab_repository.dart';
import '../viewmodels/current_article_view_model.dart';
import 'drill_prep.dart';

/// 一题的判分结果。
class DrillResult {
  const DrillResult({
    required this.question,
    required this.input,
    required this.correct,
    this.answer = '',
  });

  final QuizQuestion question;
  final String input;
  final bool correct;

  /// 答错时显示的标准答案。
  final String answer;
}

/// 快速拷打的 ViewModel。
class DrillViewModel extends ChangeNotifier {
  DrillViewModel({
    required VocabRepository vocab,
    required LearningRepository learning,
    ArticleRepository? articles,
    CurrentArticleViewModel? currentArticle,
    this.speech,
    PrefsStore? prefsStore,
    DateTime Function()? now,
  })  : _store = prefsStore ?? PrefsStore.memory(),
        _now = now ?? DateTime.now {
    _limits = parseDrillLimits(_store.readDrillLimits());
    _prep = DrillPrep(
      vocab: vocab,
      learning: learning,
      articles: articles,
      articleIdOf: () => currentArticle?.articleId ?? '',
      onError: (msg) {
        _error = msg;
        notifyListeners();
      },
    );
  }

  late final DrillPrep _prep;

  /// 朗读器（听音填空用）；不传就没有播放按钮，其余档不受影响。
  final SpeechPort? speech;

  final PrefsStore _store;
  final DateTime Function() _now;

  // 用 var 声明：check_god_class 的字段正则认不了带逗号 / 点的泛型，
  // 会被误算成方法（曾把 39 个方法报成 48）。
  var _limits = <QuizDrillKind, int>{};
  var _warmupCards = const <warm.DrillWarmupCard>[];

  QuizDrillKind _kind = QuizDrillKind.memory;
  List<QuizQuestion> _queue = const <QuizQuestion>[];
  int _index = 0;
  String _input = '';
  DrillResult? _result;
  final List<DrillResult> _results = <DrillResult>[];
  final Set<String> _wrongIds = <String>{};

  bool _busy = false;
  String? _error;

  // 「先看一遍」预习态：记忆 / 词块是闭卷回忆，开考前先把这轮要考的词
  // 连同释义 / 词块摊开（照 Web `DrillWarmup.tsx`）。题目先出好但不进
  // [_queue]，等用户点「看完了」才真正开跑。
  bool _warmup = false;
  List<QuizQuestion> _warmupQuestions = const <QuizQuestion>[];

  /// 各档题量上限（档位 → 题数）。
  int get limit => _limits[_kind] ?? defaultDrillLimit;

  /// 当前选的档位。
  QuizDrillKind get kind => _kind;

  /// 每档的题量。
  Map<QuizDrillKind, int> get limits => Map<QuizDrillKind, int>.unmodifiable(_limits);

  /// 这一轮有没有题。
  bool get hasQueue => _queue.isNotEmpty;

  /// 当前第几题（0 起）。
  int get index => _index;

  /// 这一轮共几题。
  int get total => _queue.length;

  /// 当前题；越界返回 null。
  QuizQuestion? get question => _index < _queue.length ? _queue[_index] : null;

  /// 已作答的输入。
  String get input => _input;

  /// 当前题的判分（还没交卷时为 null）。
  DrillResult? get result => _result;

  /// 这一轮已答的题。
  List<DrillResult> get results => List<DrillResult>.unmodifiable(_results);

  /// 答对了多少。
  int get correctCount => _results.where((r) => r.correct).length;

  /// 这一轮结束了吗（全部答完）。
  bool get finished => _queue.isNotEmpty && _index >= _queue.length && _result == null;

  /// 还有没有下一题。
  bool get hasNext => _index + 1 < _queue.length;

  /// 这一轮做错的题（重做用）。
  List<QuizQuestion> get wrongQuestions =>
      [for (final r in _results) if (!r.correct) r.question];

  bool get busy => _busy;
  String? get error => _error;

  /// 候选池里这一档能出多少题（设置面板显示用）。
  int get poolSize => countQuestions(
      quizStudyableItems(_prep.library.items), quizDrillKinds[_kind] ?? const []);

  /// 是不是停在「先看一遍」预习页。
  bool get warmup => _warmup;

  /// 预习卡（按题目去重后的词条）。
  List<warm.DrillWarmupCard> get warmupCards =>
      List<warm.DrillWarmupCard>.unmodifiable(_warmupCards);

  /// 这一轮预习要考几个词（预习页标题用）。
  int get warmupCount => _warmupCards.length;

  /// 初始化：读词库 + 学习记录。
  Future<void> bootstrap() async {
    _busy = true;
    notifyListeners();
    try {
      await _prep.bootstrap();
      _error = null;
    } catch (e) {
      _error = '读不出来：$e';
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  /// 换档。
  void setKind(QuizDrillKind kind) {
    if (_kind == kind) return;
    _kind = kind;
    notifyListeners();
  }

  /// 换这一档的题量。
  Future<void> setLimit(int value) async {
    final next = normalizeDrillLimit(value);
    if (_limits[_kind] == next) return;
    _limits = {..._limits, _kind: next};
    notifyListeners();
    await _store.saveDrillLimits(drillLimitsToJson(_limits));
  }

  /// 清掉一轮的状态（结果 / 输入 / 错题 / 预习页），准备重新出卷。
  void _resetRound() {
    _error = null;
    _results.clear();
    _wrongIds.clear();
    _input = '';
    _result = null;
    _index = 0;
    _warmup = false;
    _warmupQuestions = const <QuizQuestion>[];
    _warmupCards = const <warm.DrillWarmupCard>[];
  }

  /// 把一份题真正放进队列；空池子按档位写原因。
  int _beginQueue(List<QuizQuestion> questions) {
    _queue = questions;
    if (_queue.isEmpty) {
      _error = quizDrillEmptyHint(_kind);
      notifyListeners();
      return 0;
    }
    notifyListeners();
    return _queue.length;
  }

  /// 界面「开始」按钮走这里：
  ///   - 记忆 / 词块是闭卷回忆 → 先出卷但停在「先看一遍」页，等 [beginWarmup]；
  ///   - 其余档 → 直接开跑。
  ///
  /// 返回 >0 表示可以继续（预习卡数或题数），0 = 池子空、原因写进 [error]。
  Future<int> launch() async {
    _resetRound();
    final questions = await _prep.buildQuestions(_kind, limit, _now());
    if (questions.isEmpty) {
      _error = quizDrillEmptyHint(_kind);
      notifyListeners();
      return 0;
    }
    if (quizDrillNeedsWarmup(_kind)) {
      _warmupCards =
          warm.buildWarmupCards(_prep.library.items, questions, _kind);
      if (_warmupCards.isEmpty) return _beginQueue(questions);
      _warmupQuestions = questions;
      _warmup = true;
      notifyListeners();
      return _warmupCards.length;
    }
    return _beginQueue(questions);
  }

  /// 预习页「看完了，开始拷打」：把刚才出的卷真正开跑。
  int beginWarmup() {
    if (!_warmup) return 0;
    final questions = _warmupQuestions;
    _resetRound();
    return _beginQueue(questions);
  }

  /// 预习页「取消」：回设置页，这轮不出题。
  void cancelWarmup() {
    if (!_warmup) return;
    _resetRound();
    _queue = const <QuizQuestion>[];
    notifyListeners();
  }

  /// 预习页换题量：存偏好 + 重新抽一份卷（照 Web `setWarmupLimit`）。
  Future<int> setWarmupLimit(int value) async {
    await setLimit(value);
    return launch();
  }

  /// 开一轮（真正把题目放进队列）。
  ///
  /// 返回这一轮出了几题 —— 0 就是池子空了，原因写进 [error]。
  /// 界面不该直接调它：记忆 / 词块要先过 [launch] 的预习页；这里保留原语义
  /// 是因为状态机测试与「再打一轮」都按「调了就直接开跑」写。
  Future<int> start({QuizDrillKind? kind, int? limit}) async {
    if (kind != null) _kind = kind;
    _resetRound();
    final questions =
        await _prep.buildQuestions(_kind, limit ?? this.limit, _now());
    return _beginQueue(questions);
  }

  /// 朗读当前题的句子（听音填空题干是空的，只给声音）。
  /// 没注入 [speech] 或引擎抛错都静默跳过，不挡答题。
  Future<void> speakQuestion() async {
    final q = question;
    if (q == null) return;
    final audio = (q.audioText ?? '').trim();
    final text = audio.isNotEmpty ? audio : q.word.trim();
    if (text.isEmpty) return;
    try {
      await speech?.speak(text);
    } catch (_) {
      // 模拟器 / 没装 TTS 引擎时 flutter_tts 会抛，忽略即可。
    }
  }

  /// 输入答案（填空题 / 拼写题）。
  void setInput(String value) {
    if (_input == value) return;
    _input = value;
    notifyListeners();
  }

  /// 交一题。选项题传选项文本，填空题传输入框内容。
  ///
  /// 判分立刻可见，写库在背后合并进行。
  Future<void> submit([String? answer]) async {
    final q = question;
    if (q == null || _result != null) return;
    final text = (answer ?? _input).trim();
    if (text.isEmpty) {
      _error = '先写点什么';
      notifyListeners();
      return;
    }
    final correct = isCorrect(q, text);
    _error = null;
    _result = DrillResult(question: q, input: text, correct: correct, answer: q.answer);
    _results.add(_result!);
    if (!correct) _wrongIds.add(q.itemId);
    notifyListeners();
    await _prep.record(q, correct, _now());
  }

  /// 下一题（或收卷）。
  void next() {
    if (_result == null) return;
    _result = null;
    _input = '';
    if (_index + 1 < _queue.length) {
      _index += 1;
    } else {
      _index = _queue.length;
    }
    notifyListeners();
  }

  /// 错题重做：把这一轮错的题再排一遍。
  int retryWrong() {
    final wrong = wrongQuestions;
    if (wrong.isEmpty) return 0;
    _queue = wrong;
    _index = 0;
    _input = '';
    _result = null;
    _results.clear();
    _error = null;
    notifyListeners();
    return wrong.length;
  }

  /// 收工回设置。
  void reset() {
    _resetRound();
    _queue = const <QuizQuestion>[];
    notifyListeners();
  }

  void clearError() {
    if (_error == null) return;
    _error = null;
    notifyListeners();
  }

  /// 等写盘彻底排空（切后台 / 退出前调）。
  Future<void> flushWrites() => _prep.flushWrites();

  @override
  void dispose() {
    unawaited(flushWrites());
    super.dispose();
  }
}
