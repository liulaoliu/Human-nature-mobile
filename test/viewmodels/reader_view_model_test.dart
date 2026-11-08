import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:dlaoshi_app/core/reader_view.dart';
import 'package:dlaoshi_app/data/db/migrations.dart';
import 'package:dlaoshi_app/data/repositories/article_repository.dart';
import 'package:dlaoshi_app/data/repositories/vocab_repository.dart';
import 'package:dlaoshi_app/services/article_import_service.dart';
import 'package:dlaoshi_app/viewmodels/reader_view_model.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  late Database db;
  late ArticleRepository articles;
  late VocabRepository vocab;
  late ReaderViewModel vm;

  setUp(() async {
    db = await databaseFactory.openDatabase(inMemoryDatabasePath);
    await ensureSchema(db);
    articles = ArticleRepository(db);
    vocab = VocabRepository(db);
    vm = ReaderViewModel(
      articlesRepo: articles,
      vocabRepo: vocab,
      importsService: ArticleImportService(articles),
    );
  });

  tearDown(() async {
    vm.dispose();
    await db.close();
  });

  test('粘贴新建：空正文不建，正常正文直接打开', () async {
    expect(await vm.createFromPaste(raw: '   ', title: '空'), isNull);
    expect(vm.error, isNotNull);
    expect(await articles.count(), 0);

    final created = await vm.createFromPaste(
      raw: 'Global growth slowed down.\n\nThe outlook is uncertain.',
      title: 'Growth',
    );
    expect(created, isNotNull);
    expect(vm.current?.title, 'Growth');
    expect(vm.articles.length, 1);
  });

  test('标词：写进词库、本篇词表跟着长，重复标不新建', () async {
    await vm.createFromPaste(
      raw: 'Global growth slowed down. The outlook is uncertain.',
      title: 'Growth',
    );
    final article = vm.current!;
    final sentence = article.sentences.first;

    final first = await vm.markCurrentWord(
      'slowed',
      sentenceId: sentence.id,
      sentenceText: sentence.text,
    );
    expect(first, isNotNull);
    expect(vm.currentEntries.length, 1);
    expect(first!.lemma, 'slow');

    // 大小写 / 变形不新建：词库仍然只有一条。
    await vm.markCurrentWord('SLOW', sentenceId: sentence.id);
    expect(vm.library.items.length, 1);
    expect(vm.currentEntries.length, 1);
  });

  test('标词落盘：换一个新的 ViewModel 重新读库也能看到', () async {
    await vm.createFromPaste(raw: 'The outlook is uncertain.', title: 'Outlook');
    await vm.markCurrentWord('uncertain', sentenceId: 's001');

    final fresh = ReaderViewModel(
      articlesRepo: articles,
      vocabRepo: vocab,
      importsService: ArticleImportService(articles),
    );
    addTearDown(fresh.dispose);
    await fresh.bootstrap();
    expect(fresh.library.items.length, 1);
    expect(fresh.library.items.single.word, 'uncertain');
  });

  test('打开不存在的文章：不留当前文章，给错误提示', () async {
    await vm.openArticle('nope');
    expect(vm.current, isNull);
    expect(vm.error, isNotNull);
  });

  test('删文章：列表同步，当前文章被清掉', () async {
    final created = await vm.createFromPaste(
      raw: 'Global growth slowed down.',
      title: 'Growth',
    );
    await vm.removeArticle(created!.id);
    expect(vm.articles, isEmpty);
    expect(vm.current, isNull);
  });

  test('面板开关：判定由 core 出，不在这里拼布尔', () async {
    expect(vm.viewFlags.readingView, isTrue);
    vm.updateFlags(const ReaderViewFlagsInput(writingOpen: true));
    expect(vm.viewFlags.readingView, isFalse);
    expect(vm.viewFlags.examActive, isFalse);
  });
}
