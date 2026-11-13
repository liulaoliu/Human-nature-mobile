/// 快速拷打（首页「拷打」入口）的会话状态机。
///
/// 三层分工：
///   - **规则**在 `core/quiz_pool.dart`（考哪些词、怎么出卷）与
///     `core/quiz_drill.dart`（哪几档、每档什么题型、每档多少题）；
///   - **本文件**只编排：选档 → 出卷 → 判分 → 下一题 → 结算 → 错题重做；
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

import '../core/activity/activity.dart';
import '../core/answer_events.dart';
import '../core/learning.dart';
import '../core/mistakes.dart';
import '../core/practice.dart';
import '../core/quiz.dart';
import '../core/quiz_drill.dart';
import '../core/quiz_pool.dart';
import '../core/vocab/replay.dart' show replayPatched, touchedIds;
import '../core/vocab/review.dart' show ReviewGrade, reviewItem;
import '../data/prefs_store.dart';
import '../data/repositories/article_repository.dart' show ArticleRepository;
import '../data/repositories/learning_repository.dart';
import '../data/repositories/vocab_repository.dart';
import '../models/vocab.dart';
import '../viewmodels/current_article_view_model.dart';

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
    this.articles,
    this.currentArticle,
    PrefsStore? prefsStore,
    DateTime Function()? now,
  })  : _vocabRepo = vocab,
        _learningRepo = learning,
        _store = prefsStore ?? PrefsStore.memory(),
        _now = now ?? DateTime.now {
    _limits = parseDrillLimits(_store.readDrillLimits());
  }

  final VocabRepository _vocabRepo;
  final LearningRepository _learningRepo;

  /// 读正文用（「本篇」要正文词形）；不传就只认「收进本篇」那一路。
  final ArticleRepository? articles;

  /// 全局当前篇；不传就只考全库。
  final CurrentArticleViewModel? currentArticle;

  final PrefsStore _store;
  final DateTime Function() _now;

  VocabLibrary _library = const VocabLibrary();
  String? _libraryUpdatedAt;
  LearningData _learning = emptyLearning();
  Map<QuizDrillKind, int> _limits = <QuizDrillKind, int>{};

  QuizDrillKind _kind = QuizDrillKind.memory;
  List<QuizQuestion> _queue = const <QuizQuestion>[];
  int _index = 0;
  String _input = '';
  DrillResult? _result;
  final List<DrillResult> _results = <DrillResult>[];
  final Set<String> _wrongIds = <String>{};

  bool _busy = false;
  String? _error;

  // 写盘合并：同一时刻只有一个 save 在跑，后来者覆盖 pending。
  bool _writing = false;
  VocabLibrary? _pendingLibrary;
  Completer<void>? _idle;

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
  int get poolSize => countQuestions(quizStudyableItems(_library.items), quizDrillKinds[_kind] ?? const []);

  /// 初始化：读词库 + 学习记录。
  Future<void> bootstrap() async {
    _busy = true;
    notifyListeners();
    try {
      _library = await _vocabRepo.load() ?? const VocabLibrary();
      _libraryUpdatedAt = (await _vocabRepo.meta())?.at;
      _learning = await _learningRepo.load();
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

  /// 开一轮。
  ///
  /// 返回这一轮出了几题 —— 0 就是池子空了，原因写进 [error]。
  Future<int> start({QuizDrillKind? kind, int? limit}) async {
    if (kind != null) _kind = kind;
    _error = null;
    _results.clear();
    _wrongIds.clear();
    _input = '';
    _result = null;
    _index = 0;

    final kinds = quizDrillKinds[_kind] ?? const <QuizKind>[];
    final studyable = quizStudyableItems(_library.items);
    final ctx = await _poolContext();
    // 错题包围战：先只考错题本里有的词。
    final base = _kind == QuizDrillKind.siege ? _siegePool(studyable) : studyable;
    // 没绑文章（或那篇读不到正文）时退回全库：首页点进来就能直接考，
    // 不用先去精读页挑一篇。绑了文章才收窄到本篇。
    final scope = _kind == QuizDrillKind.siege || ctx.articleIdentity.isEmpty
        ? QuizScope.all
        : QuizScope.article;
    final pool = quizPool(base, scope, ctx, now: _now());
    final set = buildQuizSet(pool, kinds);
    // [limit] 是这一轮的确切题数（0 = 不限）；只有落盘的偏好才走档位归一化。
    _queue = limitQuizSet(set, limit ?? this.limit);

    if (_queue.isEmpty) {
      _error = _kind == QuizDrillKind.siege
          ? '错题本里没有能出的题：先做几轮拷打，错的词会自动收进来。'
          : '这一档没有能出的题：词库缺释义或例句，先去「自动标词」或「一键处理」补一补。';
      notifyListeners();
      return 0;
    }
    notifyListeners();
    return _queue.length;
  }

  /// 「本篇」认哪些词：收进本篇的（`source.articleId` 对得上）+ 正文里出现过的。
  ///
  /// 正文词形要真读一次文章；读不到就只靠「收进本篇」那一路，不报错。
  Future<QuizPoolContext> _poolContext() async {
    final id = currentArticle?.articleId ?? '';
    if (id.isEmpty) return const QuizPoolContext();
    var lemmas = const <String>{};
    try {
      final article = await articles?.load(id);
      if (article != null) {
        lemmas = <String>{
          for (final s in article.sentences)
            ...s.text
                .split(RegExp(r"[^A-Za-z']+"))
                .where((w) => w.length > 2)
                .map((w) => w.toLowerCase()),
        };
      }
    } catch (_) {
      // 读不到正文不算错：还有「收进本篇」那条路。
    }
    return QuizPoolContext(articleIdentity: id, docLemmas: lemmas);
  }

  /// 错题包围战的池子：错题本里点过名的词条（`MistakeKind.vocab`）。
  List<VocabItem> _siegePool(List<VocabItem> studyable) {
    final ids = <String>{
      for (final m in _learning.mistakes)
        if (m.kind == MistakeKind.vocab && (m.itemId ?? '').isNotEmpty) m.itemId!,
    };
    if (ids.isEmpty) return const <VocabItem>[];
    return [for (final it in studyable) if (ids.contains(it.id)) it];
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
    await _record(q, correct);
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
    _queue = const <QuizQuestion>[];
    _index = 0;
    _input = '';
    _result = null;
    _results.clear();
    _error = null;
    notifyListeners();
  }

  void clearError() {
    if (_error == null) return;
    _error = null;
    notifyListeners();
  }

  /// 等写盘彻底排空（切后台 / 退出前调）。
  Future<void> flushWrites() async {
    while (_idle != null) {
      await _idle!.future;
    }
  }

  Future<void> _record(QuizQuestion q, bool correct) async {
    final at = _now();
    final item = _itemOf(q.itemId);
    if (item != null) {
      final graded = reviewItem(_library, item.id, correct ? ReviewGrade.good : ReviewGrade.again, at);
      _queueSave(graded);
    }
    try {
      final data = _learning;
      if (!correct) {
        data.mistakes = upsertMistake(
          data.mistakes,
          vocabMistake(q.itemId, '${q.word} · ${q.kind.name}', at.toUtc().toIso8601String()),
        );
      }
      final event = createAnswerEvent(
        AnswerEvent(
          at: at.toUtc().toIso8601String(),
          day: '',
          articleId: currentArticle?.articleId ?? '',
          source: PracticeKind.quiz,
          kind: q.kind.name,
          cat: ActivityCat.vocab,
          correct: correct,
          questionId: q.id,
        ),
        now: at,
      );
      data.answerEvents = addAnswerEvent(data.answerEvents, event);
      _learning = data;
      await _learningRepo.writeSection(data, LearningSection.mistakes);
      await _learningRepo.writeSection(data, LearningSection.answerEvents);
    } catch (e) {
      _error = '答题记录没写进去：$e';
      notifyListeners();
    }
  }

  VocabItem? _itemOf(String id) {
    for (final it in _library.items) {
      if (it.id == id) return it;
    }
    return null;
  }

  /// 换一份词库并排一次写盘。
  void _queueSave(VocabLibrary after) {
    _library = after;
    _pendingLibrary = after;
    if (_writing) return;
    _writing = true;
    final idle = Completer<void>();
    _idle = idle;
    unawaited(() async {
      try {
        while (_pendingLibrary != null) {
          final target = _pendingLibrary!;
          _pendingLibrary = null;
          await _write(target);
        }
      } finally {
        _writing = false;
        _idle = null;
        idle.complete();
      }
    }());
  }

  Future<void> _write(VocabLibrary after) async {
    try {
      final saved = await _vocabRepo.save(after, baseUpdatedAt: _libraryUpdatedAt);
      _libraryUpdatedAt = saved.updatedAt;
    } on VocabConflict {
      try {
        final fresh = await _vocabRepo.load() ?? const VocabLibrary();
        final merged = replayPatched(fresh, after, touchedIds(fresh, after));
        final saved = await _vocabRepo.save(merged, baseUpdatedAt: (await _vocabRepo.meta())?.at);
        _library = merged;
        _libraryUpdatedAt = saved.updatedAt;
      } catch (e) {
        _error = '词库写不进去：$e';
        notifyListeners();
      }
    } catch (e) {
      _error = '词库写不进去：$e';
      notifyListeners();
    }
  }

  @override
  void dispose() {
    unawaited(flushWrites());
    super.dispose();
  }
}
