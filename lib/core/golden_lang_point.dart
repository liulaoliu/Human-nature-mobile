/// 「语言点造句」的可选项（对应 Web `src/core/goldenLangPoint.ts`）。
///
/// 为什么只要 phrases / idioms：造句要求「必须用上 X」，X 得是能直接写进英文
/// 句子的片段；`usage` 是中文说明（“so-called 常带保留态度”），
/// `structure` / `grammar` 是整句规则，它们已经在「整句仿写」的 targets 里覆盖了，
/// 单独拎出来没法当 mustUse。
///
/// 纯函数：只读本句 + 已练过的 focus 集合，不碰词库、不碰存储。
library;

import '../models/document.dart' show Sentence;
import 'lang_points.dart' show splitGlossText;
import 'language.dart' show getSentenceLanguages;
import 'writing_record.dart' show WritingRecord;

/// 一个可以单练的语言点。
class LangPointChoice {
  const LangPointChoice({
    required this.en,
    this.zh,
    required this.done,
  });

  /// 必须用上的英文片段。
  final String en;

  /// 中文释义（语言点里带就带，没有就不显示）。
  final String? zh;

  /// 这一句里已经练过（`writingHistory` 里有同句同 focus 的记录）。
  final bool done;
}

/// focus 的比较口径（大小写 / 空白不敏感）。
String langPointKey(String text) =>
    text.replaceAll(RegExp(r'\s+'), ' ').trim().toLowerCase();

/// 本句可单练的语言点，按语言点出现顺序去重；没有就返回空列表。
///
/// [extraPoints] 是用户主动「加入本课」的语言点，排在文章自带之后，同英文只留一条。
List<LangPointChoice> langPointChoices(
  Sentence? sentence, {
  Set<String>? doneFocus,
  List<({String en, String? zh})>? extraPoints,
}) {
  if (sentence == null) return const <LangPointChoice>[];
  final done = doneFocus ?? const <String>{};
  final seen = <String>{};
  final out = <LangPointChoice>[];
  for (final l in getSentenceLanguages(sentence)) {
    for (final raw in <String>[
      ...?l.phrases,
      ...?l.idioms,
    ]) {
      final split = splitGlossText(raw);
      final en = split.word.trim();
      if (en.isEmpty) continue;
      final k = langPointKey(en);
      if (!seen.add(k)) continue;
      out.add(LangPointChoice(
        en: en,
        zh: split.gloss,
        done: done.contains(k),
      ));
    }
  }
  for (final p in extraPoints ?? const <({String en, String? zh})>[]) {
    final en = p.en.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (en.isEmpty) continue;
    final k = langPointKey(en);
    if (!seen.add(k)) continue;
    out.add(LangPointChoice(en: en, zh: p.zh, done: done.contains(k)));
  }
  return List<LangPointChoice>.unmodifiable(out);
}

/// 从记录里捞出「同篇同句、已经练过的 focus」。
Set<String> doneLangPoints(
  List<WritingRecord> records,
  String articleId,
  String sentenceId,
) {
  final out = <String>{};
  for (final r in records) {
    if (r.articleId != articleId || r.sentenceId != sentenceId) continue;
    final focus = r.task?.focus;
    if (focus != null && focus.trim().isNotEmpty) {
      out.add(langPointKey(focus));
    }
  }
  return out;
}

/// AI 批改引用文章语言点时的稳定 id：`lp:<sentenceId>:<slug>`。
String langPointChoiceId(String sentenceId, String en) {
  final slug = langPointKey(en)
      .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
      .replaceAll(RegExp(r'^-+|-+$'), '');
  return 'lp:$sentenceId:${slug.isEmpty ? 'x' : slug}';
}
