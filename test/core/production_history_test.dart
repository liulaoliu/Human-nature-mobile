/// `core/production_history.dart` 的测试：进度派生、统计、提醒数、历史筛选与分组。
///
/// 用例对齐 Web 版 `src/core/productionHistory.test.ts`（246 行）。
library;

import 'package:dlaoshi_app/core/production.dart';
import 'package:dlaoshi_app/core/production_history.dart';
import 'package:dlaoshi_app/core/production_task.dart';
import 'package:dlaoshi_app/core/writing.dart';
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

/// 一条产出记录；`hits` 默认是「用上了」，`round` 默认 1。
WritingRecord _record({
  String at = '2026-11-01T10:00:00.000Z',
  String text = 'I will follow up.',
  List<ProductionTargetHit>? hits,
  int round = 1,
  bool skipped = false,
  WritingFeedback? feedback,
  String? sessionId = 's1',
  ProductionMode mode = ProductionMode.full,
  String topic = '工作',
}) {
  final task = makeProductionTask(
    _prompt(),
    topic,
    mode: mode,
    sessionId: sessionId,
  ).copyWith(
    round: () => round,
    skipped: () => skipped ? true : null,
    hits: hits ??
        const <ProductionTargetHit>[
          ProductionTargetHit(
            id: 'v1|self|word',
            kind: ProductionTargetKind.word,
            text: 'follow up',
            meaning: '跟进',
            used: true,
          ),
        ],
  );
  return WritingRecord(
    at: at,
    articleId: 'A',
    articleTitle: 'A',
    model: task.model,
    text: text,
    feedback: feedback ??
        const WritingFeedback(
          version: 2,
          total: 80,
          max: 100,
        ),
    task: task,
    source: WritingSource.production,
  );
}

ProductionTargetHit _missHit() => const ProductionTargetHit(
      id: 'v1|self|word',
      kind: ProductionTargetKind.word,
      text: 'follow up',
      meaning: '跟进',
      used: false,
    );

ProductionProgress _progress({
  String key = 'word:run',
  String text = 'run',
  String meaning = '跑',
  int attempts = 2,
  int hits = 0,
  int misses = 2,
  int streak = 0,
  String dueAt = '2026-11-01T00:00:00.000Z',
  String lastAt = '2026-11-01T00:00:00.000Z',
  String? updatedAt,
  ProductionTargetKind kind = ProductionTargetKind.word,
}) =>
    ProductionProgress(
      key: key,
      kind: kind,
      text: text,
      meaning: meaning,
      attempts: attempts,
      hits: hits,
      misses: misses,
      streak: streak,
      lastAt: lastAt,
      dueAt: dueAt,
      updatedAt: updatedAt,
    );

