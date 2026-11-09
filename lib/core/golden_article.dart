/// 文章里的金句课内容：读回来过强类型守卫，写出去存回原始 JSON。
///
/// 为什么 `SavedArticle.golden` 仍然留 `Map<String, Object?>?`：
///   - 分层只许 `core → models` 单向收（`docs/ARCHITECTURE.md` §一），
///     `models` 反过来 import `core/golden_types.dart` 就是反向依赖；
///   - 但「读回来必须过守卫」这条不能松 —— 所以强类型只在 core 这一层出现：
///     入口 [goldenLessonOf]、出口 [withGoldenLesson]。
///
/// 这样 `SavedArticle` 是「磁盘上长什么样」，`GoldenLesson` 是「业务里长什么样」，
/// 两者之间只有这一个文件做转换。
library;

import '../models/document.dart';
import 'golden.dart';
import 'golden_parse.dart';

/// 文章里每句话的最小形状（守卫要按 id 对得上、按 text 逐字校验目标）。
List<GoldenTextMeta> goldenTextMetasOf(List<Sentence> sentences) =>
    <GoldenTextMeta>[
      for (final s in sentences)
        GoldenTextMeta(id: s.id, text: s.text, translation: s.translation),
    ];

/// 读这篇的金句课：没有 / 坏到修不出来都返回 null（界面上就是「还没生成」）。
///
/// 注意**不是**「读不出来就清库」：库里那份原始 JSON 原样留着，
/// 下次改回正文还能过守卫救回来。
GoldenLesson? goldenLessonOf(SavedArticle article) {
  final raw = article.golden;
  if (raw == null || raw.isEmpty) return null;
  return normalizeGoldenLesson(raw, goldenTextMetasOf(article.sentences));
}

/// 把金句课写回文章（存 `toJson()` 的原始形状）。
SavedArticle withGoldenLesson(SavedArticle article, GoldenLesson? lesson) =>
    article.copyWith(golden: () => lesson?.toJson());

/// 正文改过之后：把对不上的旧内容淘汰掉。
///
/// 返回原文章（`identical`）表示一个字都不用改，调用方据此跳过写库。
SavedArticle pruneGoldenOf(SavedArticle article) {
  final lesson = goldenLessonOf(article);
  if (lesson == null) {
    if (article.golden == null) return article;
    return article.copyWith(golden: () => null);
  }
  final pruned = pruneGoldenLesson(lesson, goldenTextMetasOf(article.sentences));
  if (pruned == null) return article.copyWith(golden: () => null);
  final next = pruned.toJson();
  if (_sameJson(article.golden, next)) return article;
  return article.copyWith(golden: () => next);
}

bool _sameJson(Object? a, Object? b) {
  if (a is Map && b is Map) {
    if (a.length != b.length) return false;
    for (final key in a.keys) {
      if (!b.containsKey(key)) return false;
      if (!_sameJson(a[key], b[key])) return false;
    }
    return true;
  }
  if (a is List && b is List) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (!_sameJson(a[i], b[i])) return false;
    }
    return true;
  }
  return a == b;
}
