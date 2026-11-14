/// 拷打的「准备与落盘」：读词库 / 学习记录、出卷、判分后写回。
///
/// 为什么从 [DrillViewModel] 里拆出来（同 `production_session.dart` 的思路）：
///   - 选档、翻题、结算、预习页是「会话编排」，而这里是「数据准备与持久化」，
///     两组状态的写入方完全不同（翻题不该碰词库，写词库也不该清作答）；
///   - 拆开后两边都远低于上帝类门禁阈值（原先 DrillViewModel 48 个方法）。
///
/// 本类不认识 `ChangeNotifier`：错误通过 [onError] 回调交回 ViewModel 记下，
/// 其余改动都是静默的（判分结果由 ViewModel 自己先 notify 过）。
library;

import 'dart:async';

import '../core/answer_events.dart';
import '../core/article_quiz.dart';
import '../core/learning.dart';
import '../core/mistakes.dart';
import '../core/practice.dart';
import '../core/quiz.dart';
import '../core/quiz_drill.dart';
import '../core/quiz_pool.dart';
import '../core/vocab/replay.dart';
import '../core/vocab/review.dart';
import '../data/repositories/article_repository.dart';
import '../data/repositories/learning_repository.dart';
import '../data/repositories/vocab_repository.dart';
import '../models/document.dart';
import '../models/vocab.dart';

/// 把一条写盘错误交回 ViewModel（由它记 [error] 并 notify）。
typedef DrillErrorSink = void Function(String message);

/// 一份拷打会话的数据层：词库、学习记录、出卷、判分落盘。
class DrillPrep {
  DrillPrep({
    required VocabRepository vocab,
    required LearningRepository learning,
    required this.articles,
    required this.articleIdOf,
    required this.onError,
  })  : _vocabRepo = vocab,
        _learningRepo = learning;

  final VocabRepository _vocabRepo;
  final LearningRepository _learningRepo;

  /// 读正文用（「本篇」要正文词形）；不传就只认「收进本篇」那一路。
  final ArticleRepository? articles;

  /// 现取全局当前篇 id（空串表示没绑）。
  final String Function() articleIdOf;

  final DrillErrorSink onError;

  VocabLibrary library = const VocabLibrary();
  LearningData learningData = emptyLearning();
  String? libraryUpdatedAt;

  // 写盘合并：同一时刻只有一个 save 在跑，后来者覆盖 pending。
  bool _writing = false;
  VocabLibrary? _pendingLibrary;
  Completer<void>? _idle;

  /// 初始化：读词库 + 学习记录（异常交给 ViewModel 显示）。
  Future<void> bootstrap() async {
    library = await _vocabRepo.load() ?? const VocabLibrary();
    libraryUpdatedAt = (await _vocabRepo.meta())?.at;
    learningData = await _learningRepo.load();
  }

  /// 等写盘彻底排空（切后台 / 退出前调）。
  Future<void> flushWrites() async {
    while (_idle != null) {
      await _idle!.future;
    }
  }

  /// 出一份题（已按 [limit] 截断）。
  ///
  /// 词级六档走 `quiz.dart` 的 `buildQuizSet`；「语法·结构」是文章级题型，
  /// `makeQuestion` 第一行就 `if (kind.isArticle) return null`，得换成
  /// `article_quiz.dart` 的 `buildArticleQuestions` 读当前篇的句子来出。
  Future<List<QuizQuestion>> buildQuestions(
      QuizDrillKind kind, int limit, DateTime now) async {
    final kinds = quizDrillKinds[kind] ?? const <QuizKind>[];
    if (kind == QuizDrillKind.grammar) {
      var sentences = const <Sentence>[];
      final id = articleIdOf();
      if (id.isNotEmpty) {
        try {
          final article = await articles?.load(id);
          if (article != null) sentences = article.sentences;
        } catch (_) {
          // 读不到正文就不出题，交给调用方的空池子提示。
        }
      }
      return limitQuizSet(buildArticleQuestions(sentences, kinds: kinds), limit);
    }
    final studyable = quizStudyableItems(library.items);
    final ctx = await poolContext();
    // 错题包围战：先只考错题本里有的词。
    final base = kind == QuizDrillKind.siege ? siegePool(studyable) : studyable;
    // 没绑文章（或那篇读不到正文）时退回全库：首页点进来就能直接考，
    // 不用先去精读页挑一篇。绑了文章才收窄到本篇。
    final scope = kind == QuizDrillKind.siege || ctx.articleIdentity.isEmpty
        ? QuizScope.all
        : QuizScope.article;
    final pool = quizPool(base, scope, ctx, now: now);
    return limitQuizSet(buildQuizSet(pool, kinds), limit);
  }

