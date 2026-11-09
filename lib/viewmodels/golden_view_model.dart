/// 金句课的页面级状态：课程、练习进度、金句本、会话位置。
///
/// 分四层：
///   - `lib/core/golden*.dart` —— 纯函数（选句、出题、判分、进度合并），全部有单测；
///   - `lib/viewmodels/golden_lesson_editor.dart` —— 课程本身的编辑与写回文章；
///   - `lib/viewmodels/golden_drill_session.dart` —— 一句的逐轮练习（换句重置）；
///   - 本文件 —— 跨句的读取、落库、和文章/偏好的接线。
///
/// 落库口径（**两个不同的地方，别混**）：
///   - 课程（选哪些句、学习点、AI 合并结果）是**文章的一部分**，写回
///     `SavedArticle.golden`（走 `withGoldenLesson`），跟着文章一起存；
///   - 练习进度（第几次答对、是否掌握）只进 `LearningSection.goldenDrills`，
///     **永不清表**（见 `learning_repository.dart` 文件头的硬语义）。
library;

import 'dart:async';

import 'package:flutter/foundation.dart';

import '../core/golden.dart';
import '../core/golden_ai.dart';
import '../core/golden_article.dart';
import '../core/golden_bank.dart';
import '../core/golden_progress.dart';
import '../core/golden_session.dart';
import '../core/learning.dart';
import '../core/writing_record.dart';
import '../core/writing_record_json.dart';
import '../data/prefs_store.dart';
import '../data/repositories/article_repository.dart';
import '../data/repositories/learning_repository.dart';
import '../models/document.dart';
import 'golden_drill_session.dart';
import 'golden_lesson_editor.dart';

/// 金句课页面级 ViewModel。
class GoldenViewModel extends ChangeNotifier {
  GoldenViewModel({
    required ArticleRepository articles,
    required LearningRepository learning,
    PrefsStore? prefsStore,
  })  : _articlesRepo = articles,
        _learningRepo = learning,
        _prefsStore = prefsStore ?? PrefsStore.memory() {
    editor = GoldenLessonEditor(
      articles: articles,
      sentencesOf: () => sentences,
      paragraphsOf: () => paragraphs,
      onNotice: _noticeOnly,
      onFail: _fail,
    )..addListener(_bubble);
  }

  final ArticleRepository _articlesRepo;
  final LearningRepository _learningRepo;
  final PrefsStore _prefsStore;

  /// 课程编辑（选句、设置、加练语言点）。
  late final GoldenLessonEditor editor;

  late final GoldenDrillSession drill = GoldenDrillSession(
    lessonOf: () => editor.lesson,
    sentenceTextOf: textOf,
    recordStep: recordStep,
  )..addListener(_bubble);

  final List<ArticleRow> _library = <ArticleRow>[];
  final List<GoldenDrillRecord> _records = <GoldenDrillRecord>[];
  List<WritingRecord> _writing = const <WritingRecord>[];
  List<GoldenBankRow> _bank = const <GoldenBankRow>[];

  GoldenSession _session = emptyGoldenSession;
  bool _busy = false;
  bool _disposed = false;
  String? _error;
  String _notice = '';

  /// 可选文章。
  List<ArticleRow> get library => _library;

  /// 当前文章；没打开为 null。
  SavedArticle? get article => editor.article;

  /// 当前课程；文章没金句课时是本地生成的草稿。
  GoldenLesson? get lesson => editor.lesson;

  /// 当前文章的句子。
  List<Sentence> get sentences => editor.article?.sentences ?? const <Sentence>[];

  /// 当前文章的段落。
  List<Paragraph> get paragraphs =>
      editor.article?.paragraphs ?? const <Paragraph>[];

  /// 金句课相关写记录（语言点「练过没」从这里读）。
  List<WritingRecord> get history =>
      _writing.where(isGoldenWritingRecord).toList();

  /// 练习进度。
  List<GoldenDrillRecord> get records => _records;

  /// 金句本（全库，按文章摊平）。
  List<GoldenBankRow> get bank => _bank;

  /// 当前文章的会话位置。
  GoldenSession get session => _session;

  /// 掌握情况汇总。
  GoldenMasterySummary? get summary {
    final lesson = editor.lesson;
    if (lesson == null) return null;
    return summarizeGolden(
      lesson,
      goldenTextMetasOf(sentences),
      _records,
      articleId,
      paragraphs,
    );
  }

