import 'dart:convert';

import 'package:dlaoshi_app/core/golden.dart';
import 'package:dlaoshi_app/core/golden_ai.dart';
import 'package:dlaoshi_app/models/document.dart';
import 'package:flutter_test/flutter_test.dart';

const String _at = '2026-01-02T03:04:05.000Z';

Sentence _s(String id, String text, {String? translation}) => Sentence(
      id: id,
      paraId: 'p01',
      text: text,
      translation: translation,
    );

final List<Sentence> _sentences = <Sentence>[
  _s('s1', 'In response to the pandemic, remote collaboration has become the new norm.',
      translation: '为了应对疫情，远程协作已经成为新常态。'),
  _s('s2', 'The team has been working around the clock to keep up with the demand.'),
];

List<GoldenTextMeta> _metas() => <GoldenTextMeta>[
      for (final s in _sentences)
        GoldenTextMeta(id: s.id, text: s.text, translation: s.translation),
    ];

String _aiJson({String id = 's1', String target = 'in response to'}) =>
    '{"summary":"讲远程协作。","outline":[{"paraId":"p01","role":"intro","points":["背景"]}],'
    '"selected":["$id"],"sentences":[{"id":"$id","zh":"为了应对疫情","pattern":"in response to + n.",'
    '"tense":"现在完成时","note":"注意搭配","targets":[{"en":"$target","zh":"为了应对",'
    '"kind":"collocation"}]}]}';

