import 'package:dlaoshi_app/core/article_vocab.dart';
import 'package:dlaoshi_app/core/entry_kind.dart';
import 'package:dlaoshi_app/core/lang_points.dart';
import 'package:dlaoshi_app/core/vocab/library.dart';
import 'package:dlaoshi_app/models/vocab.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/vocab_fixture.dart';

/// 语言点（词组 / 习语 / 用法笔记）的领域逻辑。
///
/// 这一批只移植了两件事：`textKey`（任意文本的去重键）与
/// `repairLanguageKinds`（修正早期版本把单词误标成用法/词组的脏数据）。
/// 用例逐条对照 Web 版 `src/core/langPoints.test.ts`。
const now = '2026-10-02T00:00:00.000Z';

void main() {
  group('textKey（任意文本的去重键）', () {
    test('统一大小写与空白，保留中文', () {
      expect(textKey('  Note  Purges  '), 'note purges');
      expect(textKey('注意 purges 在这里是名词复数'), '注意 purges 在这里是名词复数');
    });

    test('弯引号统一成直引号', () {
      expect(textKey('It\u2019s'), "it's");
      expect(textKey('It\u2018s'), "it's");
      expect(textKey('It\u02bcs'), "it's");
      expect(textKey('It\u2032s'), "it's");
    });

    test('全角转半角（经 nfkc）', () {
      expect(textKey('ＡＢＣ'), 'abc');
    });

    test('空串仍是空串', () {
      expect(textKey('   '), '');
    });
  });

  group('repairLanguageKinds：修早先版本误标', () {
    test('单词被标成用法 / 词组 → 改回；真笔记与真词组不动；幂等', () {
      final lib = createLibrary().copyWith(items: [
        vocabItem(id: 'a', word: 'purge', lemma: 'purge', kind: VocabItemKind.usage),
        vocabItem(id: 'b', word: 'alga', lemma: 'alga', kind: VocabItemKind.phrase),
        vocabItem(id: 'c', word: '注意 purges 是名词', lemma: '注意 purges 是名词', kind: VocabItemKind.usage),
        vocabItem(id: 'd', word: 'fall back on', lemma: 'fall back on', kind: VocabItemKind.phrase),
        vocabItem(id: 'e', word: '注意 purges 在这里是名词复数', lemma: '注意 purges 在这里是名词复数',
            kind: VocabItemKind.usage, status: VocabStatus.queried),
      ]);
      // 新代码写的带 langPointId → 不动
      final withMark = lib.copyWith(items: [
        ...lib.items.take(4),
        lib.items[4].copyWith(
          langPointId: () => 'usage|A|s1|注意 purges 在这里是名词复数',
        ),
      ]);

      final out = repairLanguageKinds(withMark);
      final byId = {for (final it in out.items) it.id: it};
      expect(byId['a']!.kind, isNull);
      expect(byId['b']!.kind, isNull);
      expect(byId['c']!.kind, VocabItemKind.usage);
      expect(byId['d']!.kind, VocabItemKind.phrase);
      expect(byId['e']!.kind, VocabItemKind.usage);
      expect(identical(repairLanguageKinds(out), out), isTrue); // 幂等
    });

    test('带旧 langPointId 的单单词 usage 也改回单词，并清掉标记', () {
      final lib = createLibrary().copyWith(
        items: [
          vocabItem(
            id: 'vocab:conglomerate',
            word: 'conglomerate',
            lemma: 'conglomerate',
            kind: VocabItemKind.usage,
            status: VocabStatus.queried,
            meaning: '企业集团',
          ).copyWith(langPointId: () => 'usage|A|s1|conglomerate 企业集团'),
        ],
        articleEntries: [
          articleEntry(
            articleId: 'A',
            lemma: 'conglomerate',
            origin: VocabOrigin.auto,
            addedAt: now,
            sentenceId: 's1',
            sentenceText: 'A family-controlled Danish conglomerate.',
          ),
        ],
      );
      final out = repairLanguageKinds(lib);
      expect(out.items[0].kind, isNull);
      expect(out.items[0].langPointId, isNull);
      expect(kindOfItem(out.items[0]), VocabKind.word);
      expect(out.articleEntries[0].lemma, 'conglomerate');
      expect(identical(repairLanguageKinds(out), out), isTrue);
    });

    test('旧 usage 笔记占着英文词键 → 改用整条文本键，同名单词能加回来', () {
      const note = 'mantra 本义为\u201c曼怛罗、祷文\u201d，引申为反复强调的口头禅。';
      final legacy = createLibrary().copyWith(
        items: [
          vocabItem(
            id: 'vocab:mantra',
            word: note,
            lemma: 'mantra',
            kind: VocabItemKind.usage,
            status: VocabStatus.queried,
          ),
        ],
        articleEntries: [
          articleEntry(
            articleId: 'A',
            lemma: 'mantra',
            origin: VocabOrigin.manual,
            addedAt: now,
            sentenceId: 's010',
            sentenceText: 'Mrs May\u2019s mantra.',
          ),
        ],
      );
      final out = repairLanguageKinds(legacy);
      final fixed = out.items[0];
      expect(fixed.lemma, textKey(note));
      expect(fixed.id, isNot('vocab:mantra'));
      expect(fixed.id, 'vocab:${textKey(note)}');
      expect(fixed.kind, VocabItemKind.usage);
      expect(out.articleEntries[0].lemma, textKey(note)); // 按篇条目跟着改名
      expect(identical(repairLanguageKinds(out), out), isTrue);
    });

    test('坏键已修好、没有其它问题 → 原样返回同一个对象', () {
      final clean = createLibrary().copyWith(items: [
        vocabItem(id: 'vocab:run', word: 'run', lemma: 'run'),
        vocabItem(id: 'vocab:fall back on', word: 'fall back on', lemma: 'fall back on',
            kind: VocabItemKind.phrase),
      ]);
      expect(identical(repairLanguageKinds(clean), clean), isTrue);
    });
  });
}
