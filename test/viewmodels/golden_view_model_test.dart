import 'package:dlaoshi_app/core/golden.dart';
import 'package:dlaoshi_app/core/golden_progress.dart';
import 'package:dlaoshi_app/core/golden_session.dart';
import 'package:dlaoshi_app/data/db/migrations.dart';
import 'package:dlaoshi_app/data/prefs_store.dart';
import 'package:dlaoshi_app/data/repositories/article_repository.dart';
import 'package:dlaoshi_app/data/repositories/learning_repository.dart';
import 'package:dlaoshi_app/services/article_import_service.dart';
import 'package:dlaoshi_app/viewmodels/golden_view_model.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

const String _body = 'We keep up with the news every morning. '
    'She came up with a plan in response to the complaint.';

/// 一份合法的「AI 挑句」回包：两句各一个学习点。
///
/// 句 id 必须用**文章里的真实 id**（`buildArticle` 生成 s001 / s002 这种），
/// 编造的 id 会被 `normalizeGoldenLesson` 整句丢掉；学习点也必须逐字出现在原句里。
String _aiLessonJson(String first, String second) => '{"summary":"讲习惯与反应",'
    '"sentences":['
    '{"id":"$first","zh":"我们每天早上都跟上新闻。","targets":['
    '{"en":"keep up with","kind":"collocation","zh":"跟上"}]},'
    '{"id":"$second","zh":"她针对投诉想出了一个方案。","targets":['
    '{"en":"came up with","kind":"collocation","zh":"想出"},'
    '{"en":"in response to","kind":"collocation","zh":"回应"}]}'
    '],"selected":["$first","$second"]}';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  late Database db;
  late ArticleRepository articles;
  late LearningRepository learningRepo;
  late PrefsStore store;
  late GoldenViewModel vm;
  late String articleId;

  /// 文章里两句的真实 id（`buildArticle` 生成 s001 / s002）。
  late String first;
  late String second;

  setUp(() async {
    db = await databaseFactory.openDatabase(inMemoryDatabasePath);
    await ensureSchema(db);
    articles = ArticleRepository(db);
    learningRepo = LearningRepository(db);
    store = PrefsStore.memory();
    vm = GoldenViewModel(
      articles: articles,
      learning: learningRepo,
      prefsStore: store,
    );
    final created =
        await ArticleImportService(articles).createFromText(raw: _body);
    articleId = created!.id;
    first = created.sentences[0].id;
    second = created.sentences[1].id;
  });

  tearDown(() async {
    vm.dispose();
    await db.close();
  });

  group('打开文章与本地课程', () {
    test('文章没有金句课时，按课文生成一份本地课程', () async {
      await vm.bootstrap();
      expect(vm.library, hasLength(1));

      await vm.openArticle(articleId);
      expect(vm.article, isNotNull);
      expect(vm.sentences, hasLength(2));
      expect(vm.lesson, isNotNull);
      expect(vm.lesson!.source, GoldenSource.local);
      expect(vm.editor.selectedIds, isNotEmpty);
      expect(vm.ordered, isNotEmpty);
      expect(vm.summary, isNotNull);
    });

    test('打开不存在的文章：不崩，课程为空', () async {
      await vm.openArticle('nope');
      expect(vm.article, isNull);
      expect(vm.lesson, isNull);
      expect(vm.ordered, isEmpty);
      expect(vm.summary, isNull);
    });

    test('候选句带分数，按得分从高到低', () async {
      await vm.openArticle(articleId);
      final candidates = vm.candidates;
      expect(candidates, isNotEmpty);
      for (var i = 1; i < candidates.length; i++) {
        expect(
          candidates[i - 1].score,
          greaterThanOrEqualTo(candidates[i].score),
        );
      }
    });

    test('关掉当前文章：回到选文章那一步', () async {
      await vm.openArticle(articleId);
      vm.closeArticle();
      expect(vm.article, isNull);
      expect(vm.ordered, isEmpty);
      expect(vm.session, emptyGoldenSession);
    });
  });

  group('改课程并写回文章', () {
    test('勾 / 取消一句会存进文章，按原文顺序排', () async {
      await vm.openArticle(articleId);
      await vm.editor.setSelected(<String>[second, first]);
      expect(vm.editor.selectedIds, <String>[second, first]);

      // 写回文章后重新打开，选择还在。
      final reloaded = GoldenViewModel(
        articles: articles,
        learning: learningRepo,
        prefsStore: store,
      );
      await reloaded.openArticle(articleId);
      expect(reloaded.editor.selectedIds, <String>[second, first]);
      reloaded.dispose();
    });

    test('取消最后一句会被拦下并给出提示', () async {
      await vm.openArticle(articleId);
      await vm.editor.toggleSentence(second);
      expect(vm.editor.selectedIds, <String>[first]);

      // 只剩一句时再取消：不许，给出提示。
      await vm.editor.toggleSentence(first);
      expect(vm.editor.selectedIds, <String>[first]);
      expect(vm.notice, isNotEmpty);
    });

    test('一键挑句：全部 / 推荐 / 手选', () async {
      await vm.openArticle(articleId);
      await vm.editor.setPick(GoldenPickMode.all);
      expect(vm.editor.selectedIds, hasLength(2));

      await vm.editor.setPick(GoldenPickMode.recommended);
      expect(vm.editor.selectedIds, isNotEmpty);

      await vm.editor.setPick(GoldenPickMode.manual);
      expect(vm.lesson!.options.pick, GoldenPickMode.manual);
    });

    test('去重开关只改 dedupe，其余设置不动', () async {
      await vm.openArticle(articleId);
      await vm.editor.setBlankUnit(GoldenBlankUnit.target);
      await vm.editor.setDedupe(true);
      expect(vm.lesson!.options.dedupe, isTrue);
      expect(vm.lesson!.options.blankUnit, GoldenBlankUnit.target);
    });

    test('加 / 删加练语言点', () async {
      await vm.openArticle(articleId);
      await vm.editor.addExtraPoint(first, 'in response to', zh: '回应');
      expect(vm.editor.extraPointsFor(first).single.en, 'in response to');

      // 同一句同英文只留一条（大小写不敏感）。
      await vm.editor.addExtraPoint(first, 'In Response To');
      expect(vm.editor.extraPointsFor(first), hasLength(1));

      await vm.editor.removeExtraPoint(first, 'in response to');
      expect(vm.editor.extraPointsFor(first), isEmpty);
    });

    test('空的语言点直接拒绝并提示', () async {
      await vm.openArticle(articleId);
      await vm.editor.addExtraPoint(first, '   ');
      expect(vm.editor.extraPointsFor(first), isEmpty);
      expect(vm.notice, isNotEmpty);
    });
  });

  group('AI 挑句', () {
    test('没打开文章时拼提示词会报错', () {
      expect(vm.buildPrompt(), isNull);
      expect(vm.error, isNotNull);
    });

    test('提示词里带上句 id 和原文', () async {
      await vm.openArticle(articleId);
      final prompt = vm.buildPrompt();
      expect(prompt, isNotNull);
      expect(prompt, contains('keep up with the news'));
      expect(prompt, contains('JSON'));
    });

    test('粘回 AI 结果：与本地课程合并，本地语言点不丢', () async {
      await vm.openArticle(articleId);
      final reason = await vm.applyAi(_aiLessonJson(first, second));
      expect(reason, isNull);
      // 本地有课程（按课文生成的那份）时会与 AI 合并，来源记成 merged。
      expect(vm.lesson!.source, GoldenSource.merged);
      expect(vm.lesson!.selected, <String>[first, second]);
      expect(vm.lesson!.sentences, hasLength(2));
      expect(
        vm.lesson!.sentences
            .firstWhere((s) => s.id == second)
            .targets
            .map((t) => t.en),
        containsAll(<String>['came up with', 'in response to']),
      );

      // 写回文章了：重新打开仍是合并版。
      final reloaded = GoldenViewModel(
        articles: articles,
        learning: learningRepo,
        prefsStore: store,
      );
      await reloaded.openArticle(articleId);
      expect(reloaded.lesson!.source, GoldenSource.merged);
      reloaded.dispose();
    });

    test('粘回垃圾 JSON：不覆盖现有课程', () async {
      await vm.openArticle(articleId);
      final before = vm.editor.selectedIds;
      final reason = await vm.applyAi('这不是 JSON');
      expect(reason, isNotNull);
      expect(vm.editor.selectedIds, before);
    });
  });

  group('练习进度', () {
    test('记一步就落库，重新打开还在', () async {
      await vm.openArticle(articleId);
      vm.recordStep(first, GoldenStep.fill, true);
      expect(vm.records, hasLength(1));

      // 等落库的 Future 走完。
      await Future<void>.delayed(const Duration(milliseconds: 50));
      final reloaded = GoldenViewModel(
        articles: articles,
        learning: learningRepo,
        prefsStore: store,
      );
      await reloaded.bootstrap();
      expect(reloaded.records, hasLength(1));
      expect(reloaded.records.single.sentenceId, first);
      expect(reloaded.records.single.fillFirst, isTrue);
      reloaded.dispose();
    });

    test('三步首次全对 + 小结才算掌握', () async {
      await vm.openArticle(articleId);
      vm.recordStep(first, GoldenStep.fill, true);
      expect(vm.masteredFor(first), isFalse);

      vm.recordStep(first, GoldenStep.assemble, true);
      vm.recordStep(first, GoldenStep.recall, true);
      expect(vm.masteredFor(first), isFalse);

      vm.recordStep(first, GoldenStep.summary, true);
      expect(vm.masteredFor(first), isTrue);

      final summary = vm.summary!;
      expect(summary.selectedSentences, vm.ordered.length);
      expect(summary.masteredSentences, greaterThanOrEqualTo(1));
    });

    test('没打开文章时记账被忽略', () {
      vm.recordStep(first, GoldenStep.fill, true);
      expect(vm.records, isEmpty);
    });
  });

  group('会话位置', () {
    test('换视图写进偏好，重新打开回到同一页', () async {
      await vm.openArticle(articleId);
      vm.goView('drill');
      expect(vm.session.view, 'drill');

      final reloaded = GoldenViewModel(
        articles: articles,
        learning: learningRepo,
        prefsStore: store,
      );
      await reloaded.openArticle(articleId);
      expect(reloaded.session.view, 'drill');
      reloaded.dispose();
    });

    test('不认识的视图名直接忽略', () async {
      await vm.openArticle(articleId);
      vm.goView('nope');
      expect(vm.session.view, emptyGoldenSession.view);
    });

    test('记第几句', () async {
      await vm.openArticle(articleId);
      vm.goIndex(1);
      expect(vm.session.index, 1);
      vm.goIndex(0, recall: true);
      expect(vm.session.recallIndex, 0);
    });
  });

  group('全库金句本', () {
    test('只收有金句课的文章', () async {
      await vm.bootstrap();
      await vm.loadBank();
      expect(vm.bank, isEmpty);

      // 生成 AI 课程后再摊平一次，就该有了。
      await vm.openArticle(articleId);
      await vm.applyAi(_aiLessonJson(first, second));
      await vm.loadBank();
      expect(vm.bank, isNotEmpty);
      expect(vm.bank.map((r) => r.articleId).toSet(), <String>{articleId});
    });
  });
}
