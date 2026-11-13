/// 精读工作流的状态：读本篇数据 → 算 `IntensivePlan` → 界面照着画。
///
/// 三层分工：
///   - **纯函数**在 `core/intensive.dart`（阶段、进度、等级、下一步）；
///   - **本文件**只做「把数据凑齐」：词库、句子、练习成绩、仿写条数、通读勾选；
///   - **界面** `views/intensive_page.dart` 只画，并按阶段 key 跳到对应工具。
///
/// 为什么要有这一页：以前这些功能各自挂在首页，用户不知道先做哪个；
/// 仿写只是七步里的一步（Web 版也是这么排的），所以它不该在首页单独占一张卡。
library;

import 'package:flutter/foundation.dart';

import '../core/activity/activity.dart'
    show ActivityCat, DayActivity, activityStreak, addActivity, dayKeyLocal;
import '../core/article_vocab.dart' show articleItemsOf;
import '../core/intensive.dart';
import '../core/kind_stats.dart' show KindStats, emptyKindStats;
import '../core/language.dart' show hasSentenceLanguage;
import '../core/learning.dart' show LearningSection, RetellRecord;
import '../core/output_board.dart';
import '../core/practice.dart' show PracticeKind, PracticeRecord, practiceForArticle;
import '../core/writing_record.dart' show WritingRecord;
import '../core/writing_record_json.dart' show writingRecordsFromJson;
import '../data/repositories/article_repository.dart';
import '../data/repositories/learning_repository.dart';
import '../data/repositories/vocab_repository.dart';
import '../models/document.dart';
import '../models/vocab.dart' show VocabLibrary;
import 'current_article_view_model.dart';

class IntensiveViewModel extends ChangeNotifier {
  IntensiveViewModel({
    required VocabRepository vocab,
    required LearningRepository learning,
    required ArticleRepository articles,
    this.currentArticle,
  })  : _vocabRepo = vocab,
        _learningRepo = learning,
        _articlesRepo = articles;

  final VocabRepository _vocabRepo;
  final LearningRepository _learningRepo;
  final ArticleRepository _articlesRepo;

  /// 全局当前文章：只读，本页不回写。
  final CurrentArticleViewModel? currentArticle;

  VocabLibrary? _library;
  SavedArticle? _article;
  List<WritingRecord> _writes = const <WritingRecord>[];
  List<String> _skimmed = const <String>[];
  List<RetellRecord> _retells = const <RetellRecord>[];
  KindStats _kindStats = emptyKindStats();
  List<DayActivity> _activity = const <DayActivity>[];
  bool _busy = false;
  bool _savingSkim = false;
  String? _error;

  SavedArticle? get article => _article;
  String? get articleId => _article?.id;
  String get title => _article?.title ?? '';
  bool get hasArticle => _article != null;
  bool get busy => _busy;
  String? get error => _error;
  bool get skimmed => _article != null && _skimmed.contains(_article!.id);

  /// 本篇的复述记录（新的在前）。
  List<RetellRecord> get retells {
    final a = _article;
    if (a == null) return const <RetellRecord>[];
    return _retells.where((r) => r.articleId == a.id).toList(growable: false);
  }

  /// 本篇的仿写 / 产出记录（新的在前）。
  List<WritingRecord> get writes {
    final a = _article;
    if (a == null) return const <WritingRecord>[];
    return _writes.where((r) => r.articleId == a.id).toList(growable: false);
  }

  /// 产出看板：词块/搭配/习语正确率 + 仿写 + 复述 的量化。
  ///
  /// 与 Web 版 `useArticleDerived.ts` 的 `outputBoard` 同口径：题型统计按
  /// `kindStats[articleId][kind]` 求和，仿写均分只在 `feedback.max > 0` 时计入。
  OutputBoard get outputBoard {
    final a = _article;
    final lib = _library;
    if (a == null || lib == null) return buildOutputBoard(const OutputInput());
    final words = articleItemsOf(lib, a.id);
    final w = intensiveWordsOf(words);
    final mine = _writes.where((r) => r.articleId == a.id).toList(growable: false);
    return buildOutputBoard(
      OutputInput(
        chunkStats: sumKindStats(_kindStats, a.id, outputChunkKinds),
        grammarStats: sumKindStats(_kindStats, a.id, outputGrammarKinds),
        words: OutputWords(
          total: w.total,
          withChunks: w.withChunks,
          studied: w.studied,
          stable: w.stable,
        ),
        writes: OutputWrites(count: mine.length, avgScore: _avgWriteScore(mine)),
        retells: OutputRetells(
          count: retells.length,
          words: retells.fold<int>(0, (s, r) => s + r.words),
        ),
        streak: activityStreak(_activity),
      ),
    );
  }

  /// 仿写均分（0–100）。一条都没批改过时返回 null —— 看板据此显示「待批改」。
  static double? _avgWriteScore(List<WritingRecord> rows) {
    if (rows.isEmpty) return null;
    var sum = 0.0;
    var graded = 0;
    for (final r in rows) {
      final max = r.feedback.max;
      if (max <= 0) continue;
      sum += r.feedback.total / max * 100;
      graded += 1;
    }
    return graded == 0 ? null : sum / graded;
  }

