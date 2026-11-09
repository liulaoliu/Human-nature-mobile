import 'dart:convert';

import 'package:dlaoshi_app/core/activity/activity.dart';
import 'package:dlaoshi_app/core/learning.dart';
import 'package:dlaoshi_app/data/db/migrations.dart';
import 'package:dlaoshi_app/data/prefs_store.dart';
import 'package:dlaoshi_app/data/repositories/article_repository.dart';
import 'package:dlaoshi_app/data/repositories/learning_repository.dart';
import 'package:dlaoshi_app/data/repositories/vocab_repository.dart';
import 'package:dlaoshi_app/services/article_import_service.dart';
import 'package:dlaoshi_app/services/backup_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

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