  /// 计划页的候选句（按得分排）。
  List<GoldenCandidate> get candidates =>
      pickGoldenCandidates(sentences, goldenDefaultLimit);

  /// 已选句子按原文顺序展开成课程内容。
  List<GoldenSentence> get ordered {
    final lesson = editor.lesson;
    if (lesson == null) return const <GoldenSentence>[];
    final ids = editor.selectedIds;
    final byId = <String, GoldenSentence>{
      for (final GoldenSentence content in lesson.sentences) content.id: content,
    };
    final out = <GoldenSentence>[];
    for (final String id in ids) {
      final content = byId[id];
      if (content != null) {
        out.add(content);
        continue;
      }
      for (final Sentence sentence in sentences) {
        if (sentence.id == id) {
          out.add(buildLocalGoldenSentence(sentence));
          break;
        }
      }
    }
    return out;
  }

  /// 文章 id（没打开时空串）。
  String get articleId => editor.article?.id ?? '';

  /// 文章标题。
  String get articleTitle => editor.article?.title ?? '';

  bool get busy => _busy;

  /// 出错原因；没有为 null。
  String? get error => _error;

  /// 一次性提示。
  String get notice => _notice;

  /// 读文章列表 + 练习进度 + 写记录。
  Future<void> bootstrap() async {
    await _guard(() async {
      final List<ArticleRow> rows = await _articlesRepo.list();
      _library
        ..clear()
        ..addAll(rows);
      final data = await _learningRepo.load();
      _records
        ..clear()
        ..addAll(normalizeGoldenDrills(data.goldenDrills));
      _writing = writingRecordsFromJson(data.writingHistory);
    });
  }

  /// 打开某篇文章的金句课。
  Future<void> openArticle(String id) async {
    await _guard(() async {
      final SavedArticle? article = await _articlesRepo.load(id);
      editor.adopt(article);
      _session = article == null
          ? emptyGoldenSession
          : _prefsStore.loadGoldenSession(article.id);
    });
  }

  /// 回到选文章那一步（不清文章里的课，只收起当前上下文）。
  void closeArticle() {
    editor.adopt(null);
    _session = emptyGoldenSession;
    _notice = '';
    _error = null;
    notifyListeners();
  }

  /// 一句的原文（找不到时空串）。
  String textOf(String sentenceId) {
    for (final Sentence sentence in sentences) {
      if (sentence.id == sentenceId) return sentence.text;
    }
    return '';
  }

  /// 一句的学习点（按课程当前的去重设置取）。
  List<GoldenTarget> targetsFor(String sentenceId) {
    final lesson = editor.lesson;
    if (lesson == null) return const <GoldenTarget>[];
    return goldenTargetsFor(lesson, sentenceId);
  }

  /// 一句的练习进度；没练过为 null。
  GoldenDrillRecord? recordFor(String sentenceId) {
    final key = goldenDrillKey(textOf(sentenceId), targetsFor(sentenceId));
    return findGoldenRecord(_records, articleId, sentenceId, key);
  }

  /// 一句是否已掌握。
  bool masteredFor(String sentenceId) =>
      recordFor(sentenceId)?.mastered ?? false;

  /// 记一步练习结果，立刻落库。
  void recordStep(String sentenceId, GoldenStep step, bool correct) {
    final articleId = this.articleId;
    if (articleId.isEmpty) return;
    final key = goldenDrillKey(textOf(sentenceId), targetsFor(sentenceId));
    final at = DateTime.now().toUtc().toIso8601String();
    final existing =
        findGoldenRecord(_records, articleId, sentenceId, key) ??
            emptyGoldenRecord(articleId, articleTitle, sentenceId, key, at);
    final next = mergeGoldenDrills(_records, <GoldenDrillRecord>[
      recordGoldenStep(existing, step, correct, at),
    ]);
    _records
      ..clear()
      ..addAll(next);
    unawaited(_persistRecords());
    if (!_disposed) notifyListeners();
  }

