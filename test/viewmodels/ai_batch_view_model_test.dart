import 'package:dlaoshi_app/core/ai_config.dart';
import 'package:dlaoshi_app/data/db/migrations.dart';
import 'package:dlaoshi_app/data/prefs_store.dart';
import 'package:dlaoshi_app/data/repositories/article_repository.dart';
import 'package:dlaoshi_app/data/repositories/vocab_repository.dart';
import 'package:dlaoshi_app/models/vocab.dart';
import 'package:dlaoshi_app/services/ai_client.dart' show AiErrorKind, AiReply;
import 'package:dlaoshi_app/services/article_import_service.dart';
import 'package:dlaoshi_app/viewmodels/ai_batch_view_model.dart';
import 'package:dlaoshi_app/viewmodels/current_article_view_model.dart';
import 'package:flutter/foundation.dart' show VoidCallback;
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

const String _table = '''
run | /rʌn/ | v. | 跑步 | run out — 用完 | I run every day. — 我每天跑步。 | to move quickly
keep up | /kiːp ʌp/ | v. | 跟上 | keep up with — 跟上 | Keep up the work. — 继续加油。 | to go at the same speed
sharp | /ʃɑːp/ | adj. | 敏锐的 | sharp mind — 敏锐的头脑 | A sharp mind. — 敏锐的头脑。 | quick to notice
''';

/// 默认测试用的文章 id（`seed()` 把词都收进这一篇）。
const String _aid = 'a1';

VocabItem mkWord(String word) => VocabItem(
      id: 'item-$word',
      word: word,
      lemma: word.toLowerCase(),
      createdAt: '2026-11-10T00:00:00.000Z',
      updatedAt: '2026-11-10T00:00:00.000Z',
    );

ArticleVocabEntry entryOf(String articleId, VocabItem item) => ArticleVocabEntry(
      articleId: articleId,
      lemma: item.lemma,
      origin: VocabOrigin.manual,
      addedAt: '2026-11-10T00:00:00.000Z',
    );

Future<VocabRepository> openMem() async {
  sqfliteFfiInit();
  final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
  await ensureSchema(db);
  return VocabRepository(db);
}

/// 同一份内存库上的文章仓储与词库仓储（跑「跟随全局当前篇」那组要用）。
///
/// `singleInstance: false`：内存库默认按路径复用，上一组用例造的文章会漏过来。
Future<({ArticleRepository articles, VocabRepository vocab})> openBoth() async {
  sqfliteFfiInit();
  final db = await databaseFactoryFfi.openDatabase(
    inMemoryDatabasePath,
    options: OpenDatabaseOptions(singleInstance: false),
  );
  await ensureSchema(db);
  return (articles: ArticleRepository(db), vocab: VocabRepository(db));
}

/// 写一批词，并把它们都收进 [_aid] 这一篇 —— 跑批默认按篇，词必须挂在篇上。
Future<void> seed(VocabRepository repo, List<String> words, {String articleId = _aid}) {
  final items = <VocabItem>[for (final w in words) mkWord(w)];
  return repo.save(VocabLibrary(
    items: items,
    articleEntries: <ArticleVocabEntry>[
      for (final it in items) entryOf(articleId, it),
    ],
  ));
}

/// 造好 + bootstrap + 选中 [_aid] 这一篇（默认范围就是本篇）。
///
/// 不选篇的话 `articleId` 是 null，本篇章词集为空 → 一块任务都算不出来，
/// 这正是「选了本篇却没选篇」该有的行为，不是测试能跳过的前提。
Future<AiBatchViewModel> mkVm(
  VocabRepository repo,
  AiComplete complete, {
  PrefsStore? prefsStore,
  VoidCallback? onDispose,
  String articleId = _aid,
  bool selectArticle = true,
}) async {
  final vm = AiBatchViewModel(
    vocab: repo,
    complete: complete,
    prefsStore: prefsStore,
    onDispose: onDispose,
  );
  await vm.bootstrap();
  if (selectArticle) await vm.setArticle(articleId);
  return vm;
}

/// 给一组词造一份能过解析的查词表格（模型只该回本块请求的词）。
String tableFor(Iterable<String> words) => words
    .map((w) => '$w | /x/ | n. | 释义 | 用法 | 例句。 — 例句。 | def')
    .join('\n');

/// 记录每次调用的假客户端：按 prompt 顺序回放一组回复。
class FakeAi {
  FakeAi(this.replies);

