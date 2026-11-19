import 'dart:convert';

import 'package:dlaoshi_app/core/activity/activity.dart';
import 'package:dlaoshi_app/core/article_json.dart';
import 'package:dlaoshi_app/core/learning.dart';
import 'package:dlaoshi_app/data/db/migrations.dart';
import 'package:dlaoshi_app/data/prefs_store.dart';
import 'package:dlaoshi_app/data/repositories/article_repository.dart';
import 'package:dlaoshi_app/data/repositories/learning_repository.dart';
import 'package:dlaoshi_app/data/repositories/vocab_repository.dart';
import 'package:dlaoshi_app/models/document.dart';
import 'package:dlaoshi_app/models/vocab.dart';
import 'package:dlaoshi_app/services/article_import_service.dart';
import 'package:dlaoshi_app/services/backup_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../support/vocab_fixture.dart';

const String _bodyA = 'We keep up with the news every morning. '
    'She came up with a plan in response to the complaint.';
const String _bodyB = 'The committee set aside a budget for the repairs.';

/// 装一套内存库（三个仓储 + 内存偏好）。
Future<
    ({
      Database db,
      ArticleRepository articles,
      VocabRepository vocab,
      LearningRepository learning,
      PrefsStore store,
      BackupService service,
    })> _openMem() async {
  sqfliteFfiInit();
  final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
  await ensureSchema(db);
  final articles = ArticleRepository(db);
  final vocab = VocabRepository(db);
  final learning = LearningRepository(db);
  final store = PrefsStore.memory();
  return (
    db: db,
    articles: articles,
    vocab: vocab,
    learning: learning,
    store: store,
    service: BackupService(
      articles: articles,
      vocab: vocab,
      learning: learning,
      prefsStore: store,
    ),
  );
}

