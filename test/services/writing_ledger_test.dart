import 'package:dlaoshi_app/core/activity/activity.dart' show ActivityCat;
import 'package:dlaoshi_app/core/learning.dart' show LearningData;
import 'package:dlaoshi_app/core/writing.dart'
    show WritingFeedback, WritingRecord, WritingSource;
import 'package:dlaoshi_app/core/writing_record_json.dart'
    show writingRecordsFromJson;
import 'package:dlaoshi_app/data/db/migrations.dart' show ensureSchema;
import 'package:dlaoshi_app/data/repositories/learning_repository.dart';
import 'package:dlaoshi_app/services/writing_ledger.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// 只读一步就炸的仓储，用来验证失败回退。
class _ThrowingRepo extends LearningRepository {
  _ThrowingRepo(super.db);

  @override
  Future<LearningData> load() async => throw StateError('磁盘坏了');
}

WritingRecord _rec({
  String articleId = 'A',
  String text = 'I will follow up with the client.',
}) =>
    WritingRecord(
      at: '2026-11-10T09:00:00.000Z',
      articleId: articleId,
      text: text,
      feedback: const WritingFeedback(total: 80, max: 100, summary: '不错'),
      source: WritingSource.writing,
    );

void main() {
  late Database db;
  late LearningRepository repo;

  setUpAll(() => sqfliteFfiInit());

  setUp(() async {
    db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    await ensureSchema(db);
    repo = LearningRepository(db);
  });

  tearDown(() async => db.close());

  test('真追加：落一条历史，并给今天的「写」活动 +1', () async {
    final result = await appendWritingRecord(
      repo: repo,
      current: const <WritingRecord>[],
      record: _rec(),
      countActivity: true,
    );

    expect(result.ok, isTrue);
    expect(result.appended, isTrue);
    expect(result.error, isNull);
    expect(result.history, hasLength(1));

    final data = await repo.load();
    expect(writingRecordsFromJson(data.writingHistory), hasLength(1));
    expect(writingRecordsFromJson(data.writingHistory).single.text,
        'I will follow up with the client.');
    expect(data.activity, hasLength(1));
    expect(data.activity.single.countOf(ActivityCat.write), 1);
  });

  test('重复粘回同题同稿同文字：不刷历史，也不重复记账', () async {
    final first = await appendWritingRecord(
      repo: repo,
      current: const <WritingRecord>[],
      record: _rec(),
      countActivity: true,
    );
    expect(first.appended, isTrue);

    final again = await appendWritingRecord(
      repo: repo,
      current: first.history,
      record: _rec(), // 同一条：key 完全一致
      countActivity: true,
    );
    expect(again.ok, isTrue);
    expect(again.appended, isFalse);
    expect(again.history, hasLength(1));

    final data = await repo.load();
    expect(writingRecordsFromJson(data.writingHistory), hasLength(1));
    // 活动只 +1，不因为重复粘回变 2
    expect(data.activity.single.countOf(ActivityCat.write), 1);
  });

  test('countActivity: false —— 跳过稿 / 不该记账的记录仍落库，但不记活动', () async {
    final result = await appendWritingRecord(
      repo: repo,
      current: const <WritingRecord>[],
      record: _rec(),
      countActivity: false,
    );
    expect(result.ok, isTrue);
    expect(result.appended, isTrue);

    final data = await repo.load();
    expect(writingRecordsFromJson(data.writingHistory), hasLength(1));
    expect(data.activity, isEmpty);
  });

  test('repo 抛错：ok=false，error 带中文前缀，history 原样返回', () async {
    final broken = _ThrowingRepo(db);

    final current = <WritingRecord>[_rec(text: '已有的一条')];
    final before = current.length;
    final result = await appendWritingRecord(
      repo: broken,
      current: current,
      record: _rec(text: '新的一条'),
      countActivity: true,
    );

    expect(result.ok, isFalse);
    expect(result.appended, isFalse);
    expect(result.error, contains('记录存不进去：'));
    expect(result.history, same(current));
    expect(current.length, before); // 原列表没被就地改动
  });

  test('传入的 current 列表不被就地改写', () async {
    final current = <WritingRecord>[];
    await appendWritingRecord(
      repo: repo,
      current: current,
      record: _rec(),
      countActivity: true,
    );
    expect(current, isEmpty);
  });
}
