/// `core/production_draft.dart` 的测试：会话草稿守卫、按「文章 + 吃法」分组、合并导入。
///
/// 用例对齐 Web 版 `src/core/productionDraft.test.ts`（80 行）。
library;

import 'package:dlaoshi_app/core/production.dart';
import 'package:dlaoshi_app/core/production_draft.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, Object?> _draft({
  String articleId = 'A',
  String at = '2026-11-01T00:00:00.000Z',
  String mode = 'full',
  String answer = 'draft',
  Object? prompts,
  Object? hits,
  int version = 1,
}) =>
    <String, Object?>{
      'version': version,
      'sessionId': 's1',
      'articleId': articleId,
      'at': at,
      'mode': mode,
      'sessionTopic': '随机',
      'prompts': prompts ??
          <Object?>[
            <String, Object?>{
              'id': 'p1',
              'zh': '说明进度',
              'goal': '汇报',
              'targets': <Object?>[
                <String, Object?>{
                  'id': 't1',
                  'itemId': 'v1',
                  'kind': 'word',
                  'text': 'run',
                  'meaning': '跑',
                },
              ],
            },
          ],
      'index': 0,
      'answer': answer,
      'feedback': null,
      'previousFeedback': null,
      'hits': hits ??
          <Object?>[
            <String, Object?>{
              'id': 't1',
              'kind': 'word',
              'text': 'run',
              'meaning': '跑',
              'used': true,
            },
          ],
      'round': 1,
      'notice': '',
    };

void main() {
  group('productionDraft：会话草稿守卫', () {
    test('合法草稿按文章恢复；坏题/坏命中丢弃', () {
      final ok = normalizeProductionDraft(_draft(), articleId: 'A');
      expect(ok?.answer, 'draft');
      expect(ok?.hits, hasLength(1));

      final bad = normalizeProductionDraft(
        _draft(
          prompts: <Object?>[
            <String, Object?>{
              'id': 'p1',
              'zh': 5,
              'goal': '汇报',
              'targets': const <Object?>[],
            },
            <String, Object?>{
              'id': 'p2',
              'zh': '说明进度',
              'goal': '汇报',
              'targets': const <Object?>[],
            },
          ],
          hits: <Object?>[
            <String, Object?>{
              'id': 't1',
              'kind': 'word',
              'text': 'run',
              'meaning': '跑',
              'used': 'yes',
            },
          ],
        ),
        articleId: 'A',
      );
      expect(bad?.prompts, hasLength(1));
      expect(bad?.hits[0].used, isFalse);
    });

    test('文章不匹配 / 坏版本 / 没题：不恢复', () {
      expect(normalizeProductionDraft(_draft(), articleId: 'B'), isNull);
      expect(
        normalizeProductionDraft(_draft(version: 2), articleId: 'A'),
        isNull,
      );
      expect(
        normalizeProductionDraft(
          _draft(prompts: const <Object?>[]),
          articleId: 'A',
        ),
        isNull,
      );
    });

    test('多草稿按「文章 + 模式」各存一组；合并导入取较新的一版', () {
      final other = _draft(
        articleId: 'B',
        at: '2026-11-02T00:00:00.000Z',
        answer: 'B draft',
      );
      final map = normalizeProductionDraftMap(<String, Object?>{
        'A': _draft(),
        'B': other,
      });
      expect(map.keys.toList()..sort(), <String>['A::full', 'B::full']);

      final merged = mergeProductionDraftMaps(
        <String, ProductionDraft>{
          'A::full': normalizeProductionDraft(_draft(answer: 'old'))!,
        },
        <String, ProductionDraft>{
          'A::full': normalizeProductionDraft(
            _draft(at: '2026-11-03T00:00:00.000Z', answer: 'new'),
          )!,
        },
      );
      expect(merged['A::full']!.answer, 'new');
    });

    test('同一篇文章的不同吃法各留一组，互不覆盖', () {
      final yogurt = _draft(
        mode: 'yogurt',
        at: '2026-11-04T00:00:00.000Z',
        answer: 'yogurt draft',
      );
      final map = normalizeProductionDraftMap(<String, Object?>{
        'A::full': _draft(),
        'A::yogurt': yogurt,
      });
      expect(map.keys.toList()..sort(), <String>['A::full', 'A::yogurt']);
      expect(map['A::yogurt']!.answer, 'yogurt draft');

      // 旧版按文章存的 map 也能读进来（键从草稿字段重新推）
      final legacy = normalizeProductionDraftMap(<String, Object?>{'A': yogurt});
      expect(legacy.keys.toList(), <String>['A::yogurt']);
    });

    test('吃法认不出 / 文章字段为空：各自退回默认', () {
      expect(
        normalizeProductionDraft(_draft(mode: 'smoothie'), articleId: 'A'),
        isNull,
      );
      final manual = normalizeProductionDraft(
        _draft(articleId: ''),
        articleId: 'manual',
      );
      expect(manual?.articleId, 'manual');
      expect(productionDraftKey('', ProductionMode.yogurt), 'manual::yogurt');
    });

    test('题号越界夹回范围，round 只有 ≥2 才记 2', () {
      final d = _draft()
        ..['index'] = 99
        ..['round'] = 3;
      expect(normalizeProductionDraft(d)?.index, 0);
      expect(normalizeProductionDraft(d)?.round, 2);
    });

    test('批改只认 v2：版本不对就丢掉', () {
      final withFeedback = _draft()
        ..['feedback'] = <String, Object?>{
          'version': 1,
          'scores': <Object?>[],
          'issues': <Object?>[],
          'total': 80,
          'max': 100,
        }
        ..['previousFeedback'] = <String, Object?>{
          'version': 2,
          'scores': <Object?>[],
          'issues': <Object?>[],
          'total': 70,
          'max': 100,
        };
      final d = normalizeProductionDraft(withFeedback);
      expect(d?.feedback, isNull);
      expect(d?.previousFeedback?['total'], 70);
    });

    test('草稿集合最多留 9 组，最旧的先丢', () {
      final raw = <String, Object?>{};
      for (var i = 0; i < 12; i++) {
        raw['A$i::full'] = _draft(
          articleId: 'A$i',
          at: '2026-11-${i.toString().padLeft(2, '0')}T00:00:00.000Z',
        );
      }
      final map = normalizeProductionDraftMap(raw);
      expect(map, hasLength(productionDraftCap));
      expect(map.containsKey('A0::full'), isFalse);
      expect(map.containsKey('A11::full'), isTrue);
    });
  });
}