  /// 拼「让 AI 挑句」的提示词；没句子时返回 null 并把原因写进 [error]。
  String? buildPrompt() {
    final SavedArticle? article = editor.article;
    if (article == null) {
      _fail('先选一篇文章');
      return null;
    }
    final picked = candidates.take(goldenAiMaxSentences).toList();
    final pickedSentences = <Sentence>[
      for (final GoldenCandidate c in picked)
        ...sentences.where((Sentence s) => s.id == c.id),
    ];
    return buildGoldenPrompt(
      GoldenPromptInput(
        sentences: <GoldenPromptSentence>[
          for (final Sentence s in pickedSentences)
            GoldenPromptSentence(
              id: s.id,
              text: s.text,
              translation: s.translation,
              paraId: s.paraId,
            ),
        ],
        title: article.title,
      ),
    );
  }

  /// 粘回 AI 结果：解析后与本地课程合并（本地语言点不丢）。
  Future<String?> applyAi(String raw) {
    if (editor.article == null) return Future<String?>.value('先选一篇文章');
    final GoldenLesson? parsed =
        parseGoldenLesson(raw, goldenTextMetasOf(sentences));
    if (parsed == null) {
      return Future<String?>.value('没认出课程 JSON；请确认粘的是 AI 返回的那个对象');
    }
    final GoldenLesson? base = editor.lesson;
    final merged = base == null
        ? parsed
        : mergeGoldenLessons(
            base,
            parsed,
            sentences,
            const MergeGoldenOptions(preferAI: true),
          );
    return editor.save(merged).then((String? reason) {
      if (reason == null) _notice = 'AI 挑句已经合并进这一课';
      return reason;
    });
  }

  /// 换视图（同时把位置存进偏好，下次进来还在这一页）。
  void goView(String view) {
    if (!isGoldenView(view)) return;
    _session = _session.copyWith(view: view);
    _persistSession();
    notifyListeners();
  }

  /// 换到第几句（练习 / 回顾用）。
  void goIndex(int index, {bool recall = false}) {
    _session = recall
        ? _session.copyWith(recallIndex: index)
        : _session.copyWith(index: index);
    _persistSession();
    notifyListeners();
  }

  /// 读全库金句本（会读所有文章，按需调用）。
  Future<void> loadBank() async {
    await _guard(() async {
      final List<SavedArticle> all = await _articlesRepo.loadAll();
      final sources = <GoldenBankSource>[
        for (final SavedArticle article in all)
          if (goldenLessonOf(article) case final GoldenLesson lesson?)
            GoldenBankSource(
              id: article.id,
              title: article.title,
              sentences: goldenTextMetasOf(article.sentences),
              golden: lesson,
            ),
      ];
      _bank = buildGoldenBank(sources, _records);
    });
  }

  /// 清掉一次性提示 / 错误。
  void clearNotice() {
    _notice = '';
    _error = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    editor
      ..removeListener(_bubble)
      ..dispose();
    drill
      ..removeListener(_bubble)
      ..dispose();
    super.dispose();
  }

  /// 把练习进度落库。
  ///
  /// 失败**不抛**：`recordStep` 是界面同步调用的，抛出去会变成
  /// 「点一下填空就红屏」；进度丢了下次再练一遍就有，比崩掉强。
  Future<void> _persistRecords() async {
    try {
      final data = await _learningRepo.load();
      data.goldenDrills = <Map<String, Object?>>[
        for (final GoldenDrillRecord r in _records) r.toJson(),
      ];
      await _learningRepo.write(
        data,
        const <LearningSection>[LearningSection.goldenDrills],
      );
    } catch (e) {
      _fail('练习进度没存上：$e');
    }
  }

  void _persistSession() {
    final articleId = this.articleId;
    if (articleId.isEmpty) return;
    unawaited(_prefsStore.saveGoldenSession(articleId, _session));
  }

  void _bubble() {
    if (!_disposed) notifyListeners();
  }

  void _noticeOnly(String message) {
    _notice = message;
    _bubble();
  }

  void _fail(String message) {
    _error = message;
    // 落库是异步的：ViewModel 已经 dispose（比如测试拆完环境）就别再通知界面，
    // 否则 `notifyListeners` 会在已销毁实例上抛断言。
    if (_disposed) return;
    notifyListeners();
  }

  Future<void> _guard(Future<void> Function() body) async {
    _busy = true;
    _error = null;
    notifyListeners();
    try {
      await body();
    } catch (e) {
      _error = '出了点问题：$e';
    } finally {
      _busy = false;
      if (!_disposed) notifyListeners();
    }
  }
}
