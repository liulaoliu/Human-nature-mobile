/// 记录层的 JSON 还原：一条 / 一批、产出训练任务分流、坏数据跳过。
library;

import 'package:dlaoshi_app/core/production.dart';
import 'package:dlaoshi_app/core/production_task.dart';
import 'package:dlaoshi_app/core/writing.dart';
import 'package:dlaoshi_app/core/writing_record_json.dart';
import 'package:flutter_test/flutter_test.dart';

const ProductionTarget _target = ProductionTarget(
  id: 'v1|self|word',
  itemId: 'v1',
  kind: ProductionTargetKind.word,
  text: 'follow up',
  meaning: '跟进',
);

ProductionPrompt _prompt() => const ProductionPrompt(
      id: 'p1',
      zh: '跟同事说明进度',
      goal: '说明进度',
      targets: <ProductionTarget>[_target],
    );

Map<String, Object?> _writingRecordJson() => <String, Object?>{
      'at': '2026-11-01T10:00:00.000Z',
      'articleId': 'A',
      'articleTitle': 'A 文章',
      'model': 'I spent the morning cleaning up.',
      'text': 'I spent the afternoon cleaning up.',
      'feedback': const WritingFeedback(
        version: 2,
        total: 82,
        max: 100,
        summary: '不错',
      ).toJson(),
      'task': const ImitationTask(
        task: '写三句描述你的周末',
        model: 'I spent the whole morning cleaning up.',
        focus: 'clean up',
      ).toJson(),
      'source': 'writing',
      'sentenceId': 's1',
    };

void main() {
  group('writingRecordFromJson', () {
    test('往返：普通仿写记录逐字段读回，recordKey 自动补上', () {
      final rec = writingRecordFromJson(_writingRecordJson())!;
      expect(rec.at, '2026-11-01T10:00:00.000Z');
      expect(rec.articleId, 'A');
      expect(rec.articleTitle, 'A 文章');
      expect(rec.model, 'I spent the morning cleaning up.');
      expect(rec.text, 'I spent the afternoon cleaning up.');
      expect(rec.feedback.total, 82);
      expect(rec.feedback.summary, '不错');
      expect(rec.task, isA<ImitationTask>());
      expect(rec.task!.focus, 'clean up');
      expect(rec.source, WritingSource.writing);
      expect(rec.sentenceId, 's1');
      expect(rec.recordKey, isNotNull);
      expect(rec.recordKey, isNotEmpty);
    });

    test('产出训练记录读成 ProductionTask（不是普通 ImitationTask）', () {
      final task = makeProductionTask(_prompt(), '工作', sessionId: 's1');
      final rec = writingRecordFromJson(<String, Object?>{
        'at': '2026-11-02T10:00:00.000Z',
        'articleId': 'A',
        'text': 'I will follow up.',
        'feedback': const WritingFeedback(version: 2, total: 80, max: 100).toJson(),
        'task': task.toJson(),
        'source': 'production',
      })!;
      final back = rec.task;
      expect(back, isA<ProductionTask>());
      final prod = back as ProductionTask;
      expect(prod.mode, ProductionMode.skim);
      expect(prod.topic, '工作');
      expect(prod.goal, '说明进度');
      expect(prod.promptId, 'p1');
      expect(prod.sessionId, 's1');
      expect(prod.targets, hasLength(1));
      expect(prod.targets.first.text, 'follow up');
      expect(prod.hits, isEmpty);
      expect(productionTaskOfRecord(rec), same(prod));
    });

    test('跳过的产出训练稿：skipped 读得回来', () {
      final task = makeProductionTask(_prompt(), '工作')
          .copyWith(skipped: () => true);
      final rec = writingRecordFromJson(<String, Object?>{
        'at': '2026-11-02T10:00:00.000Z',
        'articleId': 'A',
        'text': '',
        'task': task.toJson(),
      })!;
      expect((rec.task as ProductionTask).skipped, isTrue);
    });

    test('缺 at / articleId 返回 null；空列表给空结果', () {
      expect(writingRecordFromJson(null), isNull);
      expect(writingRecordFromJson('x'), isNull);
      expect(writingRecordFromJson(<String, Object?>{'articleId': 'A'}), isNull);
      expect(writingRecordFromJson(<String, Object?>{'at': '2026-11-01'}), isNull);
      expect(writingRecordsFromJson(null), isEmpty);
      expect(writingRecordsFromJson('x'), isEmpty);
    });

    test('坏记录跳过、好记录留下', () {
      final out = writingRecordsFromJson(<Object?>[
        _writingRecordJson(),
        'not a map',
        <String, Object?>{'at': ''},
        _writingRecordJson(),
      ]);
      expect(out, hasLength(2));
    });

    test('task 认不出（缺 task 字段）时留 null，不抛错', () {
      final rec = writingRecordFromJson(<String, Object?>{
        'at': '2026-11-01T10:00:00.000Z',
        'articleId': 'A',
        'task': <String, Object?>{'model': 'x'},
      })!;
      expect(rec.task, isNull);
    });

    test('source 认不出当普通仿写，空字符串的 id 落 null', () {
      final rec = writingRecordFromJson(<String, Object?>{
        'at': '2026-11-01T10:00:00.000Z',
        'articleId': 'A',
        'source': 'no-such-source',
        'sentenceId': '',
        'examId': '',
      })!;
      expect(rec.source, isNull);
      expect(rec.sentenceId, isNull);
      expect(rec.examId, isNull);
    });

    test('已有 recordKey 时保留原值（不重算）', () {
      final rec = writingRecordFromJson(<String, Object?>{
        'at': '2026-11-01T10:00:00.000Z',
        'articleId': 'A',
        'text': 'x',
        'recordKey': 'stable-key',
      })!;
      expect(rec.recordKey, 'stable-key');
    });
  });

  group('writingRecordsToJson', () {
    test('一批记录 → JSON 列表，再读回来条数不变', () {
      final json = writingRecordsToJson(<WritingRecord>[
        writingRecordFromJson(_writingRecordJson())!,
      ]);
      expect(json, hasLength(1));
      expect(json.first['articleId'], 'A');
      expect(writingRecordsFromJson(json), hasLength(1));
    });
  });
}
