/// 整卷考试的「数据准备与落盘」：读词库 / 文章、组卷、判分、交卷记成绩。
///
/// 为什么从 [QuizViewModel] 拆出来：组卷要同时碰词库、文章、学习记录三份数据，
/// 交卷又要写 `practice / kindStats / activity` 三段；会话状态机只该管翻题。
/// 判分那条路直接复用 [DrillPrep.record]（文章题守卫已在那边修好）。
library;

import '../core/activity/activity.dart'
    show ActivityCat, addActivity, dayKeyLocal;
import '../core/article_quiz.dart' show buildArticleQuestions;
import '../core/answer_events.dart' show quizActivityCat;
import '../core/kind_stats.dart' show KindStat;
import '../core/learning.dart' show LearningData, LearningSection;
import '../core/practice.dart' show PracticeKind, PracticeRecord, addPracticeRecord;
import '../core/quiz.dart' show QuizKind, QuizQuestion;
import '../core/quiz_pool.dart'
    show
        QuizMode,
        QuizPoolContext,
        QuizScope,
        buildQuizSet,
        limitQuizSet,
        quizPool,
        quizStudyableItems;
import '../data/repositories/article_repository.dart';
import '../data/repositories/learning_repository.dart';
import '../data/repositories/vocab_repository.dart';
import '../models/vocab.dart' show VocabLibrary;
import 'drill_prep.dart';

/// 一条「这题答得对不对」，交卷汇总用。
typedef QuizTally = ({QuizQuestion question, bool correct});

/// 一份考试的数据层。
class QuizPrep {
  QuizPrep({
    required VocabRepository vocab,
    required LearningRepository learning,
    required ArticleRepository articles,
    required String Function() articleIdOf,
    required DrillErrorSink onError,
    DateTime Function()? now,
  })  : _learning = learning,
        _articles = articles,
        _now = now ?? DateTime.now {
    _drill = DrillPrep(
      vocab: vocab,
      learning: learning,
      articles: articles,
      articleIdOf: articleIdOf,
      onError: onError,
    );
  }

  final LearningRepository _learning;
  final ArticleRepository _articles;
  final DateTime Function() _now;
  late final DrillPrep _drill;

  List<ArticleRow> _articleRows = const <ArticleRow>[];

  /// 当前词库（组卷用）。
  VocabLibrary get library => _drill.library;

  /// 可选的文章（设置页的下拉）。
  List<ArticleRow> get articleRows => _articleRows;

  /// 学习记录（交卷时在它上面累加；判分事件由 [DrillPrep] 写）。
  LearningData get learningData => _drill.learningData;

  Future<void> bootstrap() async {
    await _drill.bootstrap();
    _articleRows = await _articles.list();
  }

  /// 组卷。
  ///
  /// [articleId] 是这次考试选中的篇；词级「本篇」与文章卷都用它，
  /// 不传才回全局当前篇。没选中任何篇时「本篇」退回全库（不静默空卷）。
  Future<List<QuizQuestion>> build({
    required QuizMode mode,
    required Set<QuizKind> kinds,
    required QuizScope scope,
    required int limit,
    String? articleId,
  }) async {
    if (mode == QuizMode.article) {
      final id = (articleId ?? '').trim();
      if (id.isEmpty) return const <QuizQuestion>[];
      final article = await _articles.load(id);
      if (article == null) return const <QuizQuestion>[];
      // 显式传 kinds：buildArticleQuestions 自己的默认值与 Web 默认相反。
      return limitQuizSet(
        buildArticleQuestions(article.sentences, kinds: kinds.toList()),
        limit,
      );
    }

    final studyable = quizStudyableItems(_drill.library.items);
    final useArticle = scope == QuizScope.article &&
        ((articleId ?? '').trim().isNotEmpty);
    final ctx = useArticle
        ? await _drill.poolContext(articleId: articleId)
        : const QuizPoolContext();
    final effective = useArticle ? QuizScope.article : (scope == QuizScope.article ? QuizScope.all : scope);
    final pool = quizPool(studyable, effective, ctx, now: _now());
    return limitQuizSet(buildQuizSet(pool, kinds.toList()), limit);
  }

  /// 判分落盘（SRS / 错题本 / 答题事件）。
  Future<void> record(
    QuizQuestion q,
    bool correct, {
    String? articleId,
  }) =>
      _drill.record(q, correct, _now(), articleId: articleId);

  /// 交卷：记一次练习成绩 + 按题型累计 + 活动热力图。
  ///
  /// 只在「这一轮真正答完」时调一次；重练错题不重复记（由 ViewModel 守卫）。
  Future<void> complete({
    required List<QuizTally> results,
    required int seconds,
    String? articleId,
  }) async {
    if (results.isEmpty) return;
    final at = _now();
    final data = _drill.learningData;
    final correct = results.where((r) => r.correct).length;

    data.practice = addPracticeRecord(
      data.practice,
      PracticeRecord(
        at: at.toUtc().toIso8601String(),
        kind: PracticeKind.quiz,
        total: results.length,
        correct: correct,
        seconds: seconds,
        articleId: articleId,
      ),
    );

    final byArticle = (articleId ?? '').trim();
    if (byArticle.isNotEmpty) {
      // 按题型累计只写有归属的篇（与 Web `useLearningActions.ts` 的守卫一致）。
      final stats = data.kindStats;
      for (final r in results) {
        final byKind = stats.putIfAbsent(byArticle, () => <String, KindStat>{});
        final kind = r.question.kind.name;
        byKind[kind] = (byKind[kind] ?? const KindStat())
            .plus(total: 1, correct: r.correct ? 1 : 0);
      }
      data.kindStats = stats;
    }

    final counts = <ActivityCat, int>{};
    for (final r in results) {
      final cat = quizActivityCat(r.question.kind);
      counts[cat] = (counts[cat] ?? 0) + 1;
    }
    var activity = data.activity;
    final day = dayKeyLocal(at);
    for (final e in counts.entries) {
      activity = addActivity(activity, day, e.key, n: e.value);
    }
    data.activity = activity;

    try {
      await _learning.writeSection(data, LearningSection.practice);
      if (byArticle.isNotEmpty) {
        await _learning.writeSection(data, LearningSection.kindStats);
      }
      await _learning.writeSection(data, LearningSection.activity);
    } on Object catch (e) {
      _drill.onError('考试成绩没写进去：$e');
    }
  }

  Future<void> flushWrites() => _drill.flushWrites();
}
