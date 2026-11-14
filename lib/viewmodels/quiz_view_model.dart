/// 整卷考试的会话状态机：设置 → 组卷 → 作答 → 交卷 → 报告。
///
/// 规则在 `core/quiz.dart` / `core/quiz_pool.dart` / `core/article_quiz.dart`；
/// 组卷与落盘在 `quiz_prep.dart`；这里只翻题、判对错、守「一轮只记一次成绩」。
///
/// 与「快速拷打」的区别：拷打按七档固定题型出卷、不记整卷成绩；考试是
/// **自选题型 × 范围 × 题量** 的一整卷，交卷写 `practice_records`。
library;

import 'dart:async';

import 'package:flutter/foundation.dart';

import '../core/ports.dart' show SpeechPort;
import '../core/quiz.dart' show QuizKind, QuizQuestion, articleKinds, isCorrect, vocabKinds;
import '../core/quiz_pool.dart'
    show
        QuizMode,
        QuizScope,
        defaultQuizArticleKinds,
        defaultQuizLimit,
        defaultQuizVocabKinds,
        normalizeQuizLimit;
import '../data/repositories/article_repository.dart' show ArticleRepository, ArticleRow;
import '../data/repositories/learning_repository.dart';
import '../data/repositories/vocab_repository.dart';
import 'current_article_view_model.dart';
import 'drill_view_model.dart' show DrillResult;
import 'quiz_prep.dart';

/// 一份整卷考试的 ViewModel。
class QuizViewModel extends ChangeNotifier {
  QuizViewModel({
    required VocabRepository vocab,
    required LearningRepository learning,
    required ArticleRepository articles,
    CurrentArticleViewModel? currentArticle,
    this.speech,
    DateTime Function()? now,
  })  : _current = currentArticle,
        _now = now ?? DateTime.now {
    _prep = QuizPrep(
      vocab: vocab,
      learning: learning,
      articles: articles,
      articleIdOf: () => currentArticle?.articleId ?? '',
      onError: (msg) {
        _error = msg;
        _safeNotify();
      },
      now: _now,
    );
  }

  late final QuizPrep _prep;

  /// 朗读器（听音 / 听音拼词用）；不传就不显示播放按钮。
  final SpeechPort? speech;
  final CurrentArticleViewModel? _current;
  final DateTime Function() _now;

  QuizMode _mode = QuizMode.vocab;
  QuizScope _scope = QuizScope.article;
  Set<QuizKind> _kinds = defaultQuizVocabKinds.toSet();
  int _limit = defaultQuizLimit;
  String? _articleId;
  List<ArticleRow> _articles = const <ArticleRow>[];

  List<QuizQuestion> _queue = const <QuizQuestion>[];
  int _index = 0;
  String _input = '';
  DrillResult? _result;
  final List<DrillResult> _results = <DrillResult>[];
  final Stopwatch _watch = Stopwatch();

  bool _busy = false;
  bool _recorded = false;
  String? _error;

  // ---- getters ----

  QuizMode get mode => _mode;
  QuizScope get scope => _scope;
  Set<QuizKind> get kinds => Set<QuizKind>.unmodifiable(_kinds);
  int get limit => _limit;
  String? get articleId => _articleId;
  List<ArticleRow> get articles => List<ArticleRow>.unmodifiable(_articles);

  /// 当前模式能选的题型（词级 13 / 文章级 6）。
  List<QuizKind> get availableKinds =>
      _mode == QuizMode.vocab ? vocabKinds : articleKinds;

  /// 词级卷要「本篇」或文章卷必须有篇。
  bool get needsArticle => _mode == QuizMode.article || _scope == QuizScope.article;

  bool get hasQueue => _queue.isNotEmpty;
  int get index => _index;
  int get total => _queue.length;
  QuizQuestion? get question => _index < _queue.length ? _queue[_index] : null;
  DrillResult? get result => _result;
  List<DrillResult> get results => List<DrillResult>.unmodifiable(_results);
  int get correctCount => _results.where((r) => r.correct).length;

  /// 全部答完、停在结果页。
  bool get finished =>
      _queue.isNotEmpty && _index >= _queue.length && _result == null;

  List<QuizQuestion> get wrongQuestions =>
      [for (final r in _results) if (!r.correct) r.question];

  bool get busy => _busy;
  String? get error => _error;
  bool get recorded => _recorded;
  int get elapsedSeconds => _watch.elapsed.inSeconds;

  // ---- 生命周期 ----

  Future<void> bootstrap() async {
    _busy = true;
    _safeNotify();
    try {
      await _prep.bootstrap();
      _articles = _prep.articleRows;
      final global = _current?.articleId;
      if (global != null && _articles.any((a) => a.id == global)) {
        _articleId = global;
      }
      // 没选文章时「本篇」没有意义：词级卷退回全库（文章卷仍要求选篇）。
      if (_mode == QuizMode.vocab && _articleId == null) {
        _scope = QuizScope.all;
      }
      _error = null;
    } on Object catch (e) {
      _error = '读不出来：$e';
    } finally {
      _busy = false;
      _safeNotify();
    }
  }

  void setMode(QuizMode value) {
    if (_mode == value) return;
    _mode = value;
    _kinds = (value == QuizMode.vocab
            ? defaultQuizVocabKinds
            : defaultQuizArticleKinds)
        .toSet();
    if (value == QuizMode.article) {
      _scope = QuizScope.article;
    } else if (_articleId == null) {
      _scope = QuizScope.all;
    }
    _clearRound();
    _safeNotify();
  }

