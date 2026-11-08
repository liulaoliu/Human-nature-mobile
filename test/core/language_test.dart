import 'package:dlaoshi_app/core/language.dart';
import 'package:dlaoshi_app/models/document.dart';
import 'package:flutter_test/flutter_test.dart';

Sentence _sentence(String id, [String text = 'Hello.']) => Sentence(
      id: id,
      paraId: 'p01',
      text: text,
    );

void main() {
  group('buildLanguagePrompt', () {
    test('含句 id 与 JSON schema', () {
      final p = buildLanguagePrompt([(id: 's001', text: 'The quick fox.')]);
      expect(p, contains('s001 | The quick fox.'));
      expect(p, contains('"sentences"'));
      expect(p, contains('structure'));
      expect(p, contains('idioms'));
    });
  });

  group('parseLanguage', () {
    test('解析合法 JSON（含栅栏）', () {
      const raw =
          '```json\n{"sentences":[{"id":"s001","structure":"主谓宾","grammar":"一般过去时","idioms":["break the ice"],"phrases":["a quick fox"],"usage":["fox 指狐狸"]}]}\n```';
      final rows = parseLanguage(raw);
      expect(rows, hasLength(1));
      expect(rows[0].id, 's001');
      expect(rows[0].structure, '主谓宾');
      expect(rows[0].grammar, '一般过去时');
      expect(rows[0].idioms, ['break the ice']);
    });

    test('丢弃没有 id 或全空的项', () {
      final raw =
          '{"sentences":[{"structure":"x"},{"id":"s002"},{"id":"s003","grammar":"g"}]}';
      expect(parseLanguage(raw).map((r) => r.id), ['s003']);
    });

    test('非法 JSON → 空', () {
      expect(parseLanguage('nope'), isEmpty);
    });

    test('前后夹着说明文字也能抠出 JSON', () {
      const raw = '好的，下面是分析结果：\n{"sentences":[{"id":"s001","grammar":"present tense"}]}\n希望有帮助！';
      final rows = parseLanguage(raw);
      expect(rows, hasLength(1));
      expect(rows[0].id, 's001');
    });

    test(r'模型偶发非法反斜杠转义（\( \) \[ \]）也能修好', () {
      const raw =
          r'{"sentences":[{"id":"s001","structure":"主句","phrases":\("a b", "c d"\),"idioms":\("x"\),"usage":\("u"\)}]}';
      final rows = parseLanguage(raw);
      expect(rows, hasLength(1));
      expect(rows[0].phrases, ['a b', 'c d']);
    });
  });

  group('语言点编辑表单（阅读 / 速读共用一份规则）', () {
    test('列表字段：分号 / 顿号 / 换行都算分隔，去空去重', () {
      expect(splitLanguageList(' a；b; a\n c 、'), ['a', 'b', 'c']);
      expect(splitLanguageList('   '), isEmpty);
    });

    test('表单 → 语言点：空字段不写；全是空白时返回空', () {
      final empty = languageFromForm(emptyLanguageForm);
      expect(normalizeLanguage(empty), isNull);

      final filled = languageFromForm(const LanguageForm(
        structure: 'SVO\n（主句）',
        grammar: '一般现在时',
        idioms: 'run fast\nwalk slow',
        phrases: '',
        usage: '用于口语',
      ));
      expect(filled.structure, 'SVO\n（主句）');
      expect(filled.grammar, '一般现在时');
      expect(filled.idioms, ['run fast', 'walk slow']);
      expect(filled.phrases, isNull);
      expect(filled.usage, ['用于口语']);
    });

    test('结构 / 语法保留原始换行与行首缩进（粘贴格式不变形）', () {
      final l = languageFromForm(const LanguageForm(
        structure: '主句\n  从句',
        grammar: '  缩进\n第二行',
      ));
      expect(l.structure, '主句\n  从句');
      expect(l.grammar, '  缩进\n第二行');
    });

    test('语言点 → 表单：列表用「；」连起来，再解析回同一条数据', () {
      const l = SentenceLanguage(
        structure: 'SV',
        grammar: '时态',
        idioms: ['a', 'b'],
        usage: ['u'],
      );
      final form = languageToForm(l);
      expect(form.idioms, 'a；b');
      expect(languageFromForm(form), l);
    });

    test('列表摘要：结构里的换行压成空格', () {
      const l = SentenceLanguage(
        structure: 'SVO\n主句',
        grammar: '现在时',
        idioms: ['x'],
      );
      expect(languagePreview(l), 'SVO 主句 ｜ 现在时 ｜ x');
    });

    test('粘贴清洗：吃掉空行，行首缩进与单换行原样保留', () {
      expect(cleanPastedText('主句\n\n  从句\n\n\n  非谓语'), '主句\n  从句\n  非谓语');
      expect(cleanPastedText('a\r\n\r\nb'), 'a\nb');
      expect(cleanPastedText('  x  \n\n  y  '), '  x\n  y');
    });

    test('粘贴清洗：本来就没有空行时原样返回（不触发接管）', () {
      expect(cleanPastedText('a\n  b'), 'a\n  b');
    });
  });

  group('旧语言点兼容（编辑要能回填）', () {
    test('单条 language + 列表字段是字符串：归一成数组，新行不被吞掉', () {
      final legacy = <String, Object?>{
        'language': <String, Object?>{
          'structure': '第一行\n第二行',
          'idioms': 'run fast；walk slow\nall in',
          'usage': '口语',
        },
      };
      final l = normalizeLanguageRaw(legacy['language']);
      expect(l, isNotNull);
      expect(l!.structure, '第一行\n第二行');
      expect(l.idioms, ['run fast', 'walk slow', 'all in']);
      expect(l.usage, ['口语']);
    });

    test('languageToForm 遇到字符串 / 缺字段也不炸，能回填成可编辑文本', () {
      final l = normalizeLanguageRaw(<String, Object?>{
        'structure': 'SVO',
        'idioms': 'a；b',
      });
      expect(
        languageToForm(l),
        const LanguageForm(structure: 'SVO', idioms: 'a；b'),
      );
    });

    test('languageToForm 对 null 给空表单', () {
      expect(languageToForm(null), emptyLanguageForm);
    });

    test('languages 是空数组时回落到单条 language（编辑不丢旧内容）', () {
      final s = Sentence(
        id: 's001',
        paraId: 'p01',
        text: 'Hi.',
        language: const SentenceLanguage(structure: 'SV'),
        languages: const [],
      );
      final got = getSentenceLanguages(s);
      expect(got, hasLength(1));
      expect(got[0].structure, 'SV');
      expect(got[0].source, LanguageSource.ai);
    });

    test('全空的旧语言点不算数', () {
      final s = Sentence(
        id: 's001',
        paraId: 'p01',
        text: 'Hi.',
        language: const SentenceLanguage(structure: '   '),
      );
      expect(getSentenceLanguages(s), isEmpty);
      expect(hasSentenceLanguage(s), isFalse);
    });
  });

  group('applyLanguage', () {
    test('按 id 写回（写入 languages，标 source=ai），未命中的不动', () {
      final sents = [_sentence('s001'), _sentence('s002', 'Other.')];
      final out = applyLanguage(sents, [
        const LanguageRow(id: 's001', structure: '主谓', phrases: ['a b']),
      ]);
      final first = out[0].languages![0];
      expect(first.structure, '主谓');
      expect(first.phrases, ['a b']);
      expect(first.source, LanguageSource.ai);
      expect(out[1].languages, isNull);
    });

    test('AI 只替换 AI 那条，保留手动条目', () {
      final base = Sentence(
        id: 's001',
        paraId: 'p01',
        text: 'Hello.',
        languages: const [
          SentenceLanguage(grammar: '手动语法', source: LanguageSource.manual),
        ],
      );
      final out = applyLanguage([base], [
        const LanguageRow(id: 's001', structure: '主谓'),
      ]);
      expect(out[0].languages, hasLength(2));
      expect(out[0].languages![0].structure, '主谓');
      expect(out[0].languages![0].source, LanguageSource.ai);
      expect(out[0].languages![1].grammar, '手动语法');
      expect(out[0].languages![1].source, LanguageSource.manual);
    });

    test('写入时间戳 at（用于「哪天加的语言点」）', () {
      final now = DateTime.utc(2026, 10, 15, 3);
      final out = applyLanguage(
        [_sentence('s001')],
        [const LanguageRow(id: 's001', grammar: 'x')],
        now: now,
      );
      expect(out[0].languages![0].at, '2026-10-15T03:00:00.000Z');
    });

    test('没有行时原样返回同一份列表', () {
      final sents = [_sentence('s001')];
      expect(identical(applyLanguage(sents, const []), sents), isTrue);
    });
  });
}
