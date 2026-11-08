import 'package:flutter_test/flutter_test.dart';

import 'package:dlaoshi_app/core/analyzer_parse.dart';
import 'package:dlaoshi_app/core/analyzer_shared.dart';
import 'package:dlaoshi_app/models/document.dart';

Sentence _sentence({
  String id = 's1',
  String text = 'He runs fast.',
  String? translation,
  String? grammarNote,
  List<String> collocations = const [],
  List<String> vocab = const [],
}) =>
    Sentence(
      id: id,
      paraId: 'p1',
      text: text,
      translation: translation,
      grammarNote: grammarNote,
      collocations: collocations,
      vocab: vocab,
    );

void main() {
  group('analyzerParse 脏输入容忍', () {
    test('查词表跳过表头、分隔线与空行，Markdown 首尾竖线不产生空列', () {
      const raw = '| 单词 | 音标 | 词性 | 中文含义 |\n'
          '| --- | --- | --- | --- |\n'
          '\n'
          '| run | /rʌn/ | v. | 跑 |';
      final words = parseLookupTable(raw);
      expect(words, hasLength(1));
      expect(words.first.word, 'run');
      expect(words.first.phonetic, '/rʌn/');
      expect(words.first.partOfSpeech, 'v.');
      expect(words.first.meaning, '跑');
    });

    test('例句表在一行内丢掉跑飞的长句与重复句', () {
      final long = List.filled(40, 'word').join(' ');
      final raw = 'run | He runs fast. | 他跑得快。 | He runs fast. | 重复句 | $long | 长句';
      final rows = parseExampleTable(raw);
      expect(rows, hasLength(1));
      expect(rows.first.examples, hasLength(1));
      expect(rows.first.examples.first.text, 'He runs fast.');
    });

    test('词组表把「无」当成已标注（空数组），不是解析失败', () {
      final rows = parsePhraseTable('mrs | 无 | 无');
      expect(rows, hasLength(1));
      expect(rows.first.word, 'mrs');
      expect(rows.first.phrases, isEmpty);
      expect(rows.first.idioms, isEmpty);
    });

    test('语法标记只保留受控词表里的写法，别名归一，乱写的丢掉', () {
      final rows = parseGrammarMarkTable('run | 可数；transitive；胡写\nbad | 胡写');
      expect(rows, hasLength(2));
      expect(rows[0].word, 'run');
      expect(rows[0].marks, ['可数', '及物']);
      expect(rows[1].word, 'bad');
      expect(rows[1].marks, isEmpty);
    });

    test('非表格自由文本解析成空，不抛异常', () {
      expect(parseLookupTable('just some prose'), isEmpty);
      expect(parseExampleTable('a | b'), isEmpty);
      expect(parseConfusables('no pipe here'), isEmpty);
      expect(parsePosTable('a | b | c'), isEmpty);
    });

    test('混淆项表中文全角冒号也认，并去掉补充说明', () {
      final rows = parseConfusables('adapt | adopt:收养 ; adept：熟练的');
      expect(rows, hasLength(1));
      expect(rows.first.word, 'adapt');
      expect(rows.first.confusables, hasLength(2));
      expect(rows.first.confusables[0].word, 'adopt');
      expect(rows.first.confusables[0].meaning, '收养');
      expect(rows.first.confusables[1].word, 'adept');
      expect(rows.first.confusables[1].meaning, '熟练的');
    });

    test('cleanVocabWord 从「1. **词 (n.)** — 释义」里只取词形', () {
      expect(cleanVocabWord('1. **impeachment (n.)** — 弹劾'), 'impeachment');
      expect(cleanVocabWord('non-native'), 'non-native');
    });
  });

  group('查词表', () {
    test('七列全填时逐字段还原', () {
      const raw = 'run | /rʌn/ | v. | 跑 | run out；run a business | I run every day. — 我每天跑步。 | to move quickly on foot';
      final w = parseLookupTable(raw).single;
      expect(w.word, 'run');
      expect(w.phonetic, '/rʌn/');
      expect(w.partOfSpeech, 'v.');
      expect(w.meaning, '跑');
      expect(w.usage, ['run out', 'run a business']);
      expect(w.examples, hasLength(1));
      expect(w.examples!.first.text, 'I run every day.');
      expect(w.examples!.first.translation, '我每天跑步。');
      expect(w.definition, 'to move quickly on foot');
    });

    test('音标格为空时从单词格里拆出来（斜杠与方括号两种）', () {
      final a = parseLookupTable('run /rʌn/ | | v. | 跑').single;
      expect(a.word, 'run');
      expect(a.phonetic, '/rʌn/');
      final b = parseLookupTable('run [rʌn] | | v. | 跑').single;
      expect(b.word, 'run');
      expect(b.phonetic, '[rʌn]');
    });

    test('音标格已有内容时不再从单词格里拆，避免误伤', () {
      final w = parseLookupTable('run /rʌn/ | /rʌnɪŋ/ | v. | 跑').single;
      expect(w.word, 'run /rʌn/');
      expect(w.phonetic, '/rʌnɪŋ/');
    });

    test('释义里含 "word" 的正常行不会被当表头丢掉', () {
      final rows = parseLookupTable(
        '单词 | 音标 | 词性 | 中文含义\n'
        'portmanteau | /pɔːtˈmæntəʊ/ | n. | a word formed by blending two words',
      );
      expect(rows, hasLength(1));
      expect(rows.first.word, 'portmanteau');
    });

    test('缺列时不崩，多余的空字段保留为空串字段', () {
      final w = parseLookupTable('run').firstOrNull;
      expect(w, isNull, reason: '只有一列不算词条');
      final two = parseLookupTable('run | /rʌn/').single;
      expect(two.word, 'run');
      expect(two.meaning, isNull);
    });
  });

  group('parseAnalysis', () {
    test('JSON 数组里的词条能解析', () {
      final out = parseAnalysis(
        '[{"word":"run","phonetic":"/rʌn/","meaning":"跑"}]',
      );
      expect(out.words, hasLength(1));
      expect(out.words.first.meaning, '跑');
    });

    test('JSON 对象里的 sentences 能解析', () {
      final out = parseAnalysis(
        '{"sentences":[{"sentenceId":"s1","translation":"他跑得快。"}]}',
      );
      expect(out.sentences.single.sentenceId, 's1');
      expect(out.sentences.single.translation, '他跑得快。');
    });

    test('坏 JSON 落到表格解析', () {
      final out = parseAnalysis('{not json\ns1 | 他跑得快。');
      expect(out.sentences.single.sentenceId, 's1');
    });

    test('纯文本无表格时返回空', () {
      expect(parseAnalysis('就是一段话').isEmpty, isTrue);
      expect(parseAnalysis('   ').isEmpty, isTrue);
    });

    test('翻译表优先于查词表', () {
      final out = parseAnalysis('s1 | 他跑得快。\nrun | /rʌn/ | v. | 跑');
      expect(out.sentences, hasLength(1));
      expect(out.words, isEmpty);
    });
  });

  group('applyToSentence', () {
    test('翻译 / 语法 / 搭配 / 生词分别落到对应字段', () {
      final s = _sentence();
      expect(
        applyToSentence(s, AnalysisTask.translate, '他跑得快。').translation,
        '他跑得快。',
      );
      expect(
        applyToSentence(s, AnalysisTask.grammar, '主谓状').grammarNote,
        '主谓状',
      );
      expect(
        applyToSentence(s, AnalysisTask.collocations, 'run fast\nrun away')
            .collocations,
        ['run fast', 'run away'],
      );
      expect(
        applyToSentence(s, AnalysisTask.extractVocab, 'sprint, dash').vocab,
        ['sprint', 'dash'],
      );
    });

    test('追加时去重，原有内容保留', () {
      final s = _sentence(collocations: ['run fast'], vocab: ['sprint']);
      final out = applyToSentence(s, AnalysisTask.collocations, 'run fast；run late');
      expect(out.collocations, ['run fast', 'run late']);
      final out2 = applyToSentence(s, AnalysisTask.extractVocab, 'sprint, dash');
      expect(out2.vocab, ['sprint', 'dash']);
    });

    test('空文本或 lookup 任务不改句子', () {
      final s = _sentence();
      expect(identical(applyToSentence(s, AnalysisTask.translate, '  '), s), isTrue);
      expect(identical(applyToSentence(s, AnalysisTask.lookup, 'x'), s), isTrue);
    });
  });

  group('其它表格', () {
    test('原形表去掉竖线后的括号注释', () {
      final rows = parseLemmaTable('went | go（去）\ncompanies | company');
      expect(rows, hasLength(2));
      expect(rows[0].from, 'went');
      expect(rows[0].to, 'go');
      expect(rows[1].to, 'company');
    });

    test('原形表跳过表头行', () {
      expect(parseLemmaTable('原词形 | 原形\nwent | go'), hasLength(1));
    });

    test('辨析表 8 列才收，表头跳过', () {
      final raw = '原形 | 当前形式 | 当前词性 | 语法身份 | 成分 | 含义 | 理由 | 标注\n'
          'slide | sliding | adj. | 分词形容词 | 修饰 oil prices | 下跌的 | 主动进行 | adj.（分词形容词）';
      final rows = parsePosTable(raw);
      expect(rows, hasLength(1));
      expect(rows.first.lemma, 'slide');
      expect(rows.first.surface, 'sliding');
      expect(rows.first.label, 'adj.（分词形容词）');
    });

    test('翻译表只认 sN 这种 id', () {
      final rows = parseTranslationTable('**s12** | 他跑了。\nnote | 随便');
      expect(rows, hasLength(1));
      expect(rows.first.sentenceId, 's12');
    });

    test('示例表里例句真的含该词时优先保留', () {
      final rows = parseExampleTable(
        'run | He runs fast. | 他跑得快。 | He sprints. | 他冲刺。',
      );
      expect(rows, hasLength(1));
      expect(rows.first.examples, hasLength(1));
      expect(rows.first.examples.first.text, 'He runs fast.');
    });
  });

  group('parseWordList', () {
    test('逗号 / 顿号 / 分号都能拆，去重保序', () {
      expect(parseWordList('run, sprint、dash；run'), ['run', 'sprint', 'dash']);
    });

    test('去掉编号与尾部标点', () {
      expect(parseWordList('1. run.\n2. sprint!'), ['run', 'sprint']);
    });
  });
}
