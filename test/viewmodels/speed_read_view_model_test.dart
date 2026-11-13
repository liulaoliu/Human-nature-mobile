import 'package:dlaoshi_app/core/speed_read.dart';
import 'package:dlaoshi_app/data/db/migrations.dart';
import 'package:dlaoshi_app/data/prefs_store.dart';
import 'package:dlaoshi_app/data/repositories/article_repository.dart';
import 'package:dlaoshi_app/services/article_import_service.dart';
import 'package:dlaoshi_app/viewmodels/current_article_view_model.dart';
import 'package:dlaoshi_app/viewmodels/speed_read_view_model.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  late Database db;
  late ArticleRepository articles;
  late PrefsStore store;
  late CurrentArticleViewModel current;
  late SpeedReadViewModel vm;
  late DateTime clock;

  const String bodyA =
      'We keep up with the news every morning. It helps us stay sharp. '
      'Small habits compound over time.';

  setUp(() async {
    db = await databaseFactory.openDatabase(inMemoryDatabasePath);
    await ensureSchema(db);
    articles = ArticleRepository(db);
    store = PrefsStore.memory();
    clock = DateTime(2026, 11, 11, 9);
    current = CurrentArticleViewModel(articlesRepo: articles, prefsStore: store);
    vm = SpeedReadViewModel(
      articles: articles,
      prefsStore: store,
      now: () => clock,
      currentArticle: current,
    );
  });

  tearDown(() async {
    vm.dispose();
    current.dispose();
    await db.close();
  });

  Future<String> seedArticle([String body = bodyA]) async {
    final imports = ArticleImportService(articles);
    final saved = await imports.createFromText(raw: body);
    return saved!.id;
  }

  void pass(int ms) => clock = clock.add(Duration(milliseconds: ms));

  group('打开文章与游标', () {
    test('bootstrap 读到文章列表与本机偏好', () async {
      await seedArticle();
      await vm.bootstrap();
      expect(vm.library, hasLength(1));
      expect(vm.wpm, defaultWpm);
      expect(vm.autoDrill, isTrue);
      expect(vm.hasArticle, isFalse);
    });

    test('打开文章后有句子，游标从第一句开始', () async {
      final id = await seedArticle();
      await vm.bootstrap();
      await vm.openArticle(id);
      expect(vm.hasArticle, isTrue);
      expect(vm.sentences, hasLength(3));
      expect(vm.index, 0);
      expect(vm.phase, SpeedReadPhase.read);
      expect(vm.sentence, isNotNull);
    });

    test('打开不存在的文章给错误，不崩', () async {
      await vm.bootstrap();
      await vm.openArticle('nope');
      expect(vm.hasArticle, isFalse);
      expect(vm.error, isNotNull);
    });

    test('重开同一篇能续上上次的游标', () async {
      final id = await seedArticle();
      await vm.bootstrap();
      await vm.openArticle(id);
      vm.advance(); // read → reveal
      vm.advance(); // reveal → 下一句
      expect(vm.index, 1);
      final key = vm.articleKey;

      final second = SpeedReadViewModel(articles: articles, prefsStore: store, now: () => clock);
      addTearDown(second.dispose);
      await second.bootstrap();
      await second.openArticle(id);
      expect(second.articleKey, key);
      expect(second.index, 1);
    });

    test('正文改过之后游标作废，从头开始', () async {
      final id = await seedArticle();
      await vm.bootstrap();
      await vm.openArticle(id);
      vm.advance();
      vm.advance();
      expect(vm.index, 1);

      // 同一个 id 换了正文 → 签名变了 → 老游标不该被认
      final changed = SpeedReadViewModel(articles: articles, prefsStore: store, now: () => clock);
      addTearDown(changed.dispose);
      await changed.bootstrap();
      await changed.openArticle(id);
      final oldKey = changed.articleKey;
      expect(store.loadSpeedCursor('$id@stale'), 0);
      expect(oldKey, isNotEmpty);
    });
  });

  group('计时与阶段推进', () {
    test('读得太快不算超时，直接翻下一句', () async {
      final id = await seedArticle();
      await vm.bootstrap();
      await vm.openArticle(id);
      pass(500);
      vm.advance();
      expect(vm.phase, SpeedReadPhase.reveal);
      expect(vm.readMs, 500);
      expect(vm.slow, isFalse);
      vm.advance();
      expect(vm.index, 1);
      expect(vm.rows, hasLength(1));
      expect(vm.rows.first.ms, 500);
      expect(vm.rows.first.drillOk, isNull);
    });

    test('读超时会标 slow，并且开了自动拷打就直接进拷打', () async {
      final id = await seedArticle();
      await vm.bootstrap();
      await vm.openArticle(id);
      pass(vm.target + 1000);
      vm.advance();
      // 超时 → 直接进拷打，不再需要多点一次「拷打」。
      expect(vm.slow, isTrue);
      expect(vm.drill, isNotNull);
      expect(vm.phase, SpeedReadPhase.drill);
    });

    test('拷打阶段按「下一句」跳过，不记对错', () async {
      final id = await seedArticle();
      await vm.bootstrap();
      await vm.openArticle(id);
      pass(vm.target + 1000);
      vm.advance();
      expect(vm.phase, SpeedReadPhase.drill);
      // 不想被拷打：按「下一句」直接翻句，drillOk 记 null。
      vm.advance();
      expect(vm.index, 1);
      expect(vm.phase, SpeedReadPhase.read);
      expect(vm.rows, hasLength(1));
      expect(vm.rows.single.drillOk, isNull);
      expect(vm.rows.single.slow, isTrue);
    });

    test('关掉自动拷打后超时也只翻句', () async {
      final id = await seedArticle();
      await vm.bootstrap();
      await vm.setAutoDrill(false);
      await vm.openArticle(id);
      pass(vm.target + 1000);
      vm.advance();
      expect(vm.slow, isTrue);
      vm.advance();
      expect(vm.index, 1);
      expect(vm.phase, SpeedReadPhase.read);
    });

    test('拷打答对记 true，答错记 false', () async {
      final id = await seedArticle();
      await vm.bootstrap();
      await vm.openArticle(id);
      pass(vm.target + 1000);
      // 超时直接进拷打，不用先停在揭晓。
      vm.advance();
      expect(vm.phase, SpeedReadPhase.drill);
      final drill = vm.drill!;
      vm.chooseDrill(drill.answer);
      expect(vm.phase, SpeedReadPhase.drillAnswer);
      expect(vm.drillOk, isTrue);
      vm.advance();
      expect(vm.rows.single.drillOk, isTrue);

      // 第二句答错
      pass(vm.target + 1000);
      vm.advance();
      expect(vm.phase, SpeedReadPhase.drill);
      final wrong = vm.drill!.options.firstWhere((o) => o != vm.drill!.answer);
      vm.chooseDrill(wrong);
      expect(vm.drillOk, isFalse);
      vm.advance();
      expect(vm.rows.last.drillOk, isFalse);
    });

    test('读完最后一句后游标归零，下次从头开始', () async {
      final id = await seedArticle();
      await vm.bootstrap();
      await vm.openArticle(id);
      for (var i = 0; i < vm.total; i++) {
        pass(100);
        vm.advance();
        vm.advance();
      }
      expect(vm.sentence, isNull);
      final key = vm.articleKey;
      expect(store.loadSpeedCursor(key), 0);
    });
  });

  group('翻句 / 重来 / 设置', () {
    test('前后翻句不记成绩', () async {
      final id = await seedArticle();
      await vm.bootstrap();
      await vm.openArticle(id);
      vm.go(1);
      expect(vm.index, 1);
      expect(vm.rows, isEmpty);
      vm.go(-1);
      expect(vm.index, 0);
      vm.go(-1); // 已经第一句，不动
      expect(vm.index, 0);
    });

    test('翻句会清掉上一句的拷打状态', () async {
      final id = await seedArticle();
      await vm.bootstrap();
      await vm.openArticle(id);
      pass(vm.target + 1000);
      vm.advance();
      expect(vm.phase, SpeedReadPhase.drill);
      vm.go(1);
      expect(vm.phase, SpeedReadPhase.read);
      expect(vm.drill, isNull);
      expect(vm.slow, isFalse);
    });

    test('重来把成绩清空、回到第一句', () async {
      final id = await seedArticle();
      await vm.bootstrap();
      await vm.openArticle(id);
      vm.advance();
      vm.advance();
      expect(vm.rows, hasLength(1));
      vm.restart();
      expect(vm.index, 0);
      expect(vm.rows, isEmpty);
      expect(vm.phase, SpeedReadPhase.read);
    });

    test('调语速夹进范围并存本机', () async {
      await vm.setWpm(180);
      expect(vm.wpm, 180);
      expect(store.loadSpeedWpm(), 180);
      await vm.setWpm(9999);
      expect(vm.wpm, maxWpm);
      expect(store.loadSpeedWpm(), maxWpm);
    });

    test('调自动拷打开关存本机', () async {
      await vm.setAutoDrill(false);
      expect(vm.autoDrill, isFalse);
      expect(store.loadSpeedAutoDrill(), isFalse);
      await vm.setAutoDrill(true);
      expect(store.loadSpeedAutoDrill(), isTrue);
    });

    test('tick 只在读的阶段通知', () async {
      final id = await seedArticle();
      await vm.bootstrap();
      await vm.openArticle(id);
      var notified = 0;
      vm.addListener(() => notified++);
      vm.tick();
      expect(notified, 1);
      vm.advance(); // → reveal
      vm.tick();
      expect(notified, 2); // advance 自己通知一次，tick 没通知
    });
  });

  group('跟随全局当前篇', () {
    test('全局选了哪篇，进速读就落在那一篇', () async {
      final first = await seedArticle(bodyA);
      final second = await seedArticle(
        'Global growth slowed in the third quarter. '
        'Household spending held up better than expected.',
      );
      expect(first, isNot(second));
      await current.bootstrap();
      await current.select(second);

      await vm.bootstrap();
      expect(vm.hasArticle, isTrue);
      expect(vm.article!.id, second);
    });

    test('全局没选：bootstrap 不自动打开任何一篇', () async {
      await seedArticle();
      await current.bootstrap();
      expect(current.articleId, isNull);

      await vm.bootstrap();
      expect(vm.hasArticle, isFalse);
    });

    test('页内换篇不改全局，再来一篇也不回落到第一篇', () async {
      final first = await seedArticle(bodyA);
      await seedArticle(
        'Global growth slowed in the third quarter. '
        'Household spending held up better than expected.',
      );
      await current.bootstrap();
      await current.select(first);

      await vm.bootstrap();
      expect(vm.article!.id, first);

      // 页内「换一篇」→ 回列表；全局那篇不动。
      await vm.openArticle(null);
      expect(vm.hasArticle, isFalse);
      expect(current.articleId, first);
    });
  });
}