  final List<AiReply> replies;
  final List<String> prompts = <String>[];
  int cursor = 0;

  Future<AiReply> call(AiConfig config, String prompt) async {
    prompts.add(prompt);
    if (cursor >= replies.length) {
      return const AiReply.fail('没有更多假回复了', AiErrorKind.empty);
    }
    return replies[cursor++];
  }
}

void main() {
  group('bootstrap / 设置', () {
    test('空词库：没有待办', () async {
      final repo = await openMem();
      final fake = FakeAi(<AiReply>[]);
      final vm = await mkVm(repo, fake.call);
      expect(vm.hasJobs, isFalse);
      expect(vm.progressText, '待办：0 块');
      expect(vm.config, defaultAiConfig);
      vm.dispose();
    });

    test('3 个缺释义的词 → 1 块任务；updateConfig 落本机且回显脱敏', () async {
      final repo = await openMem();
      await seed(repo, <String>['run', 'keep up', 'sharp']);
      final store = PrefsStore.memory();
      final fake = FakeAi(<AiReply>[AiReply.ok(_table)]);
      final vm = await mkVm(repo, fake.call, prefsStore: store);
      expect(vm.jobs, hasLength(1));
      expect(vm.progressText, contains('1/1 块'));
      expect(vm.articleId, _aid);

      const config = AiConfig(apiKey: 'sk-abcdefghijklmnop');
      await vm.updateConfig(config);
      expect(vm.config, config);
      expect(vm.config.maskedApiKey, 'sk-a****mnop');
      expect(store.loadAiConfig(), config);
      vm.dispose();
    });
  });

  group('只跑一篇', () {
    test('只算这一篇收过的词，别的篇的不算', () async {
      final repo = await openMem();
      final a = mkWord('run');
      final b = mkWord('sharp');
      await repo.save(VocabLibrary(
        items: <VocabItem>[a, b],
        articleEntries: <ArticleVocabEntry>[
          entryOf('a1', a),
          entryOf('a2', b),
        ],
      ));
      final fake = FakeAi(<AiReply>[]);
      final vm = await mkVm(repo, fake.call);

      final jobsOfA1 = vm.jobs.expand((j) => j.words).toSet();
      expect(jobsOfA1, <String>{'run'});

      await vm.setArticle('a2');
      expect(vm.jobs.expand((j) => j.words).toSet(), <String>{'sharp'});
      vm.dispose();
    });

    test('没有全库这条路：没选篇就不出任务', () async {
      final repo = await openMem();
      await seed(repo, <String>['run']);
      final fake = FakeAi(<AiReply>[]);
      final vm = await mkVm(repo, fake.call, selectArticle: false);
      expect(vm.articleId, isNull);
      expect(vm.jobs, isEmpty);
      vm.dispose();
    });

    test('本篇没有待查的词：提示「本篇没有待查的词」', () async {
      final repo = await openMem();
      // 只有 a2 有词，却选中 a1（a1 一篇都没收）→ 本篇无待办。
      final word = mkWord('run');
      await repo.save(VocabLibrary(
        items: <VocabItem>[word],
        articleEntries: <ArticleVocabEntry>[entryOf('a2', word)],
      ));
      final fake = FakeAi(<AiReply>[]);
      final vm = await mkVm(repo, fake.call, selectArticle: false);
      await vm.setArticle('a1');
      await vm.updateConfig(const AiConfig(apiKey: 'sk-x'));
      expect(vm.jobs, isEmpty);

      await vm.run();
      expect(vm.notice, contains('本篇没有待查的词'));
      expect(fake.prompts, isEmpty);
      vm.dispose();
    });
  });

  group('跑批：成功 / 失败 / 暂停 / 续跑', () {
    test('跑完一块：回复解析后回填词库，词都带上释义', () async {
      final repo = await openMem();
      await seed(repo, <String>['run', 'keep up', 'sharp']);
      final fake = FakeAi(<AiReply>[AiReply.ok(_table)]);
      final vm = await mkVm(repo, fake.call, prefsStore: PrefsStore.memory());
      await vm.updateConfig(const AiConfig(apiKey: 'sk-x'));
      await vm.run();

      expect(vm.phase, AiBatchPhase.done);
      expect(vm.outcome.doneCount, 1);
      expect(vm.outcome.failedCount, 0);
      expect(vm.allDone, isTrue);
      expect(fake.prompts, hasLength(1));
      expect(fake.prompts.single, contains('run'));

      final library = await repo.load();
      final byWord = <String, VocabItem>{
        for (final it in library!.items) it.word: it,
      };
      expect(byWord['run']?.meaning, '跑步');
      expect(byWord['keep up']?.meaning, '跟上');
      expect(byWord['sharp']?.meaning, '敏锐的');
      vm.dispose();
    });

    test('没填 key：直接拦下，不发请求，也不标成功', () async {
      final repo = await openMem();
      await seed(repo, <String>['run']);
      final fake = FakeAi(<AiReply>[AiReply.ok(_table)]);
      final vm = await mkVm(repo, fake.call);
      await vm.run();
      expect(vm.error, contains('还没填 API key'));
      expect(fake.prompts, isEmpty);
      expect(vm.outcome.doneCount, 0);
      vm.dispose();
    });

    test('401 失败：这块留待办，回复不落库；点继续可重试成功', () async {
      final repo = await openMem();
      await seed(repo, <String>['run', 'keep up', 'sharp']);
      final fake = FakeAi(<AiReply>[
        const AiReply.fail('key 不对', AiErrorKind.unauthorized),
        AiReply.ok(_table),
      ]);
      final vm = await mkVm(repo, fake.call, prefsStore: PrefsStore.memory());
      await vm.updateConfig(const AiConfig(apiKey: 'sk-x'));
      await vm.run();

      expect(vm.outcome.failedCount, 1);
      expect(vm.outcome.doneCount, 0);
      expect(vm.phase, AiBatchPhase.idle);
      expect(fake.prompts, hasLength(1));
      // 失败没改词库
      final before = await repo.load();
      expect(before!.items.where((it) => (it.meaning ?? '').isNotEmpty), isEmpty);

      await vm.resume();
      expect(vm.outcome.doneCount, 1);
      expect(vm.outcome.failedCount, 0);
      expect(fake.prompts, hasLength(2));
      final after = await repo.load();
      expect(after!.items.where((it) => (it.meaning ?? '').isNotEmpty),
          hasLength(3));
      vm.dispose();
    });

    test('模型回了空内容 / 解析不出表格：算失败，不落库', () async {
      final repo = await openMem();
      await seed(repo, <String>['run', 'keep up', 'sharp']);
      final fake = FakeAi(<AiReply>[AiReply.ok('抱歉，我不会')]);
      final vm = await mkVm(repo, fake.call, prefsStore: PrefsStore.memory());
      await vm.updateConfig(const AiConfig(apiKey: 'sk-x'));
      await vm.run();
      expect(vm.outcome.failedCount, 1);
      expect(vm.failedIds.values.single, contains('可解析'));
      vm.dispose();
    });

    test('暂停：当前块跑完就停，继续把剩下的跑完且不重跑已完成的块', () async {
      final repo = await openMem();
      // 31 个词 → 默认 chunk 30 切成 2 块，暂停才有中途可停的位置。
      final words = List<String>.generate(31, (i) => 'w$i');
      await seed(repo, words);
      late final AiBatchViewModel vm;
      var pausedOnce = false;
      Future<AiReply> complete(AiConfig config, String prompt) async {
        if (!pausedOnce) {
          pausedOnce = true;
          vm.pause(); // 第一块还在「请求中」时按暂停
        }
        // 模型回全部 31 个词：过滤只留本块请求的那些。
        return AiReply.ok(tableFor(words));
      }

      vm = await mkVm(repo, complete, prefsStore: PrefsStore.memory());
      expect(vm.jobs, hasLength(2));
      await vm.updateConfig(const AiConfig(apiKey: 'sk-x'));
      await vm.run();

      // 第一块照常落库，但停在 2 块中的第 1 块之后
      expect(vm.phase, AiBatchPhase.paused);
      expect(vm.outcome.doneCount, 1);
      expect(vm.progressText, contains('完成 1'));
      expect(vm.notice, contains('已暂停'));

      await vm.resume();
      expect(vm.phase, AiBatchPhase.done);
      expect(vm.outcome.doneCount, 2);
      // 继续时不会重跑第一块（2 块 × 各 1 次 = 2 次请求）
      expect(vm.outcome.failedCount, 0);
      vm.dispose();
    });

    test('skipFailed 清失败标记；clearNotice 清提示', () async {
      final repo = await openMem();
      await seed(repo, <String>['run']);
      final fake = FakeAi(<AiReply>[
        const AiReply.fail('限流', AiErrorKind.rateLimited),
      ]);
      final vm = await mkVm(repo, fake.call, prefsStore: PrefsStore.memory());
      await vm.updateConfig(const AiConfig(apiKey: 'sk-x'));
      await vm.run();
      expect(vm.outcome.failedCount, 1);
      vm.skipFailed();
      expect(vm.outcome.failedCount, 0);
      expect(vm.notice, contains('清掉失败标记'));
      vm.clearNotice();
      expect(vm.notice, isEmpty);
      expect(vm.error, isNull);
      vm.dispose();
    });
  });

  group('testConnection', () {
    test('走注入的回调，返回模型回复', () async {
      final repo = await openMem();
      final fake = FakeAi(<AiReply>[AiReply.ok('正常')]);
      final vm = await mkVm(repo, fake.call);
      final reply = await vm.testConnection();
      expect(reply.isOk, isTrue);
      expect(reply.text, '正常');
      expect(fake.prompts, hasLength(1));
      vm.dispose();
    });
  });

  group('守卫与状态重算', () {
    test('updateConfig 走 normalizeAiConfig：坏地址 / 越界温度被夹回', () async {
      final repo = await openMem();
      final vm = await mkVm(repo, FakeAi(<AiReply>[]).call);
      await vm.updateConfig(
        const AiConfig(
          baseUrl: 'ftp://evil.com///',
          apiKey: '  sk-x  ',
          temperature: 99,
        ),
      );
      expect(vm.config.baseUrl, defaultAiBaseUrl);
      expect(vm.config.apiKey, 'sk-x');
      expect(vm.config.temperature, maxAiTemperature);
      vm.dispose();
    });

    test('refresh 清空旧的完成 / 失败标记（词库变了，旧块对不上新块）', () async {
      final repo = await openMem();
      await seed(repo, <String>['run', 'keep up', 'sharp']);
      final fake = FakeAi(<AiReply>[AiReply.ok(_table)]);
      final vm = await mkVm(repo, fake.call, prefsStore: PrefsStore.memory());
      await vm.updateConfig(const AiConfig(apiKey: 'sk-x'));
      await vm.run();
      expect(vm.outcome.doneCount, 1);

      await seed(repo, <String>['run', 'keep up', 'sharp', 'bleak']);
      await vm.refresh();
      expect(vm.doneIds, isEmpty);
      expect(vm.failedIds, isEmpty);
      expect(vm.progressText, contains('完成 0'));
      expect(vm.jobs, hasLength(1));
      vm.dispose();
    });

    test('模型多回一个没请求的词：不落库，本块照常完成', () async {
      final repo = await openMem();
      await seed(repo, <String>['run', 'keep up', 'sharp']);
      const tableWithExtra = '''
run | /rʌn/ | v. | 跑步 | run out — 用完 | I run every day. — 我每天跑步。 | to move quickly
keep up | /kiːp ʌp/ | v. | 跟上 | keep up with — 跟上 | Keep up the work. — 继续加油。 | to go at the same speed
sharp | /ʃɑːp/ | adj. | 敏锐的 | sharp mind — 敏锐的头脑 | A sharp mind. — 敏锐的头脑。 | quick to notice
banana | /bəˈnɑːnə/ | n. | 香蕉 | 没有 | I ate a banana. — 我吃了香蕉。 | a long fruit
''';
      final fake = FakeAi(<AiReply>[AiReply.ok(tableWithExtra)]);
      final vm = await mkVm(repo, fake.call, prefsStore: PrefsStore.memory());
      await vm.updateConfig(const AiConfig(apiKey: 'sk-x'));
      await vm.run();

      expect(vm.outcome.doneCount, 1);
      expect(vm.notice, contains('不是请求的词'));
      final after = await repo.load();
      expect(after!.items.map((it) => it.word), isNot(contains('banana')));
      expect(
        after.items.where((it) => (it.meaning ?? '').isNotEmpty),
        hasLength(3),
      );
      vm.dispose();
    });

    test('模型只回没请求的词：算失败，词库零变化', () async {
      final repo = await openMem();
      await seed(repo, <String>['run', 'keep up']);
      const onlyExtra = '''
banana | /bəˈnɑːnə/ | n. | 香蕉 | 没有 | I ate a banana. — 我吃了香蕉。 | a long fruit
''';
      final fake = FakeAi(<AiReply>[AiReply.ok(onlyExtra)]);
      final vm = await mkVm(repo, fake.call, prefsStore: PrefsStore.memory());
      await vm.updateConfig(const AiConfig(apiKey: 'sk-x'));
      await vm.run();

      expect(vm.outcome.failedCount, 1);
      expect(vm.failedIds.values.single, contains('本块请求的词'));
      final after = await repo.load();
      expect(after!.items.where((it) => (it.meaning ?? '').isNotEmpty), isEmpty);
      vm.dispose();
    });

    test('全部跑完后再点继续：不再发请求', () async {
      final repo = await openMem();
      await seed(repo, <String>['run', 'keep up', 'sharp']);
      final fake = FakeAi(<AiReply>[AiReply.ok(_table)]);
      final vm = await mkVm(repo, fake.call, prefsStore: PrefsStore.memory());
      await vm.updateConfig(const AiConfig(apiKey: 'sk-x'));
      await vm.run();
      expect(vm.phase, AiBatchPhase.done);
      final sent = fake.prompts.length;

      await vm.resume();
      expect(vm.phase, AiBatchPhase.done);
      expect(fake.prompts, hasLength(sent));
      vm.dispose();
    });

    test('dispose 时回调上游释放（装配层借此 close http client）', () async {
      final repo = await openMem();
      var closed = 0;
      final vm = await mkVm(
        repo,
        FakeAi(<AiReply>[]).call,
        onDispose: () => closed++,
      );
      vm.dispose();
      expect(closed, 1);
    });
  });

  group('跟随全局当前篇', () {
    test('全局选了哪篇，跑批默认就跑那一篇', () async {
      final repos = await openBoth();
      final created = await ArticleImportService(repos.articles)
          .createFromText(raw: 'We keep up with the news every morning.');
      final aid = created!.id;
      final word = mkWord('run');
      await repos.vocab.save(VocabLibrary(
        items: <VocabItem>[word],
        articleEntries: <ArticleVocabEntry>[entryOf(aid, word)],
      ));

      final current =
          CurrentArticleViewModel(articlesRepo: repos.articles, prefsStore: PrefsStore.memory());
      await current.bootstrap();
      await current.select(aid);

      final vm = AiBatchViewModel(
        vocab: repos.vocab,
        complete: FakeAi(<AiReply>[]).call,
        articles: repos.articles,
        currentArticle: current,
        prefsStore: PrefsStore.memory(),
      );
      await vm.bootstrap();

      expect(vm.articleId, aid);
      expect(vm.jobs.expand((j) => j.words).toSet(), <String>{'run'});
      vm.dispose();
      current.dispose();
    });

    test('全局没选：本篇空着，不退回第一篇', () async {
      final repos = await openBoth();
      await ArticleImportService(repos.articles)
          .createFromText(raw: 'We keep up with the news every morning.');
      final word = mkWord('run');
      await repos.vocab.save(VocabLibrary(items: <VocabItem>[word]));

      final current =
          CurrentArticleViewModel(articlesRepo: repos.articles, prefsStore: PrefsStore.memory());
      await current.bootstrap();
      expect(current.articleId, isNull);

      final vm = AiBatchViewModel(
        vocab: repos.vocab,
        complete: FakeAi(<AiReply>[]).call,
        articles: repos.articles,
        currentArticle: current,
        prefsStore: PrefsStore.memory(),
      );
      await vm.bootstrap();

      expect(vm.articleList, hasLength(1));
      expect(vm.articleId, isNull);
      expect(vm.jobs, isEmpty);
      vm.dispose();
      current.dispose();
    });

    test('页内换篇不改全局', () async {
      final repos = await openBoth();
      final imports = ArticleImportService(repos.articles);
      final a = (await imports.createFromText(raw: 'First piece about growth.'))!;
      final b = (await imports.createFromText(raw: 'Second piece about inflation.'))!;

      final current =
          CurrentArticleViewModel(articlesRepo: repos.articles, prefsStore: PrefsStore.memory());
      await current.bootstrap();
      await current.select(a.id);

      final vm = AiBatchViewModel(
        vocab: repos.vocab,
        complete: FakeAi(<AiReply>[]).call,
        articles: repos.articles,
        currentArticle: current,
        prefsStore: PrefsStore.memory(),
      );
      await vm.bootstrap();
      expect(vm.articleId, a.id);

      await vm.setArticle(b.id);
      expect(vm.articleId, b.id);
      expect(current.articleId, a.id);
      vm.dispose();
      current.dispose();
    });
  });
}