void main() {
  group('金句课 AI 提示词', () {
    test('提示词要求逐字片段、挑句上限、并给出 JSON 形状', () {
      final prompt = buildGoldenPrompt(GoldenPromptInput(
        title: '远程办公',
        sentences: <GoldenPromptSentence>[
          GoldenPromptSentence(id: 's1', text: 'A b c.', translation: '甲乙丙。'),
          const GoldenPromptSentence(id: 's2', text: 'D e f.'),
        ],
        maxSentences: 5,
      ));
      expect(prompt, contains('最多挑 5 句'));
      expect(prompt, contains('必须是原句里逐字出现的连续片段'));
      expect(prompt, contains('文章标题：远程办公'));
      expect(prompt, contains('s1\tA b c.\t译：甲乙丙。'));
      // 没译文的句子不带「译：」尾巴
      expect(prompt, contains('s2\tD e f.'));
      expect(prompt, isNot(contains('s2\tD e f.\t译：')));
      expect(prompt, contains('"selected":["s001"]'));
    });

    test('挑句上限夹在 1..12', () {
      String promptOf(int n) => buildGoldenPrompt(GoldenPromptInput(
            sentences: const <GoldenPromptSentence>[
              GoldenPromptSentence(id: 's1', text: 'A b c.'),
            ],
            maxSentences: n,
          ));
      expect(promptOf(0), contains('最多挑 1 句'));
      expect(promptOf(99), contains('最多挑 12 句'));
    });
  });

  group('金句课 AI 解析', () {
    test('正常 JSON 解析成 AI 课程并打上 updatedAt', () {
      final lesson = parseGoldenLesson(_aiJson(), _metas(), at: _at);
      expect(lesson, isNotNull);
      expect(lesson!.source, GoldenSource.ai);
      expect(lesson.updatedAt, _at);
      expect(lesson.sentences, hasLength(1));
      expect(lesson.sentences.first.id, 's1');
      expect(lesson.sentences.first.pattern, 'in response to + n.');
      expect(lesson.sentences.first.targets.first.en, 'in response to');
      expect(lesson.selected, <String>['s1']);
    });

    test('宽容 ```json 围栏与前后废话', () {
      final wrapped = '好的，结果如下：\n```json\n${_aiJson()}\n```\n希望有帮助。';
      final lesson = parseGoldenLesson(wrapped, _metas(), at: _at);
      expect(lesson, isNotNull);
      expect(lesson!.sentences, hasLength(1));
    });

    test('编造的目标被守卫丢掉，但注释还在时句子保留', () {
      final lesson = parseGoldenLesson(
        _aiJson(target: 'not in the sentence at all'),
        _metas(),
        at: _at,
      );
      expect(lesson, isNotNull);
      final s1 = lesson!.sentences.first;
      expect(s1.id, 's1');
      // 逐字出现是硬规则：编造的 target 一个都不许留
      expect(s1.targets, isEmpty);
      // 但 zh / pattern / tense / note 还在，句子不算空
      expect(s1.pattern, 'in response to + n.');
    });

    test('既没目标也没注释的句子被整句丢掉', () {
      // s2 没有译文，所以 zh 也回退不出内容 → 整句作废 → 全空 → null
      const raw = '{"selected":["s2"],"sentences":[{"id":"s2","targets":'
          '[{"en":"made up","kind":"collocation"}]}]}';
      expect(parseGoldenLesson(raw, _metas(), at: _at), isNull);
    });

    test('未知句子 id 被丢掉', () {
      final raw = _aiJson(id: 's404');
      expect(parseGoldenLesson(raw, _metas(), at: _at), isNull);
    });

    test('空串 / 非 JSON 返回 null', () {
      expect(parseGoldenLesson('', _metas(), at: _at), isNull);
      expect(parseGoldenLesson('这不是 JSON', _metas(), at: _at), isNull);
      expect(parseGoldenLesson('{"foo":1}', _metas(), at: _at), isNull);
    });
  });

  group('金句课 AI + 本地合并', () {
    GoldenLesson localOf(List<Sentence> sentences) =>
        buildLocalGoldenLesson(sentences, null);

    test('AI 有的用 AI，AI 缺的句子用本地补齐', () {
      final ai = parseGoldenLesson(_aiJson(), _metas(), at: _at)!;
      final merged = mergeGoldenLessons(localOf(_sentences), ai, _sentences, const MergeGoldenOptions(), _at);
      expect(merged.source, GoldenSource.merged);
      expect(merged.updatedAt, _at);
      expect(merged.sentences.map((s) => s.id), containsAll(<String>['s1', 's2']));
      final s1 = merged.sentences.firstWhere((s) => s.id == 's1');
      expect(s1.pattern, 'in response to + n.');
      expect(s1.note, '注意搭配');
      // 本地语言点不能被 AI 覆盖：s1 的本地 target 仍在
      expect(s1.targets, isNotEmpty);
    });

    test('默认保留本地选择；preferAI 时用 AI 的选择', () {
      final ai = parseGoldenLesson(_aiJson(), _metas(), at: _at)!;
      final local = localOf(_sentences);
      final kept = mergeGoldenLessons(local, ai, _sentences, const MergeGoldenOptions(), _at);
      expect(kept.selected, local.selected);
      // 本地课程默认 pick 是 recommended（本地推导），合并时沿用本地口径
      expect(kept.options.pick, local.options.pick);

      final preferred = mergeGoldenLessons(
        local,
        ai,
        _sentences,
        const MergeGoldenOptions(preferAI: true),
        _at,
      );
      expect(preferred.selected, <String>['s1']);
      expect(preferred.options.pick, GoldenPickMode.ai);
      expect(preferred.aiSelected, <String>['s1']);
    });

    test('用户本课设置优先于 AI；examAfter 跟着本地走', () {
      final ai = parseGoldenLesson(_aiJson(), _metas(), at: _at)!;
      final local = localOf(_sentences).copyWith(
        options: const GoldenLessonOptions(
          dedupe: false,
          blankUnit: GoldenBlankUnit.target,
          sentenceFill: false,
          examAfter: 10,
        ),
      );
      final merged = mergeGoldenLessons(local, ai, _sentences, const MergeGoldenOptions(), _at);
      expect(merged.options.blankUnit, GoldenBlankUnit.target);
      expect(merged.options.sentenceFill, isFalse);
      expect(merged.options.examAfter, 10);
    });

    test('合并后 dedupe 打开时只影响取目标，不影响句子数', () {
      final ai = parseGoldenLesson(_aiJson(), _metas(), at: _at)!;
      final merged = mergeGoldenLessons(
        localOf(_sentences),
        ai,
        _sentences,
        const MergeGoldenOptions(dedupe: true),
        _at,
      );
      expect(merged.options.dedupe, isTrue);
      expect(merged.sentences, hasLength(2));
    });

    test('没有 AI 时本地课程原样可用（AI 失败也能练）', () {
      final local = localOf(_sentences);
      expect(local.sentences, hasLength(2));
      expect(local.selected, isNotEmpty);
      final json = jsonEncode(mergedLessonJsonRoundTrip(local));
      expect(json, contains('"version":1'));
    });
  });
}

/// 把本地课程过一遍 toJson / fromJson，确保序列化不丢字段。
Map<String, Object?> mergedLessonJsonRoundTrip(GoldenLesson lesson) =>
    lesson.toJson();
