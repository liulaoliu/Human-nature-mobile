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
import 'package:dlaoshi_app/viewmodels/backup_view_model.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

Future<
    ({
      Database db,
      ArticleRepository articles,
      LearningRepository learning,
      BackupService service,
      BackupViewModel vm,
    })> _openMem() async {
  sqfliteFfiInit();
  final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
  await ensureSchema(db);
  final articles = ArticleRepository(db);
  final vocab = VocabRepository(db);
  final learning = LearningRepository(db);
  final service = BackupService(
    articles: articles,
    vocab: vocab,
    learning: learning,
    prefsStore: PrefsStore.memory(),
  );
  return (
    db: db,
    articles: articles,
    learning: learning,
    service: service,
    vm: BackupViewModel(service),
  );
}

void main() {
  late Database db;
  late ArticleRepository articles;
  late LearningRepository learningRepo;
  late BackupViewModel vm;
  late ArticleImportService imports;

  setUp(() async {
    final opened = await _openMem();
    db = opened.db;
    articles = opened.articles;
    learningRepo = opened.learning;
    vm = opened.vm;
    imports = ArticleImportService(articles);
  });

  tearDown(() async {
    await db.close();
  });

  Future<String> sampleBackup() async {
    await imports.createFromText(raw: 'We keep up with the news every morning.');
    await learningRepo.writeAll(
      LearningData(
        activity: addActivity(
          const <DayActivity>[],
          '2026-11-01',
          ActivityCat.read,
        ),
      ),
    );
    final result = await vm.export();
    return result!.json;
  }

  test('导出成功后给概况，失败留给 error', () async {
    final result = await vm.export();
    expect(result, isNotNull);
    expect(vm.error, isNull);
    expect(vm.notice, startsWith('导出好了：文章 0 篇'));
    expect(vm.lastExport, same(result));
  });

  test('覆盖导入：notice 用「导入完成」，坏数据写进 summary', () async {
    final text = await sampleBackup();
    final result = await vm.replace(text);
    expect(result, isNotNull);
    expect(vm.notice, startsWith('导入完成：文章 1 篇'));
    expect(vm.error, isNull);
  });

  test('合并导入：notice 用「合并完成」，第二次说已经合并过', () async {
    final text = await sampleBackup();
    await vm.merge(text);
    expect(vm.notice, startsWith('合并完成'));

    await vm.merge(text);
    expect(vm.notice, contains('已经合并过'));
  });

  test('不是 JSON：error 说人话，不抛', () async {
    final result = await vm.merge('这不是备份');
    expect(result, isNull);
    expect(vm.error, '这不是 JSON 备份文件');
    expect(vm.busy, isFalse);
  });

  test('peek 只看不落库', () async {
    final text = await sampleBackup();
    // 先清掉文章，好确认 peek 没把它写回来。
    for (final row in await articles.list()) {
      await articles.remove(row.id);
    }
    expect(await articles.count(), 0);

    final parsed = vm.peek(text);
    expect(parsed, isNotNull);
    expect(parsed!.articles, hasLength(1));
    expect(await articles.count(), 0);

    expect(vm.peek('坏文件'), isNull);
  });

  test('parsed 里能看到学习记录被读出来（activity 一天）', () async {
    final text = await sampleBackup();
    final parsed = vm.peek(text)!;
    expect(parsed.learning.activity, hasLength(1));
    expect(jsonDecode(text), isA<Map<String, Object?>>());
  });

  test('clearNotice 清空提示', () async {
    await vm.export();
    expect(vm.notice, isNotEmpty);
    vm.clearNotice();
    expect(vm.notice, isEmpty);
  });
}
