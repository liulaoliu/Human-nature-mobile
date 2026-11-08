import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:dlaoshi_app/core/article_vocab.dart' show addArticleEntry;
import 'package:dlaoshi_app/core/vocab/library.dart';
import 'package:dlaoshi_app/core/vocab_browse.dart';
import 'package:dlaoshi_app/data/db/migrations.dart';
import 'package:dlaoshi_app/data/repositories/article_repository.dart';
import 'package:dlaoshi_app/data/repositories/vocab_repository.dart';
import 'package:dlaoshi_app/models/vocab.dart';
import 'package:dlaoshi_app/services/article_import_service.dart';
import 'package:dlaoshi_app/viewmodels/vocab_browse_view_model.dart';

VocabItem _item({
  required String lemma,
  String? meaning,
  String? partOfSpeech,
  VocabStatus status = VocabStatus.queried,
  String? due,
  int lapses = 0,
  String createdAt = '2026-11-01T00:00:00.000Z',
}) =>
    VocabItem(
      id: 'vocab:$lemma',
      word: lemma,
      lemma: lemma,
      meaning: meaning,
      partOfSpeech: partOfSpeech,
      status: status,
      reviewState: ReviewState(due: due, lapses: lapses),
      createdAt: createdAt,
      updatedAt: createdAt,
    );

