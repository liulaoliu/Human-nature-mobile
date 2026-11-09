/// 金句课「课程」的编辑与写回。
///
/// 为什么单独一个类：课程本身是**文章的一部分**（写回 `SavedArticle.golden`），
/// 而练习进度、金句本、会话位置属于学习侧。两者的写入方、失败处理、
/// 触发频率都不一样；混在一个 ViewModel 里，`tool/check_god_class.dart`
/// 的方法数上限（40）也撑不住。
///
/// 这里只管：改选句 / 改设置 / 加删语言点 / 一键挑句，以及把结果写回文章。
library;

import 'package:flutter/foundation.dart';

import '../core/golden.dart';
import '../core/golden_article.dart';
import '../core/golden_parse.dart';
import '../data/repositories/article_repository.dart';
import '../models/document.dart';

/// 课程的编辑入口。
class GoldenLessonEditor extends ChangeNotifier {
  GoldenLessonEditor({
    required ArticleRepository articles,
    required this.sentencesOf,
    required this.paragraphsOf,
    required this.onNotice,
    required this.onFail,
  }) : _articlesRepo = articles;

  final ArticleRepository _articlesRepo;

  /// 现取当前文章的句子（不存副本：换文章时整份换掉）。
  final List<Sentence> Function() sentencesOf;

  /// 现取当前文章的段落。
  final List<Paragraph> Function() paragraphsOf;

  /// 提示（非错误，比如「至少留一句」）。
  final void Function(String message) onNotice;

  /// 出错（写库失败等）。
  final void Function(String message) onFail;

  SavedArticle? _article;
  GoldenLesson? _lesson;

  /// 当前文章。
  SavedArticle? get article => _article;

  /// 当前课程；文章还没金句课时是按课文生成的本地草稿。
  GoldenLesson? get lesson => _lesson;

  /// 已选句子（按原文顺序）。
  List<String> get selectedIds {
    final lesson = _lesson;
    if (lesson == null) return const <String>[];
    if (lesson.selected.isNotEmpty) return lesson.selected;
    return lesson.sentences.map((s) => s.id).toList();
  }

  /// 换文章：读出已存的课，读不到就按课文生成一份本地课程。
  void adopt(SavedArticle? article) {
    _article = article;
    _lesson = _buildLesson(article);
  }

  /// 改选句（调用方负责按原文顺序给）。
  Future<void> setSelected(List<String> ids) =>
      patch((GoldenLesson l) => l.copyWith(selected: ids));

  /// 勾 / 取消一句；只剩一句时不许取消。
  Future<void> toggleSentence(String id) {
    final lesson = _lesson;
    if (lesson == null) return Future<void>.value();
    final ids = selectedIds.toList();
    if (ids.contains(id)) {
      if (ids.length <= 1) {
        onNotice('至少留一句，不然这一课就空了');
        return Future<void>.value();
      }
      ids.remove(id);
    } else {
      ids.add(id);
    }
    // 统一按原文顺序落，免得勾选顺序决定出题顺序。
    return setSelected(<String>[
      for (final sentence in sentencesOf())
        if (ids.contains(sentence.id)) sentence.id,
    ]);
  }

  /// 一键挑句：推荐 / 全部 / AI 挑的 / 手选。
  Future<void> setPick(GoldenPickMode mode) {
    switch (mode) {
      case GoldenPickMode.recommended:
        return setSelected(
          pickGoldenCandidates(sentencesOf(), goldenDefaultLimit)
              .map((GoldenCandidate c) => c.id)
              .toList(),
        );
      case GoldenPickMode.all:
        return setSelected(sentencesOf().map((Sentence s) => s.id).toList());
      case GoldenPickMode.ai:
        final ai = _lesson?.aiSelected ?? const <String>[];
        return setSelected(ai.isEmpty ? selectedIds : ai);
      case GoldenPickMode.manual:
        return patch(
          (GoldenLesson l) => l.copyWith(
            options: l.options.copyWith(pick: () => GoldenPickMode.manual),
          ),
        );
    }
  }