  /// 「本篇」认哪些词：收进本篇的（`source.articleId` 对得上）+ 正文里出现过的。
  ///
  /// 正文词形要真读一次文章；读不到就只靠「收进本篇」那一路，不报错。
  ///
  /// [articleId] 给「页内临时选一篇」用；不传就认全局当前篇。
  Future<QuizPoolContext> poolContext({String? articleId}) async {
    final id = articleId ?? articleIdOf();
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
  List<VocabItem> siegePool(List<VocabItem> studyable) {
    final ids = <String>{
      for (final m in learningData.mistakes)
        if (m.kind == MistakeKind.vocab && (m.itemId ?? '').isNotEmpty) m.itemId!,
    };
    if (ids.isEmpty) return const <VocabItem>[];
    return [for (final it in studyable) if (ids.contains(it.id)) it];
  }

  /// 判分落盘：SRS 推进 + 错题本 + 答题事件。
  ///
  /// 文章级题（`source == 'article'` 或文章级 kind）**不写 SRS、不进错题本**：
  /// 它的 `itemId` 是句子 / 段落 id，不是词条 id，写进去只会得到
  /// `vocab:s001` 这种脏错题。活动分类也按 Web 口径走（文章题算「读」）。
  ///
  /// [articleId] 给「页内临时选一篇考文章测验」用：不传就用全局当前篇。
  Future<void> record(
    QuizQuestion q,
    bool correct,
    DateTime at, {
    String? articleId,
  }) async {
    final isArticle = isArticleQuestion(q);
    final item = itemOf(q.itemId);
    if (item != null && !isArticle) {
      final graded = reviewItem(
          library, item.id, correct ? ReviewGrade.good : ReviewGrade.again, at);
      queueSave(graded);
    }
    try {
      final data = learningData;
      if (!correct && !isArticle) {
        data.mistakes = upsertMistake(
          data.mistakes,
          vocabMistake(q.itemId, '${q.word} · ${q.kind.name}',
              at.toUtc().toIso8601String()),
        );
      }
      final event = createAnswerEvent(
        AnswerEvent(
          at: at.toUtc().toIso8601String(),
          day: '',
          articleId: articleId ?? articleIdOf(),
          source: PracticeKind.quiz,
          kind: q.kind.name,
          cat: quizActivityCat(q.kind),
          correct: correct,
          questionId: q.id,
        ),
        now: at,
      );
      data.answerEvents = addAnswerEvent(data.answerEvents, event);
      learningData = data;
      await _learningRepo.writeSection(data, LearningSection.mistakes);
      await _learningRepo.writeSection(data, LearningSection.answerEvents);
    } catch (e) {
      onError('答题记录没写进去：$e');
    }
  }

  VocabItem? itemOf(String id) {
    for (final it in library.items) {
      if (it.id == id) return it;
    }
    return null;
  }

  /// 换一份词库并排一次写盘。
  void queueSave(VocabLibrary after) {
    library = after;
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
          await write(target);
        }
      } finally {
        _writing = false;
        _idle = null;
        idle.complete();
      }
    }());
  }

  Future<void> write(VocabLibrary after) async {
    try {
      final saved =
          await _vocabRepo.save(after, baseUpdatedAt: libraryUpdatedAt);
      libraryUpdatedAt = saved.updatedAt;
    } on VocabConflict {
      try {
        final fresh = await _vocabRepo.load() ?? const VocabLibrary();
        final merged = replayPatched(fresh, after, touchedIds(fresh, after));
        final saved = await _vocabRepo.save(
            merged, baseUpdatedAt: (await _vocabRepo.meta())?.at);
        library = merged;
        libraryUpdatedAt = saved.updatedAt;
      } catch (e) {
        onError('词库写不进去：$e');
      }
    } catch (e) {
      onError('词库写不进去：$e');
    }
  }
}
