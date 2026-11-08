import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:dlaoshi_app/core/analyzer_shared.dart' show AnalysisTask;
import 'package:dlaoshi_app/core/language.dart' show getSentenceLanguages;
import 'package:dlaoshi_app/core/reader_view.dart';
import 'package:dlaoshi_app/core/vocab/analysis.dart' show WordAnalysis, applyWordAnalysis;
import 'package:dlaoshi_app/data/db/migrations.dart';
import 'package:dlaoshi_app/data/repositories/article_repository.dart';
import 'package:dlaoshi_app/data/repositories/vocab_repository.dart';
import 'package:dlaoshi_app/models/document.dart'
    show LanguageSource, SentenceLanguage;
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

  group('AI 结果落库', () {
    test('翻译 / 结构 / 搭配落到句子上并落盘', () async {
      await vm.createFromPaste(raw: 'He runs fast.', title: 'Run');
      final sentence = vm.current!.sentences.first;

      final t = await vm.applySentenceAnalysis(
        sentenceId: sentence.id,
        task: AnalysisTask.translate,
        raw: '他跑得快。',
      );
      expect(t, isNotNull);
      expect(t!.translation, '他跑得快。');
      expect(vm.current!.sentences.first.translation, '他跑得快。');

      await vm.applySentenceAnalysis(
        sentenceId: sentence.id,
        task: AnalysisTask.grammar,
        raw: '主谓状',
      );
      expect(vm.current!.sentences.first.grammarNote, '主谓状');

      await vm.applySentenceAnalysis(
        sentenceId: sentence.id,
        task: AnalysisTask.collocations,
        raw: 'run fast\nrun away',
      );
      expect(vm.current!.sentences.first.collocations, ['run fast', 'run away']);

      // 换一个新 ViewModel 重新读库 —— 说明真的写进 articles 表了。
      final fresh = ReaderViewModel(
        articlesRepo: articles,
        vocabRepo: vocab,
        importsService: ArticleImportService(articles),
      );
      addTearDown(fresh.dispose);
      await fresh.openArticle(vm.current!.id);
      final reloaded = fresh.current!.sentences.first;
      expect(reloaded.translation, '他跑得快。');
      expect(reloaded.grammarNote, '主谓状');
      expect(reloaded.collocations, ['run fast', 'run away']);
    });

    test('空文本 / 不存在的句子给错误，不动文章', () async {
      await vm.createFromPaste(raw: 'He runs fast.', title: 'Run');
      final before = vm.current!.sentences.first;

      expect(
        await vm.applySentenceAnalysis(
          sentenceId: before.id,
          task: AnalysisTask.translate,
          raw: '   ',
        ),
        isNull,
      );
      expect(vm.error, isNotNull);

      expect(
        await vm.applySentenceAnalysis(
          sentenceId: 'nope',
          task: AnalysisTask.translate,
          raw: '随便',
        ),
        isNull,
      );
    });

    test('查词结果写回词库：释义 / 音标 / 词性都进去', () async {
      await vm.createFromPaste(raw: 'He runs fast.', title: 'Run');
      await vm.markCurrentWord('runs', sentenceId: 's001', sentenceText: 'He runs fast.');

      final saved = await vm.applyLibraryTransform(
        (lib) => applyWordAnalysis(lib, const [
          WordAnalysis(
            word: 'run',
            phonetic: '/rʌn/',
            partOfSpeech: 'v.',
            meaning: '跑',
          ),
        ]),
      );
      expect(saved, isNotNull);
      final item = saved!.items.single;
      expect(item.phonetic, '/rʌn/');
      expect(item.partOfSpeech, 'v.');
      expect(item.meaning, '跑');
      expect(vm.library.items.single.meaning, '跑');
    });
  });

  group('语言点 AI 结果', () {
    const rawJson = '{"sentences":[{"id":"s001",'
        '"structure":"主句 + 状语","grammar":"一般现在时",'
        '"idioms":["take its toll — 造成损害"],'
        '"phrases":["slow down — 放缓"],"usage":["growth 不可数"]}]}';

    test('落到句子上并落盘，换新 ViewModel 还能读到', () async {
      await vm.createFromPaste(raw: 'Global growth slowed down.', title: 'Growth');
      final id = vm.current!.sentences.first.id;

      final n = await vm.applyLanguageText(rawJson);
      expect(n, 1);
      final langs = getSentenceLanguages(vm.current!.sentences.first);
      expect(langs.single.structure, '主句 + 状语');
      expect(langs.single.grammar, '一般现在时');
      expect(langs.single.phrases, ['slow down — 放缓']);

      final fresh = ReaderViewModel(
        articlesRepo: articles,
        vocabRepo: vocab,
        importsService: ArticleImportService(articles),
      );
      addTearDown(fresh.dispose);
      await fresh.openArticle(vm.current!.id);
      expect(getSentenceLanguages(fresh.current!.sentences.first).single.idioms,
          ['take its toll — 造成损害']);
      expect(id, isNotEmpty);
    });

    test('粘错了：认不出句子就给错误，不动文章', () async {
      await vm.createFromPaste(raw: 'He runs fast.', title: 'Run');
      final before = vm.current!.sentences.first;

      expect(await vm.applyLanguageText('这不是 JSON'), 0);
      expect(vm.error, isNotNull);
      expect(getSentenceLanguages(vm.current!.sentences.first), isEmpty);
      expect(vm.current!.sentences.first.text, before.text);
    });

    test('手动加的语言点不会被 AI 覆盖掉', () async {
      await vm.createFromPaste(raw: 'He runs fast.', title: 'Run');
      final id = vm.current!.sentences.first.id;
      final manual = SentenceLanguage(
        structure: '手写的结构',
        source: LanguageSource.manual,
      );
      final article = vm.current!;
      await articles.save(article.copyWith(
        sentences: [
          article.sentences.first.copyWith(languages: () => [manual]),
        ],
      ));
      await vm.openArticle(article.id);

      final n = await vm.applyLanguageText(
        '{"sentences":[{"id":"$id","structure":"AI 写的"}]}',
      );
      expect(n, 1);
      final langs = getSentenceLanguages(vm.current!.sentences.first);
      expect(langs.map((l) => l.structure), ['AI 写的', '手写的结构']);
    });
  });
}
