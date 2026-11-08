/// 文章内容指纹与列表日期口径。
///
/// 对应 Web 版 `src/core/articleMeta.ts`。
library;

import 'activity/activity.dart';
import '../models/document.dart';

/// 文章列表显示的日期口径：**建立日为主**，只有真的改过才附带修改日。
///
/// 无可用时间返回空串，由视图决定不渲染，避免出现 `NaN-NaN-NaN`。
class ArticleDateKeys {
  const ArticleDateKeys({
    required this.created,
    required this.updated,
    required this.edited,
  });

  /// 建立日期 YYYY-MM-DD；老数据没有 createdAt 时用 updatedAt 兜底。
  final String created;

  /// 最近修改日期 YYYY-MM-DD。
  final String updated;

  /// 修改日与建立日不同（界面才需要显示「改」）。
  final bool edited;

  @override
  String toString() => 'ArticleDateKeys($created, $updated, edited: $edited)';
}

/// 文章内容指纹。
///
/// 自动落盘靠它判断「这次 effect 是打开文章，还是用户真的改了东西」：
/// 只有指纹变了才写库，避免点一下列表就把 `updatedAt`（以及列表里的日期）顶掉。
///
/// 口径与 Web 版一致：标题 / 书名 / 来源 / 正文 / 段落 / 句子 / 金句；
/// 句子里的分析结果（翻译、语言点、生词）也算内容。
String articleFingerprint(SavedArticle a) => articleContentFingerprint(
      title: a.title,
      book: a.book,
      origin: a.origin,
      text: a.text,
      paragraphs: a.paragraphs,
      sentences: a.sentences,
      golden: a.golden,
    );

/// 分字段版本：改正文时还没重新切句，也要能算指纹（Web 版取的是 `Pick<>`）。
String articleContentFingerprint({
  required String title,
  String? book,
  ArticleOrigin? origin,
  required String text,
  required List<Paragraph> paragraphs,
  required List<Sentence> sentences,
  Map<String, Object?>? golden,
}) {
  final parts = <Object?>[
    title,
    book ?? '',
    origin?.name ?? '',
    text,
    [for (final p in paragraphs) '${p.id}\u0001${p.sentenceIds.join(',')}'],
    [for (final s in sentences) _sentenceFingerprint(s)],
    golden ?? '',
  ];
  // 不用 jsonEncode：这里只要稳定唯一，手拼可省一层转义，且对 Map 的键顺序不敏感。
  return parts.map(_stableToString).join('\u0002');
}

/// 文章列表日期口径。
ArticleDateKeys articleDateKeys(SavedArticle a) =>
    articleDateKeysOf(createdAt: a.createdAt, updatedAt: a.updatedAt);

/// 分字段版本（老数据可能没有 createdAt）。
ArticleDateKeys articleDateKeysOf({required String? createdAt, required String updatedAt}) {
  final created = _dayKey(createdAt ?? '');
  final updated = _dayKey(updatedAt);
  final createdResolved = created.isNotEmpty ? created : updated;
  return ArticleDateKeys(
    created: createdResolved,
    updated: updated,
    edited: updated.isNotEmpty && updated != createdResolved,
  );
}

String _dayKey(String iso) {
  if (iso.isEmpty) return '';
  final d = DateTime.tryParse(iso);
  return d == null ? '' : calendarDayKey(d.toLocal());
}

String _sentenceFingerprint(Sentence s) {
  final langs = s.languages ?? const <SentenceLanguage>[];
  final single = s.language;
  return <Object?>[
    s.id,
    s.paraId,
    s.text,
    s.translation ?? '',
    s.grammarNote ?? '',
    s.collocations.join(','),
    s.vocab.join(','),
    s.tags.join(','),
    single == null ? '' : _languageFingerprint(single),
    [for (final l in langs) _languageFingerprint(l)],
  ].map(_stableToString).join('\u0003');
}

String _languageFingerprint(SentenceLanguage l) => <Object?>[
      l.structure ?? '',
      l.grammar ?? '',
      (l.idioms ?? const <String>[]).join(','),
      (l.phrases ?? const <String>[]).join(','),
      (l.usage ?? const <String>[]).join(','),
      l.source?.name ?? '',
    ].map(_stableToString).join('\u0004');

String _stableToString(Object? v) {
  if (v == null) return '';
  if (v is String) return v;
  if (v is Iterable<Object?>) return '[${v.map(_stableToString).join('\u0005')}]';
  if (v is Map) {
    final keys = v.keys.map((k) => '$k').toList()..sort();
    return '{${keys.map((k) => '$k=${_stableToString(v[k])}').join('\u0005')}}';
  }
  return '$v';
}
