// 「一键处理」五步的编排：每步都要真正落库，冲突时重放。
import 'package:dlaoshi_app/core/ecdict.dart';
import 'package:dlaoshi_app/core/tatoeba.dart';
import 'package:dlaoshi_app/data/db/migrations.dart' show ensureSchema;
import 'package:dlaoshi_app/data/repositories/article_repository.dart';
import 'package:dlaoshi_app/data/repositories/vocab_repository.dart';
import 'package:dlaoshi_app/models/document.dart';
import 'package:dlaoshi_app/models/vocab.dart';
import 'package:dlaoshi_app/services/dict_tools_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../support/vocab_fixture.dart';

final _at = DateTime.parse('2026-11-14T00:00:00.000Z');

const String _words = 'run\trʌn\tv\tmove fast\tv. 跑\tcet4\t3\t1\t100\t100\n'
    'hobble\t\'hɒbl\t\tvt. prevent\tt. 阻碍\tgre\t\t\t8000\t9000\n'
    'adapt\tə\'dæpt\tv\tmake suitable\tv. 适应\tcet4\t3\t1\t2000\t2000\n'
    'adopt\tə\'dɒpt\tv\ttake as own\tv. 收养\tcet4\t3\t1\t3000\t3000\n'
    'adept\tə\'dept\tadj\tskilled\tadj. 熟练的\tgre\t\t\t7000\t7000\n'
    'adrift\tə\'drɪft\tadj\tfloating\tadj. 漂浮的\tgre\t\t\t9000\t9000\n'
    'pernicious\tpə\'nɪʃəs\tadj\tharmful\tadj. 有害的\tgre\t\t\t12000\t12000\n';

const String _forms = 'ran\trun\n';

const String _near = 'adapt\tadopt,adept,adrift\n';

Ecdict _dict() => parseEcdict(_words, _forms, _near);

VocabLibrary _lib(List<VocabItem> items) => VocabLibrary(items: items);

SavedArticle _article() => SavedArticle(
      id: 'a1',
      title: 'T',
      updatedAt: _at.toIso8601String(),
      paragraphs: const [Paragraph(id: 'p1', sentenceIds: ['s1'])],
      sentences: const [
        Sentence(
          id: 's1',
          paraId: 'p1',
          text: 'This pernicious habit is hard to break.',
        ),
      ],
    );

