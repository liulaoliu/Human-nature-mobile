// 释义解析顺序的用例（对应 Web 版 `src/core/articleMeaning.test.ts`）。
//
// 这一组的重点不是「能取到释义」，而是**取到的顺序对不对**：
// 手改的不能被 AI 覆盖，别的篇的语境不能串进来。

import 'package:dlaoshi_app/core/article_meaning.dart';
import 'package:dlaoshi_app/models/vocab.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/vocab_fixture.dart';

const at = '2026-10-01T00:00:00.000Z';

ArticleVocabEntry entry({String? meaning, VocabMeaningSource? meaningSource}) =>
    ArticleVocabEntry(
      articleId: 'A',
      lemma: 'bank',
      origin: VocabOrigin.manual,
      addedAt: at,
      meaning: meaning,
      meaningSource: meaningSource,
    );

VocabContext ctx({
  String articleId = 'A',
  String? sentenceId,
  String text = '',
  String? meaning,
}) =>
    VocabContext(
      articleId: articleId,
      fileName: articleId,
      sentenceId: sentenceId,
      sentenceText: text,
      meaning: meaning,
      at: at,
    );

VocabItem item({String? meaning = '银行', List<VocabContext>? contexts}) =>
    vocabItem(
      id: 'vocab:bank',
      word: 'bank',
      lemma: 'bank',
      meaning: meaning,
      contexts: contexts ??
          [
            ctx(sentenceId: 's1', text: 'river bank', meaning: '河岸'),
            ctx(articleId: 'B', sentenceId: 's9', text: 'bank account', meaning: '银行账户'),
          ],
    );

void main() {
  test('释义来源有统一显示文案（旧数据不硬猜）', () {
    expect(meaningSourceLabelMap, {
      VocabMeaningSource.manual: '手动',
      VocabMeaningSource.context: '语境',
      VocabMeaningSource.library: '词库',
      VocabMeaningSource.dict: '词典',
      VocabMeaningSource.ai: 'AI',
    });
    expect(meaningSourceLabel(VocabMeaningSource.dict), '词典');
    expect(meaningSourceLabel(null), isNull);
  });

  test('1. 本篇条目释义最高', () {
    final r = resolveArticleMeaning(
      item(),
      entry(meaning: '岸边（手改）'),
      'A',
      sentenceId: 's2',
    );
    expect(r, const ResolvedMeaning(text: '岸边（手改）', source: VocabMeaningSource.manual));
  });

  test('2. 同句语境优先于同篇其他句', () {
    final it = item(contexts: [
      ctx(sentenceId: 's1', text: 'a', meaning: '甲'),
      ctx(sentenceId: 's2', text: 'b', meaning: '乙'),
    ]);
    expect(resolveArticleMeaning(it, entry(), 'A', sentenceId: 's2')?.text, '乙');
  });

  test('3. 同篇其他句的语境', () {
    expect(resolveArticleMeaning(item(), entry(), 'A', sentenceId: 's3')?.text, '河岸');
  });

  test('4. 全库主释义兜底（别的篇的语境不串）', () {
    final r = resolveArticleMeaning(item(), entry(), 'C', sentenceId: 's1');
    expect(r?.text, '银行');
    expect(r?.source, VocabMeaningSource.library);
  });

  test('没有任何释义 → null', () {
    expect(
      resolveArticleMeaning(item(meaning: null, contexts: []), entry(), 'A'),
      isNull,
    );
  });

  test('条目释义带来源时保留来源，不写死成手改', () {
    final r = resolveArticleMeaning(
      item(),
      entry(meaning: '岸边', meaningSource: VocabMeaningSource.ai),
      'A',
    );
    expect(r?.source, VocabMeaningSource.ai);
  });

  test('后写的语境覆盖先写的（AI 重跑一次就更新）', () {
    final it = item(contexts: [
      ctx(sentenceId: 's1', text: 'a', meaning: '旧的'),
      ctx(sentenceId: 's1', text: 'a', meaning: '新的'),
    ]);
    expect(resolveArticleMeaning(it, entry(), 'A', sentenceId: 's1')?.text, '新的');
  });

  test('空串 / 空白的释义不算数，继续往下找', () {
    final it = item(contexts: [
      ctx(sentenceId: 's1', text: 'a', meaning: '   '),
    ]);
    expect(resolveArticleMeaning(it, entry(meaning: ''), 'A', sentenceId: 's1')?.text, '银行');
  });

  test('articleId 为空时不匹配任何语境（只看主释义）', () {
    expect(resolveArticleMeaning(item(), entry(), '', sentenceId: 's1')?.text, '银行');
  });
}