  void setScope(QuizScope value) {
    if (_scope == value) return;
    _scope = value;
    _safeNotify();
  }

  /// 勾 / 取消一个题型；至少留一个（全空出不了卷）。
  void toggleKind(QuizKind kind) {
    if (!availableKinds.contains(kind)) return;
    final next = <QuizKind>{..._kinds};
    if (next.contains(kind)) {
      if (next.length <= 1) return;
      next.remove(kind);
    } else {
      next.add(kind);
    }
    _kinds = next;
    _safeNotify();
  }

  void setLimit(int value) {
    final next = normalizeQuizLimit(value);
    if (_limit == next) return;
    _limit = next;
    _safeNotify();
  }

  void setArticleId(String? id) {
    final next = (id ?? '').trim();
    final value = next.isEmpty ? null : next;
    if (_articleId == value) return;
    _articleId = value;
    if (_mode == QuizMode.vocab) {
      _scope = value == null ? QuizScope.all : QuizScope.article;
    }
    _safeNotify();
  }

  void setInput(String value) {
    if (_input == value) return;
    _input = value;
    _safeNotify();
  }

  // ---- 组卷 / 作答 ----

  /// 组卷并开考；返回题数（0 = 没出成，原因写进 [error]）。
  Future<int> start() async {
    if (_busy) return 0;
    _clearRound();
    _busy = true;
    _error = null;
    _safeNotify();
    try {
      final queue = await _prep.build(
        mode: _mode,
        kinds: _kinds,
        scope: _scope,
        limit: _limit,
        articleId: _articleId,
      );
      if (queue.isEmpty) {
        _error = _mode == QuizMode.article
            ? '这篇还没有足够的译文 / 语言点，出不了文章题：先去精读页补一补，或换一篇。'
            : '当前范围没有能出的题：先补释义 / 例句，或者换个范围。';
        return 0;
      }
      _queue = queue;
      _index = 0;
      _recorded = false;
      _watch
        ..reset()
        ..start();
      return queue.length;
    } on Object catch (e) {
      _error = '出卷失败：$e';
      return 0;
    } finally {
      _busy = false;
      _safeNotify();
    }
  }

  Future<void> speakQuestion() async {
    final q = question;
    if (q == null) return;
    final audio = (q.audioText ?? '').trim();
    final text = audio.isNotEmpty ? audio : q.word.trim();
    if (text.isEmpty) return;
    try {
      await speech?.speak(text);
    } catch (_) {
      // 模拟器 / 没装 TTS 引擎：忽略，不挡答题。
    }
  }

  /// 交一题（选项题传选项文本，输入题传输入框内容）。
  Future<void> submit([String? answer]) async {
    final q = question;
    if (q == null || _result != null) return;
    final text = (answer ?? _input).trim();
    if (text.isEmpty) {
      _error = '先写点什么';
      _safeNotify();
      return;
    }
    final correct = isCorrect(q, text);
    _error = null;
    _result = DrillResult(
      question: q,
      input: text,
      correct: correct,
      answer: q.answer,
    );
    _results.add(_result!);
    _safeNotify();
    await _prep.record(q, correct, articleId: _examArticleId);
  }

  /// 下一题；最后一题后收卷并记一次成绩。
  Future<void> next() async {
    if (_result == null) return;
    _result = null;
    _input = '';
    if (_index + 1 < _queue.length) {
      _index += 1;
      _safeNotify();
      return;
    }
    _index = _queue.length;
    _safeNotify();
    if (_recorded) return;
    _recorded = true;
    if (_watch.isRunning) _watch.stop();
    await _prep.complete(
      results: [for (final r in _results) (question: r.question, correct: r.correct)],
      seconds: _watch.elapsed.inSeconds,
      articleId: _examArticleId,
    );
    _safeNotify();
  }

  /// 错题重练：只排错题；**不重置** `_recorded`（同一轮不记第二次成绩）。
  int retryWrong() {
    final wrong = wrongQuestions;
    if (wrong.isEmpty) return 0;
    _queue = wrong;
    _index = 0;
    _input = '';
    _result = null;
    _results.clear();
    _error = null;
    _safeNotify();
    return wrong.length;
  }

  /// 再考一轮：清空并重新按当前设置组卷。
  Future<int> restart() async {
    _clearRound();
    return start();
  }

  /// 回设置页。
  void reset() {
    _clearRound();
    _safeNotify();
  }

  Future<void> flushWrites() => _prep.flushWrites();

  // ---- 内部 ----

  String? get _examArticleId {
    if (_mode != QuizMode.article && _scope != QuizScope.article) {
      return null;
    }
    final id = ((_articleId ?? _current?.articleId) ?? '').trim();
    return id.isEmpty ? null : id;
  }

  void _clearRound() {
    _queue = const <QuizQuestion>[];
    _index = 0;
    _input = '';
    _result = null;
    _results.clear();
    _error = null;
    _recorded = false;
    _watch
      ..stop()
      ..reset();
  }

  void _safeNotify() {
    if (_isDisposed) return;
    notifyListeners();
  }

  bool _isDisposed = false;

  @override
  void dispose() {
    _isDisposed = true;
    unawaited(flushWrites());
    super.dispose();
  }
}
