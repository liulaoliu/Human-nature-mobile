import 'package:dlaoshi_app/core/library_validate.dart';
import 'package:dlaoshi_app/core/migrations.dart';
import 'package:dlaoshi_app/core/vocab/library.dart';
import 'package:dlaoshi_app/models/vocab.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/vocab_fixture.dart';

/// 词库不变量校验：数据是唯一资产，这里负责把结构问题指出来
/// （`error` 必须在迁移时被修掉，`warn` 只是可疑）。
///
/// 对应 Web 版 `src/core/libraryValidate.test.ts`。
///
/// 差异说明：Web 版的入参是 `unknown`，所以能抓「items 不是数组」；
/// Dart 侧入参是 [VocabLibrary]，类型系统已经挡住这层，
/// **原始 JSON 的形状守卫放在后续的 `backup_parse.dart` 里**。
const now = '2026-10-02T00:00:00.000Z';

void main() {
  group('validateLibrary：error', () {
    test('正常库没有任何问题', () {
      final lib = createLibrary().copyWith(items: [
        vocabItem(id: 'vocab:run', word: 'run', lemma: 'run'),
      ]);
      expect(validateLibrary(lib), isEmpty);
    });

    test('抓：lemma 重复 / 时间不是 ISO / id 为空', () {
      final bad = createLibrary().copyWith(items: [
        vocabItem(id: 'vocab:run', word: 'run', lemma: 'run'),
        vocabItem(id: 'vocab:run2', word: 'running', lemma: 'run'), // lemma 重复
        vocabItem(id: 'vocab:y', word: 'y', lemma: 'y', createdAt: '昨天'),
        vocabItem(id: '', word: 'z', lemma: 'z'),
      ]);
      final msgs = libraryErrors(bad).map((i) => i.message).join(' | ');
      expect(msgs, contains('lemma 重复'));
      expect(msgs, contains('createdAt'));
      expect(msgs, contains('缺少 id'));
    });

    test('reviewState.due 坏值只 warn', () {
      final lib = createLibrary().copyWith(items: [
        vocabItem(id: 'vocab:z', word: 'z', lemma: 'z',
            reviewState: const ReviewState(due: '明天')),
      ]);
      expect(libraryErrors(lib), isEmpty);
      expect(validateLibrary(lib).map((i) => i.message).join(' | '), contains('reviewState.due'));
    });

    test('articleEntries：缺 articleId / 缺 lemma / 指向不存在的词 / 重复 / addedAt 坏', () {
      final lib = VocabLibrary(
        items: [vocabItem(id: 'vocab:alpha', lemma: 'alpha')],
        articleEntries: [
          articleEntry(articleId: '', lemma: 'alpha'),
          articleEntry(articleId: 'A', lemma: ''),
          articleEntry(articleId: 'A', lemma: 'ghost'),
          articleEntry(articleId: 'B', lemma: 'alpha'),
          articleEntry(articleId: 'B', lemma: 'alpha', addedAt: 'x'),
        ],
      );
      final msgs = libraryErrors(lib).map((i) => i.message).join(' | ');
      expect(msgs, contains('缺 articleId'));
      expect(msgs, contains('缺 lemma'));
      expect(msgs, contains('不存在的词'));
      expect(msgs, contains('重复'));
      expect(msgs, contains('addedAt'));
    });
  });

  group('validateLibrary：warn', () {
    test('id 与 lemma 不一致 / 例句缺 text / source.articleId 为空 → 只 warn', () {
      final issues = validateLibrary(createLibrary().copyWith(items: [
        vocabItem(
          id: 'vocab:old-name',
          word: 'run',
          lemma: 'run',
          examples: const [VocabExample(text: '  ')],
          source: const VocabSource(articleId: '', fileName: 'f', sentenceId: 's1'),
        ),
      ]));
      expect(issues.every((i) => i.level == LibraryIssueLevel.warn), isTrue);
      final msgs = issues.map((i) => i.message).join(' | ');
      expect(msgs, contains('id 与 lemma 不一致'));
      expect(msgs, contains('例句缺少 text'));
      expect(msgs, contains('source.articleId 为空'));
    });

    test('语境缺 articleId 也只 warn', () {
      final issues = validateLibrary(createLibrary().copyWith(items: [
        vocabItem(id: 'vocab:run', word: 'run', lemma: 'run', contexts: const [
          VocabContext(articleId: '', fileName: 'f', sentenceId: 's1', at: now),
        ]),
      ]));
      expect(issues.map((i) => i.message).join(' | '), contains('语境缺少 articleId'));
      expect(issues.every((i) => i.level == LibraryIssueLevel.warn), isTrue);
    });
  });

  test('toString 带级别与 id，排查时能直接定位', () {
    final issue = validateLibrary(createLibrary().copyWith(items: [
      vocabItem(id: 'vocab:old-name', word: 'run', lemma: 'run'),
    ])).first;
    expect(issue.toString(), startsWith('warn [vocab:old-name]: '));
  });

  test('migrateLibrary 的产物不该有 error（迁移与校验必须自洽）', () {
    final migrated = migrateLibrary({
      'items': [
        {'word': 'run', 'lemma': 'run'},
        {'word': 'fall back on', 'lemma': 'fall back on', 'kind': 'phrase'},
      ],
      'articleEntries': [
        {'articleId': 'A', 'lemma': 'run', 'origin': 'auto', 'addedAt': now},
      ],
    }, DateTime.parse(now));
    expect(libraryErrors(migrated), isEmpty);
  });
}