VocabLibrary _lib(List<VocabItem> items) =>
    createLibrary().copyWith(items: items);

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  late Database db;
  late VocabRepository vocabRepo;
  late ArticleRepository articleRepo;
  late VocabBrowseViewModel vm;

  setUp(() async {
    db = await databaseFactory.openDatabase(inMemoryDatabasePath);
    await ensureSchema(db);
    vocabRepo = VocabRepository(db);
    articleRepo = ArticleRepository(db);
    vm = VocabBrowseViewModel(vocab: vocabRepo, articles: articleRepo);
  });

  tearDown(() async {
    vm.dispose();
    await db.close();
  });

  group('读库与默认状态', () {
    test('空库：没有条目，范围全 / 类型全 / 状态全 / 排序最近', () async {
      await vm.bootstrap();
      expect(vm.items, isEmpty);
      expect(vm.articles, isEmpty);
      expect(vm.scope, BrowseScope.all);
      expect(vm.kind, BrowseKind.all);
      expect(vm.status, BrowseStatus.all);
      expect(vm.sort, BrowseSort.recent);
      expect(vm.error, isNull);
    });

    test('读库后条目可数，排序默认最近收的在前', () async {
      await vocabRepo.save(_lib([
        _item(lemma: 'alpha', createdAt: '2026-11-01T00:00:00.000Z'),
        _item(lemma: 'beta', createdAt: '2026-11-05T00:00:00.000Z'),
      ]));
      await vm.bootstrap();
      expect(vm.items.map((i) => i.lemma), ['beta', 'alpha']);
    });

    test('文章列表带进来，本篇范围默认指第一篇', () async {
      final svc = ArticleImportService(articleRepo);
      await svc.createFromText(raw: 'He runs fast.', title: 'Run');
      await vm.bootstrap();
      expect(vm.articles.single.title, 'Run');
      expect(vm.currentArticleId, vm.articles.single.id);
    });
  });

  group('筛选与排序', () {
    setUp(() async {
      await vocabRepo.save(_lib([
        _item(
          lemma: 'alpha',
          meaning: '第一个',
          partOfSpeech: 'n.',
          createdAt: '2026-11-01T00:00:00.000Z',
          due: '2026-11-02T00:00:00.000Z',
        ),
        _item(
          lemma: 'beta',
          meaning: '第二个',
          createdAt: '2026-11-05T00:00:00.000Z',
          lapses: 2,
        ),
        _item(
          lemma: 'gamma',
          status: VocabStatus.mastered,
          createdAt: '2026-11-06T00:00:00.000Z',
        ),
      ]));
      await vm.bootstrap();
    });

    test('默认跳过已掌握；打开「含已掌握」三条都在', () {
      expect(vm.items.map((i) => i.lemma), ['beta', 'alpha']);
      vm.setIncludeMastered(true);
      expect(vm.items.length, 3);
    });

    test('「已掌握」状态明确只看 mastered，不受开关影响', () {
      vm.setStatus(BrowseStatus.mastered);
      expect(vm.items.map((i) => i.lemma), ['gamma']);
      vm.setIncludeMastered(true);
      expect(vm.items.map((i) => i.lemma), ['gamma']);
    });

    test('搜索命中单词 / 释义，大小写不敏感', () {
      vm.setQuery('ALP');
      expect(vm.items.map((i) => i.lemma), ['alpha']);
      vm.setQuery('第二个');
      expect(vm.items.map((i) => i.lemma), ['beta']);
    });

    test('状态「忘过」只剩 lapses > 0 的', () {
      vm.setStatus(BrowseStatus.lapsed);
      expect(vm.items.map((i) => i.lemma), ['beta']);
    });

    test('排序：字母 / 到期', () {
      vm.setSort(BrowseSort.alphabet);
      expect(vm.items.map((i) => i.lemma), ['alpha', 'beta']);
      vm.setSort(BrowseSort.due);
      // alpha 有 due，beta 没有（排最后）。
      expect(vm.items.map((i) => i.lemma), ['alpha', 'beta']);
    });

    test('入库日筛选：勾一天只剩那天的，清空恢复', () {
      final days = vm.dayOptions;
      expect(days.map((d) => d.day).toList(), isNotEmpty);
      final pick = days.first.day;
      vm.toggleDay(pick);
      expect(vm.items.every((i) => i.createdAt.startsWith(pick)), isTrue);
      vm.clearDays();
      expect(vm.items.length, 2);
    });

    test('scopeCount 是搜索 / 类型 / 日期之前的数（跟 includeMastered 走）', () {
      // 默认不含已掌握 → 3 条里排除 gamma。
      expect(vm.scopeCount, 2);
      vm.setIncludeMastered(true);
      expect(vm.scopeCount, 3);
      vm.setQuery('alpha');
      expect(vm.scopeCount, 3, reason: '搜索不影响 scopeCount');
      expect(vm.items.length, 1);
    });
  });

  group('选篇', () {
    test('勾了篇才出词；两篇都勾能同时看到两篇收的词', () async {
      final svc = ArticleImportService(articleRepo);
      final a = await svc.createFromText(raw: 'Alpha runs.', title: 'A');
      final b = await svc.createFromText(raw: 'Beta walks.', title: 'B');
      await vocabRepo.save(_lib([
        _item(lemma: 'alpha'),
        _item(lemma: 'beta'),
      ]));
      // 把两条词分别挂到两篇上（走 core 的 addArticleEntry）。
      final lib = (await vocabRepo.load())!;
      await vocabRepo.save(addArticleEntry(
        addArticleEntry(
          lib,
          articleId: a!.id,
          lemma: 'alpha',
          origin: VocabOrigin.manual,
        ),
        articleId: b!.id,
        lemma: 'beta',
        origin: VocabOrigin.manual,
      ));
      await vm.bootstrap();

      vm.setScope(BrowseScope.picked);
      expect(vm.items, isEmpty, reason: '一篇都没勾');

      vm.togglePicked(a.id);
      expect(vm.items.map((i) => i.lemma), ['alpha']);

      vm.togglePicked(b.id);
      expect(vm.items.map((i) => i.lemma), ['alpha', 'beta']);

      vm.togglePicked(a.id);
      expect(vm.items.map((i) => i.lemma), ['beta']);
    });

    test('本篇范围只出这一篇的词', () async {
      final svc = ArticleImportService(articleRepo);
      final a = await svc.createFromText(raw: 'Alpha runs.', title: 'A');
      await svc.createFromText(raw: 'Beta walks.', title: 'B');
      await vocabRepo.save(_lib([
        _item(lemma: 'alpha'),
        _item(lemma: 'beta'),
      ]));
      final lib = (await vocabRepo.load())!;
      await vocabRepo.save(addArticleEntry(
        lib,
        articleId: a!.id,
        lemma: 'alpha',
        origin: VocabOrigin.manual,
      ));
      await vm.bootstrap();

      vm.setScope(BrowseScope.article);
      vm.setCurrentArticle(a.id);
      expect(vm.items.map((i) => i.lemma), ['alpha']);
    });

    test('删掉的篇会从选篇里剔掉', () async {
      final svc = ArticleImportService(articleRepo);
      final a = await svc.createFromText(raw: 'Alpha runs.', title: 'A');
      await vm.bootstrap();
      vm.setScope(BrowseScope.picked);
      vm.togglePicked(a!.id);
      expect(vm.pickedArticleIds, {a.id});

      await articleRepo.remove(a.id);
      await vm.bootstrap();
      expect(vm.pickedArticleIds, isEmpty);
      expect(vm.scope, BrowseScope.all, reason: '选篇空了退回全部');
    });
  });
}