  /// 本页的精读计划（没有文章时给一份空的）。
  IntensivePlan get plan {
    final a = _article;
    final lib = _library;
    if (a == null || lib == null) {
      return buildIntensivePlan(
        const IntensiveInput(
          hasDoc: false,
          skimmed: false,
          words: IntensiveWords(
            total: 0,
            withMeaning: 0,
            withChunks: 0,
            withMarks: 0,
            studied: 0,
            stable: 0,
            due: 0,
            noExample: 0,
          ),
          sentences: IntensiveSentences(total: 0, translated: 0, language: 0),
        ),
      );
    }
    final words = articleItemsOf(lib, a.id);
    final sents = a.sentences;
    // 只算测验类记录：听写 / 听力不进「达标拷打」这一格。
    final rows = practiceForArticle(_practice, a.id).where((r) => r.kind == PracticeKind.quiz).toList();
    final quizTotal = rows.fold<int>(0, (s, r) => s + r.total);
    final quizCorrect = rows.fold<int>(0, (s, r) => s + r.correct);
    return buildIntensivePlan(
      IntensiveInput(
        hasDoc: true,
        skimmed: skimmed,
        words: intensiveWordsOf(words),
        sentences: IntensiveSentences(
          total: sents.length,
          translated: sents.where((s) => (s.translation ?? '').trim().isNotEmpty).length,
          language: sents.where(hasSentenceLanguage).length,
        ),
        quiz: quizTotal > 0 ? SkillStat(total: quizTotal, correct: quizCorrect) : null,
        writes: _writes.where((r) => r.articleId == a.id).length,
      ),
    );
  }

  List<PracticeRecord> _practice = const <PracticeRecord>[];

  Future<void> bootstrap() async {
    _busy = true;
    _error = null;
    notifyListeners();
    try {
      _library = await _vocabRepo.load();
      final data = await _learningRepo.load();
      _skimmed = List<String>.unmodifiable(data.skimmed);
      _practice = data.practice;
      _retells = data.retells;
      _kindStats = data.kindStats;
      _activity = data.activity;
      _writes = writingRecordsFromJson(data.writingHistory);
      final id = currentArticle?.articleId;
      if (id != null) _article = await _articlesRepo.load(id);
    } catch (e) {
      _error = '读数据失败：$e';
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  /// 换一篇（页内临时换，不回写全局）。
  Future<void> openArticle(String? id) async {
    if (id == null) {
      _article = null;
      notifyListeners();
      return;
    }
    try {
      _article = await _articlesRepo.load(id);
      _error = null;
    } catch (e) {
      _error = '读文章失败：$e';
    }
    notifyListeners();
  }

  /// 勾 / 取消「已通读（看懂大意）」。
  Future<void> toggleSkimmed() async {
    final a = _article;
    if (a == null || _savingSkim) return;
    final next = <String>[..._skimmed];
    if (next.contains(a.id)) {
      next.remove(a.id);
    } else {
      next.add(a.id);
    }
    _skimmed = List<String>.unmodifiable(next);
    notifyListeners();
    _savingSkim = true;
    try {
      final data = await _learningRepo.load();
      data.skimmed = next;
      await _learningRepo.writeSection(data, LearningSection.skimmed);
    } catch (e) {
      _error = '通读标记没存进去：$e';
    } finally {
      _savingSkim = false;
      notifyListeners();
    }
  }

  void clearError() {
    if (_error == null) return;
    _error = null;
    notifyListeners();
  }

  /// 记一条复述打卡（空文本 / 没打开文章 → 不记）。
  ///
  /// 与 Web 版 `useLearningActions.saveRetell` 同口径：`words` 按空白切词数，
  /// 新的在前、最多留 200 条，同时给活动统计记一次 `write`。
  Future<bool> saveRetell(String text) async {
    final a = _article;
    final t = text.trim();
    if (a == null || t.isEmpty) return false;
    final now = DateTime.now();
    final at = now.toUtc().toIso8601String();
    final words = t.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).length;
    final rec = RetellRecord(at: at, articleId: a.id, text: t, words: words);
    final next = <RetellRecord>[rec, ..._retells];
    _retells = List<RetellRecord>.unmodifiable(
      next.length > 200 ? next.sublist(0, 200) : next,
    );
    _activity = addActivity(_activity, dayKeyLocal(now), ActivityCat.write);
    notifyListeners();
    try {
      final data = await _learningRepo.load();
      data.retells = _retells.toList();
      data.activity = _activity;
      await _learningRepo.writeSection(data, LearningSection.retells);
      await _learningRepo.writeSection(data, LearningSection.activity);
      return true;
    } catch (e) {
      _error = '复述没存进去：$e';
      notifyListeners();
      return false;
    }
  }

  /// 删掉一条复述（按 `at` 认）。
  Future<void> deleteRetell(String at) async {
    final next = _retells.where((r) => r.at != at).toList(growable: false);
    if (next.length == _retells.length) return;
    _retells = List<RetellRecord>.unmodifiable(next);
    notifyListeners();
    try {
      final data = await _learningRepo.load();
      data.retells = next;
      await _learningRepo.writeSection(data, LearningSection.retells);
    } catch (e) {
      _error = '删复述失败：$e';
      notifyListeners();
    }
  }
}
