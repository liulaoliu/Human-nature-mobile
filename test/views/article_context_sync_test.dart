// 全局「当前文章」到各模块的推送：换篇要推、清空要清、连点两篇不能乱。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:dlaoshi_app/data/prefs_store.dart';
import 'package:dlaoshi_app/data/repositories/article_repository.dart';
import 'package:dlaoshi_app/data/repositories/learning_repository.dart';
import 'package:dlaoshi_app/data/repositories/vocab_repository.dart';
import 'package:dlaoshi_app/services/article_import_service.dart';
import 'package:dlaoshi_app/viewmodels/current_article_view_model.dart';
import 'package:dlaoshi_app/viewmodels/production_view_model.dart';
import 'package:dlaoshi_app/viewmodels/study_view_model.dart';
import 'package:dlaoshi_app/viewmodels/writing_view_model.dart';
import 'package:dlaoshi_app/views/article_context_sync.dart';
import 'smoke_harness.dart';

/// 一整套装配：和 main.dart 里跟「本篇」有关的几层一样。
class _Harness {
  _Harness(this.db)
      : articles = ArticleRepository(db),
        vocab = VocabRepository(db),
        learning = LearningRepository(db),
        prefs = PrefsStore.memory() {
    imports = ArticleImportService(articles);
    current = CurrentArticleViewModel(articlesRepo: articles, prefsStore: prefs);
    study = StudyViewModel(vocab: vocab, learning: learning, prefsStore: prefs);
    production =
        ProductionViewModel(vocab: vocab, learning: learning, prefsStore: prefs);
    writing = WritingViewModel(learning: learning, prefsStore: prefs);
  }

  final Database db;
  final ArticleRepository articles;
  final VocabRepository vocab;
  final LearningRepository learning;
  final PrefsStore prefs;
  late final ArticleImportService imports;
  late final CurrentArticleViewModel current;
  late final StudyViewModel study;
  late final ProductionViewModel production;
  late final WritingViewModel writing;

  Widget app() => MultiProvider(
        providers: [
          Provider<ArticleRepository>.value(value: articles),
          Provider<VocabRepository>.value(value: vocab),
          Provider<LearningRepository>.value(value: learning),
          Provider<PrefsStore>.value(value: prefs),
          ChangeNotifierProvider<CurrentArticleViewModel>.value(value: current),
          ChangeNotifierProvider<StudyViewModel>.value(value: study),
          ChangeNotifierProvider<ProductionViewModel>.value(value: production),
          ChangeNotifierProvider<WritingViewModel>.value(value: writing),
        ],
        child: const MaterialApp(
          home: ArticleContextSync(child: Text('首页')),
        ),
      );

  void dispose() {
    current.dispose();
    study.dispose();
    production.dispose();
    writing.dispose();
  }
}

/// 让帧后回调 + 真实 IO 都跑完。
Future<void> _settle(WidgetTester tester) async {
  await tester.pump();
  await tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 60)),
  );
  await tester.pump();
  await tester.pump();
}

void main() {
  setUpAll(smokeInitFfi);

  testWidgets('没选文章：三个模块的本篇都是空的', (tester) async {
    smokeUseTallScreen(tester);
    final db = await smokeOpenDb(tester);
    final h = _Harness(db);
    addTearDown(h.dispose);

    await tester.pumpWidget(h.app());
    await _settle(tester);

    // 背单词的「本篇」是 `String?`，没绑就是 null；
    // 产出训练与小课堂用 `'manual'` 当「没绑文章」的哨兵值（它们允许手工出题）。
    expect(h.study.articleId, isNull);
    expect(h.production.articleId, 'manual');
    expect(h.writing.articleId, 'manual');

    await smokeFinish(tester);
  });

  testWidgets('精读选了文章：背单词 / 产出训练 / 小课堂都拿到同一篇', (tester) async {
    smokeUseTallScreen(tester);
    final db = await smokeOpenDb(tester);
    final h = _Harness(db);
    addTearDown(h.dispose);

    late final String id;
    await tester.runAsync(() async {
      final created = await h.imports.createFromText(
        raw: 'We keep up with the news every morning.',
        title: 'News',
      );
      id = created!.id;
      await h.current.bootstrap();
    });

    await tester.pumpWidget(h.app());
    await _settle(tester);
    expect(h.study.articleId, isNull);

    await h.current.select(id);
    await _settle(tester);

    expect(h.study.articleId, id);
    expect(h.production.articleId, id);
    expect(h.writing.articleId, id);

    // 清空：三处一起回到「没绑」（产出训练与小课堂回落到 'manual' 哨兵值）。
    await h.current.select(null);
    await _settle(tester);
    expect(h.study.articleId, isNull);
    expect(h.production.articleId, 'manual');
    expect(h.writing.articleId, 'manual');

    await smokeFinish(tester);
  });

  testWidgets('连点两篇：最后落定的那一篇赢', (tester) async {
    smokeUseTallScreen(tester);
    final db = await smokeOpenDb(tester);
    final h = _Harness(db);
    addTearDown(h.dispose);

    late final String a;
    late final String b;
    await tester.runAsync(() async {
      a = (await h.imports.createFromText(raw: 'Alpha runs.', title: 'A'))!.id;
      b = (await h.imports.createFromText(raw: 'Beta walks.', title: 'B'))!.id;
      await h.current.bootstrap();
    });

    await tester.pumpWidget(h.app());
    await _settle(tester);

    // 不给第二次 IO 让路，模拟用户手速很快地连点两篇。
    await h.current.select(a);
    await h.current.select(b);
    await _settle(tester);

    expect(h.study.articleId, b);
    expect(h.production.articleId, b);
    expect(h.writing.articleId, b);

    await smokeFinish(tester);
  });
}
