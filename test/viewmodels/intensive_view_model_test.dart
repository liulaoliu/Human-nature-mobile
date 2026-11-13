// 精读工作流 ViewModel：数据凑得对不对、通读勾选落不落盘、换篇回不回写全局。
import 'package:dlaoshi_app/core/intensive.dart';
import 'package:dlaoshi_app/data/db/migrations.dart';
import 'package:dlaoshi_app/data/prefs_store.dart';
import 'package:dlaoshi_app/data/repositories/article_repository.dart';
import 'package:dlaoshi_app/data/repositories/learning_repository.dart';
import 'package:dlaoshi_app/data/repositories/vocab_repository.dart';
import 'package:dlaoshi_app/models/vocab.dart';
import 'package:dlaoshi_app/services/article_import_service.dart';
import 'package:dlaoshi_app/viewmodels/current_article_view_model.dart';
import 'package:dlaoshi_app/viewmodels/intensive_view_model.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../support/vocab_fixture.dart';

Future<Database> _openMem() async {
  sqfliteFfiInit();
  final db = await databaseFactoryFfi.openDatabase(
    inMemoryDatabasePath,
    options: OpenDatabaseOptions(singleInstance: false),
  );
  await ensureSchema(db);
  return db;
}

void main() {
  late Database db;
  late ArticleRepository articles;
  late VocabRepository vocabRepo;
  late LearningRepository learningRepo;
  late PrefsStore store;
  late CurrentArticleViewModel current;
  late IntensiveViewModel vm;

  setUp(() async {
    db = await _openMem();
    articles = ArticleRepository(db);
    vocabRepo = VocabRepository(db);
    learningRepo = LearningRepository(db);
    store = PrefsStore.memory();
    current = CurrentArticleViewModel(articlesRepo: articles, prefsStore: store);
    vm = IntensiveViewModel(
      vocab: vocabRepo,
      learning: learningRepo,
      articles: articles,
      currentArticle: current,
    );
  });

  tearDown(() async {
    vm.dispose();
    current.dispose();
    await db.close();
  });

  /// 造一篇带两句正文的文章；词挂在这一篇上。
  Future<String> seedArticle({String title = 'Growth'}) async {
    final article = (await ArticleImportService(articles).createFromText(
      raw: 'Global growth slowed down. The outlook is uncertain.',
      title: title,
    ))!;
    await vocabRepo.save(
      VocabLibrary(
        items: [
          for (final w in const ['alpha', 'beta'])
            vocabItem(
              id: 'v-$w',
              word: w,
              meaning: '$w 的意思',
              status: VocabStatus.queried,
              source: VocabSource(articleId: article.id, fileName: title),
            ),
        ],
        articleEntries: [
          for (final w in const ['alpha', 'beta'])
            ArticleVocabEntry(
              articleId: article.id,
              lemma: w,
              origin: VocabOrigin.manual,
              addedAt: '2026-01-01T00:00:00.000Z',
            ),
        ],
      ),
    );
    return article.id;
  }

  group('bootstrap', () {
    test('没选文章：plan 是空的一份，七阶段全是待做', () async {
      await vm.bootstrap();
      expect(vm.hasArticle, isFalse);
      expect(vm.plan.stages, hasLength(7));
      expect(vm.plan.level, 0);
      expect(
        vm.plan.stages.every((s) => s.status == IntensiveStageStatus.todo),
        isTrue,
      );
    });

    test('选了文章：读到本篇，阶段按本篇的词算', () async {
      final id = await seedArticle();
      await current.bootstrap();
      await current.select(id);
      await vm.bootstrap();
      expect(vm.hasArticle, isTrue);
      expect(vm.title, 'Growth');
      // 两个词都有释义，vocab 阶段至少不是 0%。
      final vocab = vm.plan.stages.firstWhere(
        (s) => s.key == IntensiveStageKey.vocab,
      );
      expect(vocab.progress, greaterThan(0));
      expect(vm.plan.stages, hasLength(7));
    });

    test('句子翻译与语言点都空：comprehend 阶段 0%', () async {
      final id = await seedArticle();
      await current.bootstrap();
      await current.select(id);
      await vm.bootstrap();
      final comp = vm.plan.stages.firstWhere(
        (s) => s.key == IntensiveStageKey.comprehend,
      );
      expect(comp.progress, 0);
      expect(comp.status, IntensiveStageStatus.todo);
    });
  });

  group('通读勾选', () {
    test('勾上就落盘，换一个 ViewModel 读得回来', () async {
      final id = await seedArticle();
      await current.bootstrap();
      await current.select(id);
      await vm.bootstrap();
      expect(vm.skimmed, isFalse);

      await vm.toggleSkimmed();
      expect(vm.skimmed, isTrue);
      // skim 阶段从 todo 变成 done。
      final skim = vm.plan.stages.firstWhere(
        (s) => s.key == IntensiveStageKey.skim,
      );
      expect(skim.status, IntensiveStageStatus.done);

      final again = IntensiveViewModel(
        vocab: vocabRepo,
        learning: learningRepo,
        articles: articles,
        currentArticle: current,
      );
      await again.bootstrap();
      expect(again.skimmed, isTrue);
      again.dispose();

      // 再勾一次取消。
      await vm.toggleSkimmed();
      expect(vm.skimmed, isFalse);
      final data = await learningRepo.load();
      expect(data.skimmed, isEmpty);
    });

    test('没文章时勾不动（也不会写盘）', () async {
      await vm.bootstrap();
      await vm.toggleSkimmed();
      expect(vm.skimmed, isFalse);
      final data = await learningRepo.load();
      expect(data.skimmed, isEmpty);
    });
  });

  group('换篇', () {
    test('页内换篇不回写全局', () async {
      final a = await seedArticle(title: 'Growth');
      final b = await seedArticle(title: 'Inflation');
      await current.bootstrap();
      await current.select(a);
      await vm.bootstrap();
      expect(vm.title, 'Growth');

      await vm.openArticle(b);
      expect(vm.title, 'Inflation');
      expect(current.articleId, a, reason: '页内换篇只影响这一页');
    });

    test('传 null 就回到空态', () async {
      final a = await seedArticle();
      await current.bootstrap();
      await current.select(a);
      await vm.bootstrap();
      await vm.openArticle(null);
      expect(vm.hasArticle, isFalse);
      expect(vm.plan.level, 0);
    });
  });
}
