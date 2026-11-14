/// 整卷考试的会话状态机：设置 → 组卷 → 作答 → 交卷 → 报告。
///
/// 规则在 `core/quiz.dart` / `core/quiz_pool.dart` / `core/article_quiz.dart`；
/// 设置的默认值与存取口径在 `core/quiz_settings.dart`；组卷与落盘在 `quiz_prep.dart`；
/// 这里只翻题、判对错、守「一轮只记一次成绩」。
///
/// 与「快速拷打」的区别：拷打按七档固定题型出卷、不记整卷成绩；考试是
/// **自选题型 × 范围 × 题量** 的一整卷，交卷写 `practice_records`。
library;

import 'dart:async';

import 'package:flutter/foundation.dart';

import '../core/ports.dart' show SpeechPort;
import '../core/quiz.dart'
    show QuizQuestion, isCorrect, strictSpelling;
import '../core/quiz_history.dart';
import '../core/quiz_pool.dart' show QuizMode, QuizScope;
import '../core/quiz_session.dart';
import '../core/quiz_settings.dart';
import '../data/prefs_store.dart';
import '../data/repositories/article_repository.dart' show ArticleRepository, ArticleRow;
import '../data/repositories/learning_repository.dart';
import '../data/repositories/vocab_repository.dart';
import 'current_article_view_model.dart';
import 'drill_view_model.dart' show DrillResult;
import 'quiz_archive.dart';
import 'quiz_prep.dart';
import 'quiz_settings_mixin.dart';

/// 一份整卷考试的 ViewModel。
///
/// 设置的读写与「模式 / 范围 / 题型 / 题量 / 四个开关」的 getter、setter
/// 在 [QuizSettingsMixin] 里；这里只管一场考试的生命周期。
class QuizViewModel extends ChangeNotifier with QuizSettingsMixin {
  QuizViewModel({
    required VocabRepository vocab,
    required LearningRepository learning,
    required ArticleRepository articles,
    CurrentArticleViewModel? currentArticle,
    this.speech,
    PrefsStore? prefsStore,
    DateTime Function()? now,
  })  : _current = currentArticle,
        _store = prefsStore ?? PrefsStore.memory(),
        _now = now ?? DateTime.now {
    _archive = QuizArchive(_store);
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
    final saved = _store.loadQuizState();
    adoptSettings(saved.settings);
    _archive.adopt(history: saved.history, session: saved.session);
  }

  late final QuizPrep _prep;
  late final QuizArchive _archive;
  final PrefsStore _store;

  /// 朗读器（听音 / 听音拼词用）；不传就不显示播放按钮。
  final SpeechPort? speech;
  final CurrentArticleViewModel? _current;
  final DateTime Function() _now;

  /// 历史轮次 + 上一场没考完的卷（放 [QuizArchive] 里，见那个文件的说明）。
  QuizArchive get archive => _archive;

  String? _articleId;
  List<ArticleRow> _articles = const <ArticleRow>[];

  List<QuizQuestion> _queue = const <QuizQuestion>[];
  var _index = 0;
  String _input = '';
  DrillResult? _result;
  final List<DrillResult> _results = <DrillResult>[];
  final Stopwatch _watch = Stopwatch();

  /// 自动切题的待触发定时器（答完题隔一会儿自己翻页）。
  Timer? _advanceTimer;

  /// 反复鞭打已经跑到第几轮（1 = 第一轮）。
  var _drillRound = 1;

  /// 恢复上一场时已经过去的秒数（Stopwatch 不能直接设初值）。
  var _elapsedBase = 0;

  var _busy = false;
  var _recorded = false;
  String? _error;

  // ---- getters ----

  int get drillRound => _drillRound;
  String? get articleId => _articleId;
  List<ArticleRow> get articles => List<ArticleRow>.unmodifiable(_articles);

  @override
  bool get hasArticleForScope => _articleId != null;

  /// 设置变了：落盘 + 丢掉跟新口径对不上的「上一场」。
  @override
  void onSettingsChanged() =>
      _archive.saveSession(null, settings: settings);