  /// 去重开关（同一个学习点只练一次）。
  Future<void> setDedupe(bool value) => patch((GoldenLesson l) {
        final merged = l.copyWith(options: l.options.copyWith(dedupe: value));
        return value ? dedupeGoldenLesson(merged) : merged;
      });

  /// 挖空单位：按词 / 按整块。
  Future<void> setBlankUnit(GoldenBlankUnit unit) => patch(
        (GoldenLesson l) =>
            l.copyWith(options: l.options.copyWith(blankUnit: () => unit)),
      );

  /// 填空后要不要加练整句。
  Future<void> setSentenceFill(bool value) => patch(
        (GoldenLesson l) =>
            l.copyWith(options: l.options.copyWith(sentenceFill: () => value)),
      );

  /// 隔几句安排一次小测（5 / 10；null 是不安排）。
  Future<void> setExamAfter(int? value) => patch(
        (GoldenLesson l) =>
            l.copyWith(options: l.options.copyWith(examAfter: () => value)),
      );

  /// 手动加一条加练语言点（同句同英文只留一条）。
  Future<void> addExtraPoint(String sentenceId, String en, {String? zh}) {
    final trimmed = en.trim();
    if (trimmed.isEmpty) {
      onNotice('先写一个英文语言点');
      return Future<void>.value();
    }
    final gloss = (zh ?? '').trim();
    return patch((GoldenLesson l) {
      final points = <GoldenExtraPoint>[
        ...?l.extraPoints,
        GoldenExtraPoint(
          sentenceId: sentenceId,
          en: trimmed,
          kind: GoldenExtraPointKind.chunk,
          source: GoldenExtraPointSource.user,
          zh: gloss.isEmpty ? null : gloss,
        ),
      ];
      return l.copyWith(
        extraPoints: () => normalizeGoldenExtraPoints(
          <Object?>[for (final GoldenExtraPoint p in points) p.toJson()],
          <String>{for (final Sentence s in sentencesOf()) s.id},
        ),
      );
    });
  }

  /// 删一条加练语言点。
  Future<void> removeExtraPoint(String sentenceId, String en) {
    final key = en.trim().toLowerCase();
    return patch((GoldenLesson l) {
      final points = <GoldenExtraPoint>[
        for (final GoldenExtraPoint p in l.extraPoints ?? const <GoldenExtraPoint>[])
          if (!(p.sentenceId == sentenceId &&
              p.en.trim().toLowerCase() == key))
            p,
      ];
      return l.copyWith(extraPoints: () => points);
    });
  }

  /// 改一处课程并写回文章。
  Future<void> patch(GoldenLesson Function(GoldenLesson) change) async {
    final lesson = _lesson;
    if (lesson == null) return;
    await save(change(lesson));
  }

  /// 整份存回文章；成功返回 null，失败返回原因。
  Future<String?> save(GoldenLesson lesson) async {
    final article = _article;
    if (article == null) return '先选一篇文章';
    _lesson = lesson;
    notifyListeners();
    try {
      final saved = withGoldenLesson(article, lesson);
      await _articlesRepo.save(saved);
      _article = saved;
      return null;
    } catch (e) {
      onFail('课程没存进文章：$e');
      return '课程没存进文章：$e';
    }
  }

  /// 某一句上额外加练的语言点。
  List<GoldenExtraPoint> extraPointsFor(String sentenceId) {
    final points = _lesson?.extraPoints ?? const <GoldenExtraPoint>[];
    return points
        .where((GoldenExtraPoint p) => p.sentenceId == sentenceId)
        .toList();
  }

  GoldenLesson? _buildLesson(SavedArticle? article) {
    if (article == null) return null;
    final saved = goldenLessonOf(article);
    if (saved != null) return saved;
    return buildLocalGoldenLesson(
      article.sentences,
      paragraphsOf(),
      LocalGoldenOptions(selected: _savedSelectionOf(article.golden)),
    );
  }

  /// 旧数据里 `golden` 只存了 `selected` 时也能接着用。
  List<String>? _savedSelectionOf(Map<String, Object?>? raw) {
    if (raw == null) return null;
    final selected = goldenStrList(raw['selected']);
    return selected.isEmpty ? null : selected;
  }
}
