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

import '../core/article_vocab.dart' show articleItemsOf;import '../core/intensive.dart';
import '../core/language.dart' show hasSentenceLanguage;
import '../core/learning.dart' show LearningSection;
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
}
