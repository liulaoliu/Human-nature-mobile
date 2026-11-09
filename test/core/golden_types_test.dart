import 'package:dlaoshi_app/core/golden_types.dart';
import 'package:flutter_test/flutter_test.dart';

const _target = GoldenTarget(
  en: 'in response to',
  zh: '为了应对',
  kind: GoldenTargetKind.collocation,
);

GoldenLesson _lesson() => const GoldenLesson(
      source: GoldenSource.local,
      sentences: <GoldenSentence>[
        GoldenSentence(
          id: 's1',
          zh: '为了应对疫情，远程协作已成为新常态。',
          pattern: 'In response to + n., … has become …',
          targets: <GoldenTarget>[_target],
        ),
      ],
      selected: <String>['s1'],
      options: GoldenLessonOptions(dedupe: true, blankUnit: GoldenBlankUnit.target),
    );

void main() {
  group('golden_types 的 JSON 形状', () {
    test('GoldenTarget / GoldenSentence：可空字段缺省不写，枚举存 name', () {
      expect(_target.toJson(), <String, Object?>{
        'en': 'in response to',
        'kind': 'collocation',
        'zh': '为了应对',
      });
      expect(
        const GoldenTarget(en: 'run into', kind: GoldenTargetKind.word).toJson(),
        <String, Object?>{'en': 'run into', 'kind': 'word'},
      );
      final json = _lesson().sentences.first.toJson();
      expect(json['id'], 's1');
      expect(json['targets'], <Object?>[_target.toJson()]);
      expect(json.containsKey('tense'), isFalse);
      expect(json.containsKey('note'), isFalse);
    });

    test('GoldenSection / GoldenRubric：role 和可选字段', () {
      expect(
        const GoldenSection(
          paraId: 'p01',
          role: GoldenSectionRole.intro,
          points: <String>['a', 'b'],
        ).toJson(),
        <String, Object?>{
          'paraId': 'p01',
          'role': 'intro',
          'points': <String>['a', 'b'],
        },
      );
      expect(
        const GoldenRubric(
          dimension: '结构运用',
          weight: 50,
          description: '是否用上目标句型',
        ).toJson(),
        <String, Object?>{
          'dimension': '结构运用',
          'weight': 50,
          'description': '是否用上目标句型',
        },
      );
    });

    test('GoldenExamItem / GoldenExtraPoint：默认 source 与可选字段', () {
      expect(
        const GoldenExamItem(
          id: 'exam:s1',
          sentenceId: 's1',
          task: '仿写一句',
          model: 'In response to ...',
        ).toJson(),
        <String, Object?>{
          'id': 'exam:s1',
          'sentenceId': 's1',
          'task': '仿写一句',
          'model': 'In response to ...',
          'mustUse': <String>[],
          'rubric': <Object?>[],
          'source': 'ai',
        },
      );
      expect(
        const GoldenExtraPoint(
          sentenceId: 's1',
          en: 'come with',
          kind: GoldenExtraPointKind.chunk,
          source: GoldenExtraPointSource.user,
          issueKey: 'k1',
        ).toJson(),
        <String, Object?>{
          'sentenceId': 's1',
          'en': 'come with',
          'kind': 'chunk',
          'source': 'user',
          'issueKey': 'k1',
        },
      );
    });

    test('GoldenLessonOptions：只写显式设置，examAfter 缺省不写', () {
      expect(
        const GoldenLessonOptions().toJson(),
        <String, Object?>{'dedupe': false},
      );
      expect(
        const GoldenLessonOptions(
          pick: GoldenPickMode.manual,
          blankUnit: GoldenBlankUnit.target,
          sentenceFill: true,
          examAfter: 10,
        ).toJson(),
        <String, Object?>{
          'dedupe': false,
          'pick': 'manual',
          'blankUnit': 'target',
          'sentenceFill': true,
          'examAfter': 10,
        },
      );
    });

    test('GoldenLessonOptions.copyWith：不传原样保留，显式传 null 才清空', () {
      const base = GoldenLessonOptions(
        pick: GoldenPickMode.ai,
        blankUnit: GoldenBlankUnit.target,
        sentenceFill: false,
        examAfter: 10,
      );
      final kept = base.copyWith(dedupe: true);
      expect(kept.dedupe, isTrue);
      expect(kept.pick, GoldenPickMode.ai);
      expect(kept.blankUnit, GoldenBlankUnit.target);
      expect(kept.sentenceFill, isFalse);
      expect(kept.examAfter, 10);

      final cleared = base.copyWith(
        pick: () => null,
        blankUnit: () => null,
        sentenceFill: () => null,
        examAfter: () => null,
      );
      expect(cleared.pick, isNull);
      expect(cleared.blankUnit, isNull);
      expect(cleared.sentenceFill, isNull);
      expect(cleared.examAfter, isNull);
      expect(cleared.dedupe, isFalse);
    });

    test('GoldenLesson.toJson：列表字段恒在，可空字段缺省不写', () {
      final json = _lesson().toJson();
      expect(json['version'], 1);
      expect(json['source'], 'local');
      expect(json['outline'], <Object?>[]);
      expect(json['selected'], <String>['s1']);
      expect(json['options'], <String, Object?>{
        'dedupe': true,
        'blankUnit': 'target',
      });
      expect(json.containsKey('summary'), isFalse);
      expect(json.containsKey('aiSelected'), isFalse);
      expect(json.containsKey('exam'), isFalse);
      expect(json.containsKey('extraPoints'), isFalse);
      expect(json.containsKey('updatedAt'), isFalse);
    });
  });

  group('GoldenLesson.copyWith 的可空字段语义', () {
    test('不传字段时原样保留（含可空字段）', () {
      final base = _lesson().copyWith(
        summary: () => '本课讲应对变化的表达',
        exam: () => <GoldenExamItem>[
          const GoldenExamItem(
            id: 'exam:s1',
            sentenceId: 's1',
            task: '仿写',
            model: 'irrelevant',
          ),
        ],
        extraPoints: () => <GoldenExtraPoint>[],
        updatedAt: () => '2026-11-09T00:00:00Z',
      );
      final same = base.copyWith(version: 1);
      expect(same.summary, base.summary);
      expect(same.exam, base.exam);
      expect(same.extraPoints, base.extraPoints);
      expect(same.updatedAt, base.updatedAt);
      expect(same.aiSelected, base.aiSelected);
    });

    test('显式传 () => null 才能清空 exam / extraPoints / updatedAt / summary', () {
      final base = _lesson().copyWith(
        summary: () => 'x',
        exam: () => <GoldenExamItem>[
          const GoldenExamItem(
            id: 'exam:s1',
            sentenceId: 's1',
            task: '仿写',
            model: 'irrelevant',
          ),
        ],
        extraPoints: () => <GoldenExtraPoint>[],
        updatedAt: () => '2026-11-09T00:00:00Z',
      );
      final cleared = base.copyWith(
        summary: () => null,
        exam: () => null,
        extraPoints: () => null,
        updatedAt: () => null,
      );
      expect(cleared.summary, isNull);
      expect(cleared.exam, isNull);
      expect(cleared.extraPoints, isNull);
      expect(cleared.updatedAt, isNull);
      // 普通字段仍可覆盖，列表/身份不动。
      expect(cleared.sentences, base.sentences);
      expect(cleared.selected, base.selected);
      expect(cleared.version, base.version);
    });

    test('普通字段与可空字段可同时改，toJson 能读回', () {
      final lesson = _lesson().copyWith(
        source: GoldenSource.merged,
        sentences: const <GoldenSentence>[],
        selected: const <String>[],
        options: const GoldenLessonOptions(examAfter: 10),
        aiSelected: () => <String>['s1'],
        summary: () => '摘要',
      );
      final json = lesson.toJson();
      expect(json['source'], 'merged');
      expect(json['sentences'], <Object?>[]);
      expect(json['selected'], <String>[]);
      expect(json['aiSelected'], <String>['s1']);
      expect(json['summary'], '摘要');
      expect(json['options'], <String, Object?>{
        'dedupe': false,
        'examAfter': 10,
      });
    });
  });
}