  @override
  void onRoundInvalidated() => _clearRound();

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
  int get elapsedSeconds => _elapsedBase + _watch.elapsed.inSeconds;

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
      if (mode == QuizMode.vocab && _articleId == null) {
        adoptSettings(settings.copyWith(scope: QuizScope.all));
      }
      _error = null;
    } on Object catch (e) {
      _error = '读不出来：$e';
    } finally {
      _busy = false;
      _safeNotify();
    }
  }

  void setArticleId(String? id) {
    final next = (id ?? '').trim();
    final value = next.isEmpty ? null : next;
    if (_articleId == value) return;
    _articleId = value;
    if (mode == QuizMode.vocab) {
      adoptSettings(settings.copyWith(
        scope: value == null ? QuizScope.all : QuizScope.article,
      ));
      _archive.saveSession(null, settings: settings);
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
    _archive.saveSession(null, settings: settings);
    _busy = true;
    _error = null;
    _safeNotify();
    try {
      final queue = await _prep.build(
        mode: mode,
        kinds: kinds,
        scope: scope,
        limit: limit,
        articleId: _articleId,
        unique: unique,
      );
      if (queue.isEmpty) {
        _error = switch (mode) {
          QuizMode.article =>
            '这篇还没有足够的译文 / 语言点，出不了文章题：先去精读页补一补，或换一篇。',
          QuizMode.dictation =>
            '这篇里没有词库中的词，听写出不来：先把词收进本篇，或换一篇。',
          QuizMode.mixed =>
            '词级题和文章题都没出成：先补释义 / 例句，或先去精读页补译文和语言点。',
          QuizMode.vocab => '当前范围没有能出的题：先补释义 / 例句，或者换个范围。',
        };
        return 0;
      }
      _queue = queue;
      _index = 0;
      _recorded = false;
      _drillRound = 1;
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
    await _say(speech, text);
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
    _persistSession();
    await _prep.record(q, correct, articleId: _examArticleId);

    // 答完朗读（语法标记不读：答案是可数 / 不可数这类中文标签）。
    final spoken = quizSpeakText(
      speakAfter: speakAfter,
      kind: q.kind,
      word: q.word,
      answer: q.answer,
    );
    if (spoken != null) await _say(speech, spoken);

    // 自动下一题：答对快切、答错多停；拼写错要先确认（词已排进重学队尾）。
    final delay = quizAutoAdvanceDelay(
      auto: auto,
      correct: correct,
      spellingMiss: !correct && strictSpelling.contains(q.kind),
    );
    if (delay != null) {
      _advanceTimer?.cancel();
      _advanceTimer = Timer(delay, () {
        _advanceTimer = null;
        if (_result != null) unawaited(next());
      });
    }
  }

  /// 下一题；最后一题后收卷并记一次成绩。
  Future<void> next() async {
    _advanceTimer?.cancel();
    _advanceTimer = null;
    if (_result == null) return;
    _result = null;
    _input = '';
    if (_index + 1 < _queue.length) {
      _index += 1;
      _safeNotify();
      _persistSession();
      return;
    }
    _index = _queue.length;
    _safeNotify();
    if (_recorded) return;
    _recorded = true;
    if (_watch.isRunning) _watch.stop();
    final seconds = elapsedSeconds;
    _archive.saveSession(null, settings: settings);
    await _prep.complete(
      results: [for (final r in _results) (question: r.question, correct: r.correct)],
      seconds: seconds,
      articleId: _examArticleId,
    );
    _recordHistory(seconds);
    _safeNotify();
    _maybeLoopWrong();
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

  /// 继续上一场没考完的卷；返回剩下的题数（0 = 没有可恢复的）。
  ///
  /// 恢复的是**出卷那一刻的题**，不按现在的设置重新抽 —— 否则题会变，
  /// 「上次停在第 7 题」就对不上了。
  int resumeSession() {
    final saved = _archive.saved;
    if (saved == null || !saved.resumable) return 0;
    _advanceTimer?.cancel();
    _advanceTimer = null;
    _queue = saved.questions;
    _index = saved.index;
    _input = '';
    _result = null;
    _results
      ..clear()
      ..addAll([
        for (final r in saved.results)
          DrillResult(
            question: r.question,
            input: r.input,
            correct: r.correct,
            answer: r.question.answer,
          ),
      ]);
    _recorded = saved.recorded;
    _drillRound = saved.drillRound;
    _elapsedBase = saved.seconds;
    _error = null;
    _watch
      ..reset()
      ..start();
    _safeNotify();
    return _queue.length - _index;
  }

  /// 丢掉上一场的快照（用户点「不继续了」或改了设置）。
  void discardSaved() {
    if (_archive.saved == null) return;
    _archive.saveSession(null, settings: settings);
    _safeNotify();
  }

  /// 回设置页。
  void reset() {
    _clearRound();
    _safeNotify();
  }

  Future<void> flushWrites() => _prep.flushWrites();

  // ---- 内部 ----

  /// 反复鞭打：交卷后还有错题就自动重练（最多 [maxQuizDrillRounds] 轮）。
  ///
  /// 拷打不走这里（结算页的造句才是那一轮的落点）。
  void _maybeLoopWrong() {
    final wrong = wrongQuestions.length;
    if (!quizShouldLoopWrong(
      loopWrong: loopWrong,
      drill: false,
      wrong: wrong,
      round: _drillRound,
    )) {
      return;
    }
    _drillRound += 1;
    _advanceTimer?.cancel();
    _advanceTimer = Timer(const Duration(milliseconds: 1500), () {
      _advanceTimer = null;
      retryWrong();
    });
  }

  /// 把「当前停在哪」存下来，下次进来能接着考。
  void _persistSession() {
    if (_queue.isEmpty || _index >= _queue.length) return;
    _archive.saveSession(
      QuizSession(
        mode: mode,
        scope: scope,
        questions: _queue,
        index: _index,
        results: [
          for (final r in _results)
            QuizAnswerSnapshot(
              question: r.question,
              input: r.input,
              correct: r.correct,
            ),
        ],
        seconds: elapsedSeconds,
        articleId: _examArticleId,
        drillRound: _drillRound,
        recorded: _recorded,
      ),
      settings: settings,
    );
  }

  /// 交卷时补一条历史（摘要 + 逐题明细）。
  ///
  /// 存 prefs 而不是新开 sqflite 表：`docs/PLAN.md` 明确「不加 v14 迁移」。
  /// 汇总口径另有 `practice_records`，两边互不依赖。
  void _recordHistory(int seconds) {
    final id = _examArticleId;
    _archive.record(
      QuizRoundRow(
        at: _now().toUtc().toIso8601String(),
        mode: mode,
        total: _results.length,
        correct: correctCount,
        seconds: seconds,
        articleId: id,
        articleTitle: id == null
            ? ''
            : (_articles
                    .where((a) => a.id == id)
                    .map((a) => a.title)
                    .firstOrNull ??
                ''),
        entries: [
          for (final r in _results)
            QuizAnswerRow(
              word: r.question.word,
              kind: r.question.kind,
              correct: r.correct,
              answer: r.question.answer,
              input: r.input,
            ),
        ],
      ),
      settings: settings,
    );
  }

  String? get _examArticleId {
    if (mode != QuizMode.article && scope != QuizScope.article) {
      return null;
    }
    final id = ((_articleId ?? _current?.articleId) ?? '').trim();
    return id.isEmpty ? null : id;
  }

  void _clearRound() {
    _advanceTimer?.cancel();
    _advanceTimer = null;
    _queue = const <QuizQuestion>[];
    _index = 0;
    _input = '';
    _result = null;
    _results.clear();
    _error = null;
    _recorded = false;
    _drillRound = 1;
    _elapsedBase = 0;
    _watch
      ..stop()
      ..reset();
  }

  void _safeNotify() {
    if (_isDisposed) return;
    notifyListeners();
  }

  var _isDisposed = false;

  @override
  void dispose() {
    _isDisposed = true;
    _advanceTimer?.cancel();
    _advanceTimer = null;
    unawaited(flushWrites());
    super.dispose();
  }
}

/// 朗读一句；没注入朗读器 / 模拟器没装 TTS 引擎都只吞掉，不挡答题。
Future<void> _say(SpeechPort? speech, String text) async {
  try {
    await speech?.speak(text);
  } catch (_) {
    // 忽略。
  }
}