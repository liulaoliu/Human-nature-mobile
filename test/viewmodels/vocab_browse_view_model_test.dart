import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:dlaoshi_app/core/article_vocab.dart' show addArticleEntry;
import 'package:dlaoshi_app/core/vocab/library.dart';
import 'package:dlaoshi_app/core/vocab_browse.dart';
import 'package:dlaoshi_app/core/vocab_browse_prefs.dart';
import 'package:dlaoshi_app/data/db/migrations.dart';
import 'package:dlaoshi_app/data/prefs_store.dart';
import 'package:dlaoshi_app/data/repositories/article_repository.dart';
import 'package:dlaoshi_app/data/repositories/vocab_repository.dart';
import 'package:dlaoshi_app/models/vocab.dart';
import 'package:dlaoshi_app/services/article_import_service.dart';
import 'package:dlaoshi_app/viewmodels/current_article_view_model.dart';
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

  /// 全局当前文章（词库的「本篇」= 它；用例里要能控制选没选、选了哪篇）。
  late CurrentArticleViewModel current;

  /// 老用例都按「全部 / 全部 / 全部」写的，用一份种子偏好把默认值钉住 ——
  /// 面板默认值（本篇 / 单词 / 复习）另有一组用例专门测。
  PrefsStore legacyStore() => PrefsStore.memory(<String, String>{
        vocabBrowsePrefsKey:
            '{"scope":"all","kind":"all","status":"all","sort":"recent"}',
      });

  setUp(() async {
    db = await databaseFactory.openDatabase(inMemoryDatabasePath);
    await ensureSchema(db);
    vocabRepo = VocabRepository(db);
    articleRepo = ArticleRepository(db);
    current = CurrentArticleViewModel(articlesRepo: articleRepo);
    vm = VocabBrowseViewModel(
      vocab: vocabRepo,
      articles: articleRepo,
      currentArticle: current,
      prefsStore: legacyStore(),
    );
  });

  tearDown(() async {
    vm.dispose();
    current.dispose();
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

    test('文章列表带进来，本篇跟着全局当前文章走', () async {
      final svc = ArticleImportService(articleRepo);
      await svc.createFromText(raw: 'He runs fast.', title: 'Run');
      await current.bootstrap();
      await vm.bootstrap();
      expect(vm.articles.single.title, 'Run');
      // 还没选文章：本篇没有来源。
      expect(vm.currentArticleId, isNull);
      // 精读页选了这一篇，词库这边立刻跟上（同一个 VM，不需要 refresh）。
      await current.select(vm.articles.single.id);
      expect(vm.currentArticleId, vm.articles.single.id);
      expect(vm.currentArticleTitle, 'Run');
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
    test('挑了一篇才出词；换一篇就只出新的那篇', () async {
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
      expect(vm.items, isEmpty, reason: '一篇都没挑');

      vm.setPickedArticle(a.id);
      expect(vm.pickedArticleId, a.id);
      expect(vm.items.map((i) => i.lemma), ['alpha']);

      // 单选：换一篇就是替换，不是累加。
      vm.setPickedArticle(b.id);
      expect(vm.items.map((i) => i.lemma), ['beta']);

      // 清掉就不出词了。
      vm.setPickedArticle(null);
      expect(vm.pickedArticleId, isNull);
      expect(vm.items, isEmpty);
    });

    test('本篇范围只出全局当前文章那一篇的词', () async {
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
      await current.bootstrap();
      await vm.bootstrap();

      vm.setScope(BrowseScope.article);
      // 全局还没选文章：本篇空着，不偷偷退回全库。
      expect(vm.items, isEmpty);

      await current.select(a.id);
      expect(vm.items.map((i) => i.lemma), ['alpha']);
    });

    test('选的那篇被删了：选篇清空，范围退回全部', () async {
      final svc = ArticleImportService(articleRepo);
      final a = await svc.createFromText(raw: 'Alpha runs.', title: 'A');
      await vm.bootstrap();
      vm.setScope(BrowseScope.picked);
      vm.setPickedArticle(a!.id);
      expect(vm.pickedArticleId, a.id);

      await articleRepo.remove(a.id);
      await vm.bootstrap();
      expect(vm.pickedArticleId, isNull);
      expect(vm.scope, BrowseScope.all, reason: '选篇空了退回全部');
    });

    test('全局当前文章被删了：本篇也退回全部', () async {
      final svc = ArticleImportService(articleRepo);
      final a = await svc.createFromText(raw: 'Alpha runs.', title: 'A');
      await current.bootstrap();
      await current.select(a!.id);
      await vm.bootstrap();
      // 老用例的种子偏好把范围钉在「全部」，这里显式切到「本篇」。
      vm.setScope(BrowseScope.article);
      expect(vm.scope, BrowseScope.article);
      expect(vm.currentArticleId, a.id);

      await articleRepo.remove(a.id);
      await current.refresh();
      await vm.bootstrap();
      expect(vm.currentArticleId, isNull);
      expect(vm.scope, BrowseScope.all, reason: '当前篇没了退回全部');
    });
  });

  group('筛选结果缓存', () {
    Future<void> seedThree() async {
      await vocabRepo.save(_lib([
        _item(lemma: 'alpha', createdAt: '2026-11-01T00:00:00.000Z'),
        _item(lemma: 'beta', createdAt: '2026-11-02T00:00:00.000Z'),
        _item(lemma: 'gamma', createdAt: '2026-11-03T00:00:00.000Z'),
      ]));
      await vm.bootstrap();
    }

    test('[Dart] 同一组条件连读多次只整库扫一次', () async {
      await seedThree();
      final before = vm.debugComputeCount;

      // 界面一帧里会取 items（条数 / 空态 / 列表）、scopeCount、dayOptions、
      // articleCounts，等价于连读好几遍。
      for (var i = 0; i < 5; i++) {
        expect(vm.items, hasLength(3));
        expect(vm.scopeCount, 3);
        expect(vm.dayOptions, isNotNull);
        expect(vm.articleCounts, isEmpty);
        expect(vm.result.items, hasLength(3));
      }

      expect(vm.debugComputeCount, before + 1, reason: '只算一次');
      expect(identical(vm.items, vm.items), isTrue, reason: '排序列表也复用');
      expect(identical(vm.result, vm.result), isTrue);
    });

    test('[Dart] 改条件后重算，结果跟着变', () async {
      await seedThree();
      expect(vm.items.map((i) => i.lemma), ['gamma', 'beta', 'alpha']);

      final before = vm.debugComputeCount;
      vm.setQuery('alp');
      expect(vm.items.map((i) => i.lemma), ['alpha']);
      expect(vm.debugComputeCount, before + 1);

      vm.setQuery('');
      expect(vm.items, hasLength(3));
    });

    test('[Dart] 只改排序时只重排，不重扫整库', () async {
      await seedThree();
      expect(vm.items.first.lemma, 'gamma');
      final resultBefore = vm.result;

      final before = vm.debugComputeCount;
      vm.setSort(BrowseSort.alphabet);
      expect(vm.items.map((i) => i.lemma), ['alpha', 'beta', 'gamma']);
      expect(identical(vm.items, vm.items), isTrue);
      expect(vm.debugComputeCount, before, reason: '筛选结果没变，不该重算');
      expect(identical(vm.result, resultBefore), isTrue, reason: '结果对象也是同一份');
    });

    test('[Dart] bootstrap 之后缓存作废，读得到新库', () async {
      await seedThree();
      expect(vm.items, hasLength(3));

      await vocabRepo.save(_lib([
        _item(lemma: 'alpha', createdAt: '2026-11-01T00:00:00.000Z'),
      ]));
      await vm.bootstrap();
      expect(vm.items.map((i) => i.lemma), ['alpha']);
    });

    test('[Dart] 各条件都会作废缓存（范围 / 类型 / 状态 / 搜索 / 日期 / 选篇 / 含已掌握）', () async {
      await seedThree();
      vm.items; // 先算一次，让计数有基准
      final start = vm.debugComputeCount;

      vm.setScope(BrowseScope.all); // 同值 → 不作废，读也不重算
      vm.items;
      expect(vm.debugComputeCount, start, reason: '同值 setter 不重算');

      vm.setKind(BrowseKind.word);
      vm.items;
      expect(vm.debugComputeCount, start + 1, reason: '类型变了');

      vm.setStatus(BrowseStatus.due);
      vm.items;
      expect(vm.debugComputeCount, start + 2, reason: '状态变了');

      vm.toggleDay('2026-11-01');
      vm.items;
      expect(vm.debugComputeCount, start + 3, reason: '日期变了');

      vm.clearDays();
      vm.items;
      expect(vm.debugComputeCount, start + 4, reason: '清日期');

      vm.setIncludeMastered(true);
      vm.items;
      expect(vm.debugComputeCount, start + 5, reason: '含已掌握');

      vm.setQuery('alp');
      vm.items;
      expect(vm.debugComputeCount, start + 6, reason: '搜索词');

      vm.setPickedArticle('nope');
      vm.items;
      expect(vm.debugComputeCount, start + 7, reason: '选篇');
    });

    test('[Dart] 返回的列表是同一份缓存，文档写明调用方别原地改', () async {
      await seedThree();
      final list = vm.items;
      expect(list, hasLength(3));
      expect(identical(vm.items, list), isTrue);
    });

    test('[Dart] 两千条词时，一帧连读多次也只扫一次', () async {
      await vocabRepo.save(_lib([
        for (var i = 0; i < 2000; i++)
          _item(
            lemma: 'word${i.toString().padLeft(4, '0')}',
            createdAt: '2026-11-01T00:00:00.000Z',
          ),
      ]));
      await vm.bootstrap();
      final before = vm.debugComputeCount;

      // 模拟浏览页一帧：标题条数、空态、列表长度、范围条数、日期、每篇条数。
      final count = vm.items.length;
      expect(count, 2000);
      expect(vm.items.isEmpty, isFalse);
      expect(vm.items, hasLength(2000));
      expect(vm.scopeCount, 2000);
      expect(vm.dayOptions, isNotEmpty);
      expect(vm.articleCounts, isEmpty);

      expect(vm.debugComputeCount, before + 1, reason: '不是六次');
    });
  });

  group('筛选条件持久化', () {
    test('没存过时是面板默认值：本篇 / 单词 / 复习', () async {
      final bare = VocabBrowseViewModel(
        vocab: vocabRepo,
        articles: articleRepo,
        prefsStore: PrefsStore.memory(),
      );
      addTearDown(bare.dispose);
      expect(bare.scope, BrowseScope.article);
      expect(bare.kind, BrowseKind.word);
      expect(bare.status, BrowseStatus.due);
      expect(bare.sort, BrowseSort.recent);
      expect(bare.includeMastered, isFalse);
    });

    test('改了条件就写盘，新建的 ViewModel 读得回来', () async {
      final store = PrefsStore.memory();
      final a = VocabBrowseViewModel(
        vocab: vocabRepo,
        articles: articleRepo,
        prefsStore: store,
      );
      addTearDown(a.dispose);
      a.setScope(BrowseScope.all);
      a.setKind(BrowseKind.lang);
      a.setStatus(BrowseStatus.lapsed);
      a.setSort(BrowseSort.alphabet);
      a.setIncludeMastered(true);
      a.setDays({'2026-11-01'});
      await Future<void>.delayed(Duration.zero);

      final b = VocabBrowseViewModel(
        vocab: vocabRepo,
        articles: articleRepo,
        prefsStore: store,
      );
      addTearDown(b.dispose);
      expect(b.scope, BrowseScope.all);
      expect(b.kind, BrowseKind.lang);
      expect(b.status, BrowseStatus.lapsed);
      expect(b.sort, BrowseSort.alphabet);
      expect(b.includeMastered, isTrue);
      expect(b.days, {'2026-11-01'});
    });

    test('存坏的偏好当没存过，不炸', () async {
      final vm2 = VocabBrowseViewModel(
        vocab: vocabRepo,
        articles: articleRepo,
        prefsStore: PrefsStore.memory(<String, String>{
          vocabBrowsePrefsKey: '{不是 json',
        }),
      );
      addTearDown(vm2.dispose);
      expect(vm2.scope, BrowseScope.article);
      expect(vm2.status, BrowseStatus.due);
    });

    test('重置回默认：本篇 / 单词 / 复习 / 不限日期', () async {
      vm.setScope(BrowseScope.all);
      vm.setKind(BrowseKind.all);
      vm.setStatus(BrowseStatus.all);
      vm.setDays({'2026-11-01'});
      vm.setScope(const VocabBrowsePrefs().scope);
      vm.setKind(const VocabBrowsePrefs().kind);
      vm.setStatus(const VocabBrowsePrefs().status);
      vm.setDays(const <String>{});
      expect(vm.scope, BrowseScope.article);
      expect(vm.kind, BrowseKind.word);
      expect(vm.status, BrowseStatus.due);
      expect(vm.days, isEmpty);
    });
  });
}