void main() {
  late Database db;
  late VocabRepository vocab;
  late ArticleRepository articles;

  setUpAll(() => sqfliteFfiInit());

  setUp(() async {
    db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    await ensureSchema(db);
    vocab = VocabRepository(db);
    articles = ArticleRepository(db);
  });

  tearDown(() async => db.close());

  DictToolsService service({ExampleLookup? lookup}) => DictToolsService(
        vocab: vocab,
        articles: articles,
        exampleLookup: lookup,
        clock: () => _at,
      );

  group('每步单独跑', () {
    test('enrich：补齐后落库，第二次跑是 skipped', () async {
      await vocab.save(_lib([vocabItem(word: 'hobble', lemma: 'hobble')]));
      final s = service();

      final first = await s.run('enrich', dict: _dict());
      expect(first.status, DictStepStatus.ok);
      expect(first.count, 1);

      final saved = (await vocab.load())!.items.single;
      expect(saved.phonetic, "/'hɒbl/");
      expect(saved.meaning, contains('阻碍'));

      final second = await s.run('enrich', dict: _dict());
      expect(second.status, DictStepStatus.skipped);
    });

    test('lemma：ran → run，并落库', () async {
      await vocab.save(_lib([vocabItem(word: 'ran', lemma: 'ran')]));
      final out = await service().run('lemma', dict: _dict());
      expect(out.status, DictStepStatus.ok);
      expect(out.count, 1);

      final saved = (await vocab.load())!.items.single;
      expect(saved.word, 'run');
      expect(saved.lemma, 'run');
    });

    test('confuse：给缺干扰项的词补 3 个，来源记 dict', () async {
      await vocab.save(_lib([
        vocabItem(word: 'adapt', lemma: 'adapt', meaning: '适应'),
        vocabItem(
          id: 'v2',
          word: 'hobble',
          lemma: 'hobble',
          meaning: '阻碍',
          confusables: const [
            VocabConfusable(word: 'hobble', meaning: '已有'),
          ],
        ),
      ]));
      final out = await service().run('confuse', dict: _dict());
      expect(out.status, DictStepStatus.ok);
      expect(out.count, 1);

      final saved = (await vocab.load())!.items;
      final adapt = saved.firstWhere((it) => it.lemma == 'adapt');
      expect(adapt.confusables, hasLength(3));
      expect(adapt.confusablesSource, VocabConfusableSource.dict);
      final hobble = saved.firstWhere((it) => it.lemma == 'hobble');
      expect(hobble.confusables, hasLength(1), reason: '已有的不覆盖');
    });

    test('examples：按词形查 Tatoeba 并落库，第二次跑 skipped', () async {
      await vocab.save(_lib([vocabItem(word: 'mitigate', lemma: 'mitigate')]));
      Set<String>? asked;
      final s = service(lookup: (words) async {
        asked = words;
        return {
          'mitigate': const [
            TatoebaExample(en: 'The drug can mitigate the pain.', zh: '这种药能减轻疼痛。'),
          ],
        };
      });

      final first = await s.run('examples', dict: null);
      expect(first.status, DictStepStatus.ok);
      expect(first.count, 1);
      expect(asked, contains('mitigate'));

      final saved = (await vocab.load())!.items.single;
      expect(saved.examples, hasLength(1));
      expect(saved.examples.single.origin, VocabExampleOrigin.tatoeba);

      final second = await s.run('examples', dict: null);
      expect(second.status, DictStepStatus.skipped);
    });

    test('examples：例句库里查不到 → skipped，不写库', () async {
      await vocab.save(_lib([vocabItem(word: 'zzzz', lemma: 'zzzz')]));
      final out = await service(lookup: (_) async => const {})
          .run('examples', dict: null);
      expect(out.status, DictStepStatus.skipped);
      expect((await vocab.load())!.items.single.examples, isEmpty);
    });

    test('pick：按水平挑超纲词并收进本篇，带来源句原文', () async {
      await articles.save(_article());
      await vocab.save(
        _lib([vocabItem(word: 'habit', lemma: 'habit', meaning: '习惯')]),
      );
      final out = await service()
          .run('pick', dict: _dict(), articleId: 'a1', level: EcdictLevel.cet6);
      expect(out.status, DictStepStatus.ok);
      expect(out.count, 1);

      final saved = (await vocab.load())!;
      final item = saved.items.firstWhere((it) => it.lemma == 'pernicious');
      expect(item.examples.single.text, 'This pernicious habit is hard to break.');
      expect(item.source?.articleId, 'a1');
      expect(
        saved.articleEntries.any(
          (e) => e.articleId == 'a1' && e.lemma == 'pernicious',
        ),
        isTrue,
      );
    });

    test('pick：没选文章 → skipped（不静默退回全库）', () async {
      final out = await service().run('pick', dict: _dict(), articleId: null);
      expect(out.status, DictStepStatus.skipped);
      expect(out.message, contains('精读页'));
    });

    test('词典没加载：依赖词典的步骤 skipped 并说明', () async {
      final out = await service().run('enrich', dict: null);
      expect(out.status, DictStepStatus.skipped);
      expect(out.message, contains('词典'));
    });
  });

  group('runAll', () {
    test('按五步顺序全跑，失败 / 跳过不阻断后面的步骤', () async {
      await vocab.save(_lib([
        vocabItem(word: 'hobble', lemma: 'hobble'),
        vocabItem(id: 'v2', word: 'adapt', lemma: 'adapt', meaning: '适应'),
        vocabItem(id: 'v3', word: 'ran', lemma: 'ran'),
      ]));
      final out = await service(lookup: (_) async => const {})
          .runAll(dict: _dict());
      expect(out.map((o) => o.stepId), [
        'pick',
        'enrich',
        'examples',
        'lemma',
        'confuse',
      ]);
      expect(out.first.status, DictStepStatus.skipped, reason: '没选文章');
      expect(
        out.where((o) => o.status == DictStepStatus.ok).length,
        greaterThanOrEqualTo(3),
      );
      // 没有一步是 failed（词典和库都正常）。
      expect(out.where((o) => o.status == DictStepStatus.failed), isEmpty);
    });
  });
}