void main() {
  late Database db;
  late ArticleRepository articles;
  late VocabRepository vocab;
  late LearningRepository learningRepo;
  late PrefsStore store;
  late BackupService service;
  late ArticleImportService imports;

  setUp(() async {
    final opened = await _openMem();
    db = opened.db;
    articles = opened.articles;
    vocab = opened.vocab;
    learningRepo = opened.learning;
    store = opened.store;
    service = opened.service;
    imports = ArticleImportService(articles);
  });

  // 必须关：sqflite_common_ffi 对同一个 `:memory:` 路径会复用连接，
  // 不关的话上个用例的数据会漏进下一个。
  tearDown(() async {
    await db.close();
  });

  /// 造一份带学习记录的备份 JSON（只给一篇文章 + 一条读完记录）。
  Future<String> seedBackup() async {
    await imports.createFromText(raw: _bodyA);
    await learningRepo.writeAll(
      LearningData(
        activity: addActivity(
          const <DayActivity>[],
          '2026-11-01',
          ActivityCat.read,
        ),
      ),
    );
    final result = await service.exportAll(now: DateTime(2026, 11, 1, 9));
    return result.json;
  }

  group('导出', () {
    test('空库也能导出，概况与文件名对得上', () async {
      final result = await service.exportAll(now: DateTime(2026, 11, 1, 9));

      expect(result.articleCount, 0);
      expect(result.vocabCount, 0);
      expect(result.fileName, 'economist-backup-2026-11-01.json');
      expect(result.summary, '文章 0 篇 · 生词 0 个');

      final decoded = jsonDecode(result.json);
      expect(decoded, isA<Map<String, Object?>>());
      expect((decoded as Map)['version'], 1);
      expect(decoded['articles'], isEmpty);
    });

    test('文章与学习记录都进了备份，能被自己解析回来', () async {
      await imports.createFromText(raw: _bodyB);
      await learningRepo.writeAll(
        LearningData(
          activity: addActivity(
            const <DayActivity>[],
            '2026-11-01',
            ActivityCat.read,
            n: 3,
          ),
        ),
      );

      final result = await service.exportAll(now: DateTime(2026, 11, 1, 9));
      expect(result.articleCount, 1);

      final parsed = service.parse(result.json);
      expect(parsed.articles, hasLength(1));
      expect(parsed.articles.single.title, isNotEmpty);
      expect(parsed.learning.activity, hasLength(1));
      expect(parsed.learning.activity.single.countOf(ActivityCat.read), 3);
      expect(parsed.dropped, 0);
    });
  });

  group('解析守卫', () {
    test('不是 JSON 直接抛格式错，不吞', () {
      expect(() => service.parse('这不是 JSON'), throwsA(isA<FormatException>()));
    });

    test('坏条目只计数，不整份失败', () async {
      final payload = <String, Object?>{
        'version': 1,
        'articles': <Object?>[
          <String, Object?>{'id': 'x'}, // 结构不完整，丢掉
        ],
        'activity': <Object?>[
          <String, Object?>{'day': '2026-11-01', 'counts': <String, Object?>{'read': 2}},
          <String, Object?>{'nope': true}, // 坏行，丢掉
        ],
      };

      final parsed = service.parse(jsonEncode(payload));
      expect(parsed.articles, isEmpty);
      expect(parsed.learning.activity, hasLength(1));
      expect(parsed.dropped, greaterThanOrEqualTo(2));
    });
  });

  group('覆盖导入', () {
    test('整份替换：文章进来、学习记录换成备份里的那份', () async {
      final text = await seedBackup();
      await learningRepo.writeAll(
        LearningData(
          activity: addActivity(
            const <DayActivity>[],
            '2026-11-09',
            ActivityCat.write,
          ),
        ),
      );

      final result = await service.replace(text);
      expect(result.articleCount, 1);
      expect(result.skipped, isFalse);

      final reloaded = await learningRepo.load();
      expect(reloaded.activity, hasLength(1));
      expect(reloaded.activity.single.day, '2026-11-01');
      expect(reloaded.activity.single.countOf(ActivityCat.write), 0);
      expect(await articles.count(), 1);
    });

    test('备份里没有学习记录键时不清空现有统计', () async {
      await learningRepo.writeAll(
        LearningData(
          activity: addActivity(
            const <DayActivity>[],
            '2026-11-09',
            ActivityCat.write,
          ),
        ),
      );

      // 只带一篇文章，不带任何学习记录键。
      final onlyArticle = jsonEncode(<String, Object?>{
        'version': 1,
        'articles': <Object?>[
          jsonDecode(
            jsonEncode(
              <String, Object?>{
                'id': 'a9',
                'title': 'Only',
                'text': 'One sentence here.',
                'paragraphs': <Object?>[
                  <String, Object?>{
                    'id': 'p01',
                    'sentenceIds': <String>['s1'],
                  },
                ],
                'sentences': <Object?>[
                  <String, Object?>{
                    'id': 's1',
                    'paraId': 'p01',
                    'text': 'One sentence here.',
                  },
                ],
                'updatedAt': '2026-11-01T00:00:00.000Z',
              },
            ),
          ),
        ],
      });

      await service.replace(onlyArticle);

      final reloaded = await learningRepo.load();
      expect(reloaded.activity, hasLength(1));
      expect(reloaded.activity.single.countOf(ActivityCat.write), 1);
    });

    test('词库为空的备份不覆盖现有词库', () async {
      final text = await seedBackup();
      final result = await service.replace(text);
      expect(result.vocabCount, 0);
      // 空库导出本来就没有 library 键，覆盖导入不该把词库清掉（这里本来也空）。
      expect(await vocab.load(), isNull);
    });
  });

  group('合并导入', () {
    test('同一份文件第二次被跳过（按指纹记账）', () async {
      final text = await seedBackup();

      final first = await service.merge(text);
      expect(first.skipped, isFalse);
      expect(first.articleCount, 1);

      final second = await service.merge(text);
      expect(second.skipped, isTrue);
      expect(second.summary, '这份文件已经合并过了，没有重复导入');
    });

    test('账本落进偏好存储，换一个服务实例也认得这份文件', () async {
      final text = await seedBackup();
      await service.merge(text);

      final reopened = BackupService(
        articles: articles,
        vocab: vocab,
        learning: learningRepo,
        prefsStore: store,
      );
      expect((await reopened.merge(text)).skipped, isTrue);
    });

    test('学习记录按段累加：同一天同类活动相加', () async {
      final text = await seedBackup();
      await service.merge(text);

      // 合并是**按天累加**（与 Web 一致）：本机 1 次 + 备份 1 次 = 2 次。
      final afterFirst = await learningRepo.load();
      expect(afterFirst.activity.single.countOf(ActivityCat.read), 2);

      // 本机再记一次同一天同类的活动 → 3。
      await learningRepo.writeAll(
        LearningData(
          activity: addActivity(
            afterFirst.activity,
            '2026-11-01',
            ActivityCat.read,
          ),
        ),
      );

      // 造一份内容不同（指纹不同）但同样记了 11-01 的备份 → 再 +1 = 4。
      final otherText = jsonEncode(<String, Object?>{
        'version': 1,
        'activity': <Object?>[
          <String, Object?>{
            'day': '2026-11-01',
            'counts': <String, Object?>{'read': 1},
          },
        ],
      });
      final result = await service.merge(otherText);
      expect(result.skipped, isFalse);

      final merged = await learningRepo.load();
      expect(merged.activity, hasLength(1));
      expect(merged.activity.single.countOf(ActivityCat.read), 4);
    });

    test('文章重复合并不会变成两篇', () async {
      final text = await seedBackup();
      await service.merge(text);

      final otherText = await _variantOf(text);
      await service.merge(otherText);

      expect(await articles.count(), 1);
    });

    test('合并导入不会盖掉这期间在别处标的词（33.3）', () async {
      final text = await seedBackup();
      await service.merge(text);

      // 造一份**内容不同**（指纹不同）的备份，里面带一个词 `backupword`。
      final withWord = jsonEncode(<String, Object?>{
        'version': 1,
        'library': <String, Object?>{
          'schemaVersion': 1,
          'items': <Object?>[
            <String, Object?>{
              'id': 'item-backupword',
              'word': 'backupword',
              'lemma': 'backupword',
              'createdAt': '2026-11-01T00:00:00.000Z',
              'updatedAt': '2026-11-01T00:00:00.000Z',
            },
          ],
        },
      });

      // 解析这份备份的过程中，用户在背单词页标了一个词（另一版词库）。
      await vocab.save(VocabLibrary(
        items: <VocabItem>[
          vocabItem(id: 'item-marked', word: 'marked'),
        ],
      ));

      final result = await service.merge(withWord);
      expect(result.skipped, isFalse);

      final lib = await vocab.load();
      final words = <String>{for (final it in lib!.items) it.word};
      expect(words, contains('backupword'), reason: '备份里的词要并进来');
      expect(words, contains('marked'), reason: '这期间标进来的词不能被盖掉');
    });

    test('覆盖导入：整份替换，且是带锁按顺序落盘（33.3）', () async {
      // `seedBackup()` 造的那份不带词库（词库为空不覆盖是本组的既有承诺），
      // 所以这里单独造一份**带词库**的备份。
      await service.merge(jsonEncode(<String, Object?>{
        'version': 1,
        'library': <String, Object?>{
          'schemaVersion': 1,
          'items': <Object?>[
            <String, Object?>{
              'id': 'item-backupword',
              'word': 'backupword',
              'lemma': 'backupword',
              'createdAt': '2026-11-01T00:00:00.000Z',
              'updatedAt': '2026-11-01T00:00:00.000Z',
            },
          ],
        },
      }));
      final text = (await service.exportAll(now: DateTime(2026, 11, 2, 9))).json;

      // 本机再标一个词，然后覆盖导入：词库要被备份那份整份替换（这是语义，
      // 不是 bug），但必须真的落盘一版 —— 不能因为并发写就静默跳过。
      final before = await vocab.save(VocabLibrary(
        items: <VocabItem>[vocabItem(id: 'item-before', word: 'before')],
      ));

      final result = await service.replace(text);
      expect(result.vocabCount, 1);

      final after = await vocab.meta();
      expect(after!.at.compareTo(before.updatedAt), greaterThan(0),
          reason: '覆盖导入要真的落盘一版，不能静默跳过');
      final lib = await vocab.load();
      expect(<String>{for (final it in lib!.items) it.word}, <String>{'backupword'});
    });
  });

  group('合并导入：文章正文以较新那侧为准（33.6）', () {
    SavedArticle mkArticle({
      required String updatedAt,
      String? translation,
      Map<String, Object?>? golden,
    }) =>
        SavedArticle(
          id: 'a-33-6',
          title: '测试篇',
          text: 'We keep up with the news every morning.',
          updatedAt: updatedAt,
          paragraphs: const <Paragraph>[
            Paragraph(id: 'p01', sentenceIds: <String>['s1']),
          ],
          sentences: <Sentence>[
            Sentence(
              id: 's1',
              paraId: 'p01',
              text: 'We keep up with the news every morning.',
              translation: translation,
            ),
          ],
          golden: golden,
        );

    String backupWith(SavedArticle article) => jsonEncode(<String, Object?>{
          'version': 1,
          'articles': <Object?>[articleToJson(article)],
        });

    Map<String, Object?> lessonJson({List<String> extra = const <String>[]}) =>
        <String, Object?>{
          'source': 'local',
          'summary': '讲习惯',
          'sentences': <Object?>[
            <String, Object?>{
              'id': 's1',
              'zh': '我们每天早上都跟上新闻。',
              'targets': <Object?>[
                <String, Object?>{
                  'en': 'keep up with',
                  'kind': 'collocation',
                  'zh': '跟上',
                },
              ],
            },
          ],
          'selected': <Object?>['s1'],
          'extraPoints': <Object?>[
            for (final e in extra)
              <String, Object?>{
                'sentenceId': 's1',
                'en': e,
                'kind': 'collocation',
              },
          ],
        };

    test('本机这篇更新：合并后正文还是本机的', () async {
      final text = backupWith(mkArticle(updatedAt: '2026-11-01T00:00:00.000Z'));

      // 本机这篇在本机补了译文，时间比备份里那份晚。
      await articles.save(mkArticle(
        updatedAt: '2026-11-09T00:00:00.000Z',
        translation: '我们每天早上都跟上新闻。',
      ));

      final result = await service.merge(text);
      expect(result.skipped, isFalse);

      final kept = await articles.load('a-33-6');
      expect(kept!.updatedAt, '2026-11-09T00:00:00.000Z');
      expect(
        kept.sentences.single.translation,
        '我们每天早上都跟上新闻。',
        reason: '「合并」不是「还原」：本机改过的正文不能被旧备份盖回去',
      );
    });

    test('备份这篇更新：用备份那份', () async {
      final text = backupWith(mkArticle(
        updatedAt: '2026-11-09T00:00:00.000Z',
        translation: '备份里的译文',
      ));

      await articles.save(mkArticle(updatedAt: '2026-11-01T00:00:00.000Z'));

      await service.merge(text);

      final kept = await articles.load('a-33-6');
      expect(kept!.sentences.single.translation, '备份里的译文');
    });

    test('金句课不跟着正文走：两边「加入本课」仍取并集', () async {
      // 本机更新，但备份里多一条本机没有的语言点。
      await articles.save(mkArticle(
        updatedAt: '2026-11-09T00:00:00.000Z',
        translation: '本机的译文',
        golden: lessonJson(extra: <String>['in the news']),
      ));
      final text = backupWith(mkArticle(
        updatedAt: '2026-11-01T00:00:00.000Z',
        golden: lessonJson(extra: <String>['every morning']),
      ));

      await service.merge(text);

      final kept = await articles.load('a-33-6');
      final rawExtras =
          (kept!.golden ?? const <String, Object?>{})['extraPoints'];
      final extras = <String>[
        if (rawExtras is List)
          for (final p in rawExtras)
            if (p is Map) p['en'] as String,
      ]..sort();
      expect(extras, <String>['every morning', 'in the news'],
          reason: '正文保留本机的，但金句课两边取并集');
      expect(kept.sentences.single.translation, '本机的译文');
    });
  });

  group('导入结果文案', () {
    test('坏数据要报出来，不许静默', () {
      const result = BackupImportResult(
        articleCount: 2,
        vocabCount: 5,
        dropped: 3,
        errors: <String>['文章结构不完整'],
      );
      expect(result.summary, '文章 2 篇 · 生词 5 个 · 跳过 3 条坏数据');
    });
  });
}

/// 把备份 JSON 改一个字节，得到「不同指纹、同样内容」的第二份文件。
Future<String> _variantOf(String text) async {
  final map = jsonDecode(text) as Map<String, Object?>;
  map['exportedAt'] = '2026-11-02T00:00:00.000Z';
  return jsonEncode(map);
}