void main() {
  group('deriveProductionProgress', () {
    test('命中升一档，漏用立刻到期；记录本身不被修改', () {
      final hit = _record();
      final miss = _record(
        at: '2026-11-02T10:00:00.000Z',
        round: 2,
        hits: <ProductionTargetHit>[_missHit()],
      );
      final list = <WritingRecord>[hit, miss];
      final before = list.map((r) => '${r.at}|${r.text}').join(',');

      final progress = deriveProductionProgress(list);

      expect(list.map((r) => '${r.at}|${r.text}').join(','), before);
      expect(progress, hasLength(1));
      expect(progress.first.text, 'follow up');
      expect(progress.first.attempts, 2);
      expect(progress.first.hits, 1);
      expect(progress.first.misses, 1);
      expect(progress.first.streak, 0);
      // 漏用 → 立刻到期，就是那一次的时间
      expect(progress.first.dueAt, '2026-11-02T10:00:00.000Z');
    });

    test('连续命中按 1/3/7/14/30… 天推到期', () {
      final first = _record(at: '2026-11-01T10:00:00.000Z');
      final second = _record(at: '2026-11-02T10:00:00.000Z', round: 2);
      final progress = deriveProductionProgress(<WritingRecord>[first, second]);
      expect(progress.first.streak, 2);
      expect(progress.first.hits, 2);
      // 第二档间隔 3 天
      expect(progress.first.dueAt, '2026-11-05T10:00:00.000Z');
    });

    test('没有 hits 的记录不产生进度（老数据不猜）', () {
      final rec = _record(hits: const <ProductionTargetHit>[]);
      expect(deriveProductionProgress(<WritingRecord>[rec]), isEmpty);
    });

    test('applyProductionProgressRecords 是增量叠加', () {
      final base = deriveProductionProgress(<WritingRecord>[
        _record(at: '2026-11-01T10:00:00.000Z'),
      ]);
      final out = applyProductionProgressRecords(
        base,
        <WritingRecord>[_record(at: '2026-11-03T10:00:00.000Z', round: 2)],
      );
      expect(out, hasLength(1));
      expect(out.first.attempts, 2);
      expect(out.first.streak, 2);
    });
  });

  group('productionStats / filterProductionHistory / groupProductionAttempts', () {
    test('统计次数 / 重写 / 命中率 / 平均分', () {
      final a = _record();
      final b = _record(
        at: '2026-11-02T10:00:00.000Z',
        text: 'I will follow up tomorrow.',
        round: 2,
      );
      final stats = productionStats(<WritingRecord>[a, b]);
      expect(stats.attempts, 2);
      expect(stats.sessions, 1);
      expect(stats.rewrites, 1);
      expect(stats.targetHits, 2);
      expect(stats.targetAttempts, 2);
      expect(stats.targetMisses, 0);
      expect(stats.hitRate, 1);
      expect(stats.avgScore, 80);
      expect(stats.modes['full'], 2);
    });

    test('筛选按文章、模式、主题', () {
      final list = <WritingRecord>[_record(), _record(at: '2026-11-02T10:00:00.000Z')];
      expect(
        filterProductionHistory(
          list,
          const ProductionHistoryFilter(
            articleId: 'A',
            mode: ProductionMode.full,
            topic: '工作',
          ),
        ),
        hasLength(2),
      );
      expect(
        filterProductionHistory(
          list,
          const ProductionHistoryFilter(mode: ProductionMode.yogurt),
        ),
        isEmpty,
      );
      expect(
        filterProductionHistory(
          list,
          const ProductionHistoryFilter(topic: '跟同事'),
        ),
        hasLength(2),
      );
      expect(productionRecords(list), hasLength(2));
      expect(groupProductionAttempts(list).first.records, hasLength(2));
      expect(productionHistoryMarkdown(list), contains('跟同事说明进度'));
    });

    test('分组把第 1 稿排在前面，最新的一组在最上面', () {
      final list = <WritingRecord>[
        _record(at: '2026-11-02T10:00:00.000Z', round: 2),
        _record(at: '2026-11-01T10:00:00.000Z', round: 1),
      ];
      final groups = groupProductionAttempts(list);
      expect(groups, hasLength(1));
      expect(groups.first.sessionId, 's1');
      expect(groups.first.records.first.at, '2026-11-01T10:00:00.000Z');
      expect(groups.first.records.last.at, '2026-11-02T10:00:00.000Z');
    });
  });

  group('productionReviewCounts', () {
    test('到期按 dueAt，薄弱按漏用 / 命中率', () {
      final counts = productionReviewCounts(
        <ProductionProgress>[
          _progress(),
          _progress(
            key: 'word:curb',
            text: 'curb',
            meaning: '抑制',
            attempts: 2,
            hits: 2,
            misses: 0,
            streak: 2,
            dueAt: '2027-01-01T00:00:00.000Z',
          ),
        ],
        '2026-11-05T00:00:00.000Z',
      );
      expect(counts.due, 1);
      expect(counts.weak, 1);
      expect(counts.newTargets, 0);
    });

    test('传候选时算还没练过的目标块', () {
      final counts = productionReviewCounts(
        <ProductionProgress>[
          _progress(
            key: 'word:run',
            text: 'run',
            meaning: '跑',
            attempts: 1,
            hits: 1,
            misses: 0,
            dueAt: '2027-01-01T00:00:00.000Z',
          ),
        ],
        '2026-11-05T00:00:00.000Z',
        candidates: const <ProductionTarget>[
          ProductionTarget(
            id: 'run',
            itemId: 'run',
            kind: ProductionTargetKind.word,
            text: 'run',
            meaning: '跑',
          ),
          ProductionTarget(
            id: 'curb',
            itemId: 'curb',
            kind: ProductionTargetKind.word,
            text: 'curb',
            meaning: '抑制',
          ),
        ],
      );
      expect(counts.newTargets, 1);
    });
  });

  group('跳过稿', () {
    test('进历史但不计入真实产出 / 平均分，导出写明跳过', () {
      final real = _record();
      final skipped = _record(
        text: '',
        skipped: true,
        hits: const <ProductionTargetHit>[],
        feedback: skippedProductionFeedback(),
      );
      final list = <WritingRecord>[real, skipped];
      final stats = productionStats(list);
      expect(stats.attempts, 1);
      expect(stats.avgScore, 80);
      expect(stats.targetAttempts, 1);
      expect(productionHistoryMarkdown(list), contains('跳过（未提交，无 AI 批改）'));
      expect(productionRecords(list), hasLength(2));
    });

    test('makeSkippedProductionRecord 记下草稿与题面，不伪造分数', () {
      final task = makeProductionTask(_prompt(), '工作', sessionId: 's1');
      final rec = makeSkippedProductionRecord(
        task: task,
        text: 'I will ',
        at: '2026-11-03T10:00:00.000Z',
        articleId: 'A',
        articleTitle: 'A',
        round: 1,
      );
      expect(rec.source, WritingSource.production);
      expect(rec.text, 'I will ');
      expect(rec.feedback.total, 0);
      expect(rec.feedback.summary, '跳过（未提交）');
      expect(productionTaskOf(rec)!.skipped, isTrue);
      expect(productionTaskOf(rec)!.round, 1);
    });
  });

  group('进度表守卫与合并', () {
    test('坏行丢弃，合并取更新的一行', () {
      final rows = normalizeProductionProgress(<Object?>[
        <String, Object?>{
          'key': 'word:run',
          'kind': 'word',
          'text': 'run',
          'meaning': '跑',
          'attempts': 2,
          'hits': 1,
          'misses': 1,
          'streak': 0,
          'lastAt': '2026-11-01T00:00:00.000Z',
          'dueAt': '2026-11-02T00:00:00.000Z',
          'updatedAt': '2026-11-01T00:00:00.000Z',
        },
        <String, Object?>{'kind': 'word', 'text': ''},
        'not a map',
        <String, Object?>{'kind': 'bogus', 'text': 'x'},
      ]);
      expect(rows, hasLength(1));
      expect(rows.first.attempts, 2);

      final merged = mergeProductionProgress(rows, <ProductionProgress>[
        rows.first.copyWith(
          attempts: 3,
          hits: 2,
          updatedAt: '2026-11-03T00:00:00.000Z',
        ),
      ]);
      expect(merged.first.attempts, 3);
      expect(merged.first.hits, 2);
    });

    test('合并不累加（同一批 attempts 不能被算两次）', () {
      final rows = <ProductionProgress>[_progress(attempts: 2, updatedAt: '2026-11-02T00:00:00.000Z')];
      final merged = mergeProductionProgress(rows, rows);
      expect(merged.first.attempts, 2);
    });

    test('负数与非数字一律归零；坏时间戳补当前时间', () {
      final rows = normalizeProductionProgress(<Object?>[
        <String, Object?>{
          'kind': 'phrase',
          'text': 'run out',
          'attempts': -3,
          'hits': 'abc',
          'misses': 1.9,
          'streak': 0,
          'lastAt': '不是时间',
          'dueAt': '2026-11-02T00:00:00.000Z',
        },
      ]);
      expect(rows, hasLength(1));
      expect(rows.first.attempts, 0);
      expect(rows.first.hits, 0);
      expect(rows.first.misses, 1);
      expect(rows.first.key, 'phrase:run out');
    });
  });

  group('旧记录迁移', () {
    test('同文章/日期/模式/主题补同一个 sessionId', () {
      final a = _record(sessionId: null);
      final b = _record(at: '2026-11-01T11:00:00.000Z', round: 2, sessionId: null);
      final result = assignLegacyProductionSessionIds(<WritingRecord>[a, b]);
      expect(result.changed, 2);
      expect(result.groups, hasLength(1));
      final group = result.groups.first;
      expect(group.articleId, 'A');
      expect(group.day, '2026-11-01');
      expect(group.mode, ProductionMode.full);
      expect(group.topic, '工作');
      expect(group.count, 2);
      expect(group.firstAt, '2026-11-01T10:00:00.000Z');
      expect(group.lastAt, '2026-11-01T11:00:00.000Z');

      final ids = result.records
          .map((r) => productionTaskOf(r)!.sessionId)
          .toList();
      expect(ids.first, isNotNull);
      expect(ids.first, ids.last);
      expect(ids.first, contains('legacy:A|2026-11-01|full|工作'));
    });

    test('已有 sessionId 的记录不动', () {
      final rec = _record();
      final result = assignLegacyProductionSessionIds(<WritingRecord>[rec]);
      expect(result.changed, 0);
      expect(productionTaskOf(result.records.first)!.sessionId, 's1');
    });

    test('旧记录没有 sessionId 时标成 legacy 分组', () {
      final groups = groupProductionAttempts(<WritingRecord>[_record(sessionId: null)]);
      expect(groups.first.legacy, isTrue);
    });
  });

  group('趋势与错因', () {
    test('productionTrend 算最近命中率与重写提分', () {
      final first = _record(at: '2026-11-04T10:00:00.000Z', round: 1);
      final second = _record(
        at: '2026-11-05T10:00:00.000Z',
        round: 2,
        feedback: const WritingFeedback(version: 2, total: 90, max: 100),
      );
      final trend = productionTrend(
        <WritingRecord>[first, second],
        '2026-11-06T00:00:00.000Z',
      );
      expect(trend.recentAttempts, 2);
      expect(trend.recentHits, 2);
      expect(trend.recentHitRate, 1);
      expect(trend.rewriteGain, 10);
    });

    test('productionTopErrors 按 rule+key 聚合，取前 N', () {
      final rec = _record(
        feedback: const WritingFeedback(
          version: 2,
          total: 60,
          max: 100,
          issues: <WritingIssue>[
            WritingIssue(
              original: 'I runed',
              suggestion: 'I ran',
              rule: WritingRule.tenseChoice,
              key: 'grammar-tense-choice',
            ),
            WritingIssue(
              original: 'a apple',
              suggestion: 'an apple',
              rule: WritingRule.articleWrong,
              key: 'article-wrong',
            ),
          ],
        ),
      );
      final errors = productionTopErrors(<WritingRecord>[rec, rec]);
      expect(errors, hasLength(2));
      expect(errors.first.count, 2);
    });
  });

  group('isProgressDue / isProgressWeak / isProgressRecent', () {
    test('坏时间戳当「到期」处理，别把复习卡住', () {
      expect(isProgressDue(_progress(dueAt: '不是时间'), '2026-11-05T00:00:00.000Z'), isTrue);
      expect(isProgressDue(_progress(dueAt: '2027-01-01T00:00:00.000Z'), '2026-11-05T00:00:00.000Z'), isFalse);
    });

    test('薄弱：漏过就算；没漏过看命中率', () {
      expect(isProgressWeak(_progress(attempts: 4, hits: 4, misses: 0)), isFalse);
      expect(isProgressWeak(_progress(attempts: 10, hits: 6, misses: 0)), isTrue);
      expect(isProgressWeak(_progress(attempts: 1, hits: 0, misses: 1)), isTrue);
    });

    test('最近 7 天内动过', () {
      expect(
        isProgressRecent(_progress(lastAt: '2026-11-04T00:00:00.000Z'), '2026-11-06T00:00:00.000Z'),
        isTrue,
      );
      expect(
        isProgressRecent(_progress(lastAt: '2026-10-01T00:00:00.000Z'), '2026-11-06T00:00:00.000Z'),
        isFalse,
      );
      expect(isProgressRecent(_progress(lastAt: '坏'), '2026-11-06T00:00:00.000Z'), isFalse);
    });
  });

  group('productionRecordKey', () {
    test('同一条记录稳定，改正文就变', () {
      final rec = _record();
      expect(productionRecordKey(rec), productionRecordKey(rec));
      expect(
        productionRecordKey(rec),
        isNot(productionRecordKey(rec.copyWith(text: 'I will follow up now.'))),
      );
    });
  });
}
