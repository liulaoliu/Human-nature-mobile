// 测试用的词条 / 词库构造器。
//
// 对应 Web 版 `src/core/testFixtures.ts` 的 `vocabItem`：所有字段给默认值，
// 用例里只写自己关心的那几个。

import 'package:dlaoshi_app/models/vocab.dart';

const _at = '2026-01-01T00:00:00.000Z';

/// 造一条词条；不传的字段用「普通未查词单词」的默认值。
VocabItem vocabItem({
  String id = 'v1',
  String? word,
  String? lemma,
  VocabItemKind? kind,
  String? meaning,
  String? phonetic,
  String? partOfSpeech,
  String? definition,
  VocabStatus status = VocabStatus.unqueried,
  String createdAt = _at,
  String updatedAt = _at,
  ReviewState reviewState = defaultReviewState,
  List<VocabExample> examples = const [],
  List<String> tags = const [],
  String note = '',
  List<String> usage = const [],
  Map<VocabField, VocabFieldSource>? fieldSources,
  VocabSource? source,
  List<VocabContext>? contexts,
}) {
  final w = word ?? lemma ?? 'alpha';
  return VocabItem(
    id: id,
    word: w,
    lemma: lemma ?? w,
    kind: kind,
    meaning: meaning,
    phonetic: phonetic,
    partOfSpeech: partOfSpeech,
    definition: definition,
    status: status,
    createdAt: createdAt,
    updatedAt: updatedAt,
    reviewState: reviewState,
    examples: examples,
    tags: tags,
    note: note,
    usage: usage,
    fieldSources: fieldSources,
    source: source,
    contexts: contexts,
  );
}

/// 造一条按篇收录。
ArticleVocabEntry articleEntry({
  String articleId = 'A',
  String lemma = 'alpha',
  VocabOrigin origin = VocabOrigin.manual,
  VocabVia? via,
  String addedAt = _at,
  String? sentenceId,
  String sentenceText = '',
  String? meaning,
  VocabMeaningSource? meaningSource,
  String? printedAt,
}) {
  return ArticleVocabEntry(
    articleId: articleId,
    lemma: lemma,
    origin: origin,
    via: via,
    addedAt: addedAt,
    sentenceId: sentenceId,
    sentenceText: sentenceText,
    meaning: meaning,
    meaningSource: meaningSource,
    printedAt: printedAt,
  );
}

/// 空词库。
VocabLibrary emptyLibrary() => const VocabLibrary();
