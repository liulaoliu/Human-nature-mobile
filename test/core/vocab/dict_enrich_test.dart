// 用离线词典补音标/词性/释义的用例（逐条翻自 Web 版
// `src/core/dictEnrich.test.ts`，M-W 那两条不搬 —— App 没打包 M-W）。
import 'package:dlaoshi_app/core/ecdict.dart';
import 'package:dlaoshi_app/core/vocab/dict_enrich.dart';
import 'package:dlaoshi_app/models/vocab.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/vocab_fixture.dart';

final _now = DateTime.parse('2026-10-02T00:00:00.000Z');

/// 词典表：word / phonetic / pos / en / zh。
const String _words = 'run\trʌn\t\tv. move fast\tv. 跑\n'
    'hobble\t\'hɒbl\t\tvt. prevent\tt. 阻碍\n'
    'ensconce\tɪn\'skɒns\t\tvt. settle comfortably\tv. 使安顿\n'
    'consort\t\'kɒnsɔːt\tn\tkeep company\tn. 配偶\\nv. 交往\n';

Ecdict _dict() => parseEcdict(_words, 'ensconced\tensconce\n');

VocabLibrary _lib(List<VocabItem> items) => VocabLibrary(items: items);

void main() {
  group('enrichWithDict：离线词典补齐生词本', () {
    test('[Web] 补空着的字段（音标/词性/释义），并把状态推到 queried', () {
      final lib = _lib([vocabItem(word: 'hobble', lemma: 'hobble')]);
      final out = enrichWithDict(lib, _dict(), now: _now);

      final it = out.library.items.single;
      expect(out.filled, 1);
      expect(it.phonetic, "/'hɒbl/");
      expect(it.meaning, contains('阻碍'));
      expect(it.definition, contains('prevent'));
      expect(it.status, VocabStatus.queried);
      expect(it.fieldSources, <VocabField, VocabFieldSource>{
        VocabField.phonetic: VocabFieldSource.dict,
        VocabField.meaning: VocabFieldSource.dict,
        VocabField.definition: VocabFieldSource.dict,
      });
      expect(it.updatedAt, _now.toIso8601String());
    });

    test('[Web] 不覆盖已有内容（用户改过 / AI 给过的留着）', () {
      final lib = _lib([
        vocabItem(
          word: 'run',
          lemma: 'run',
          phonetic: '/MY/',
          meaning: '我的释义',
          definition: 'my own def',
          status: VocabStatus.edited,
        ),
      ]);
      final out = enrichWithDict(lib, _dict(), now: _now);

      final it = out.library.items.single;
      expect(it.phonetic, '/MY/');
      expect(it.meaning, '我的释义');
      expect(it.definition, 'my own def');
      expect(it.status, VocabStatus.edited);
      expect(out.filled, 0);
      expect(identical(out.library, lib), isTrue, reason: '没补到就返回同一个引用');
    });

    test('[Web] 幂等：第二次跑没有可补的，返回同一个引用', () {
      final lib = _lib([vocabItem(word: 'hobble', lemma: 'hobble')]);
      final first = enrichWithDict(lib, _dict(), now: _now);
      final second = enrichWithDict(first.library, _dict(), now: _now);

      expect(second.filled, 0);
      expect(identical(second.library, first.library), isTrue);
    });

    test('[Web] 词形变化也能查到（ensconced → ensconce）', () {
      final lib = _lib([vocabItem(word: 'ensconced', lemma: 'ensconced')]);
      final out = enrichWithDict(lib, _dict(), now: _now);
      expect(out.library.items.single.meaning, contains('安顿'));
    });

    test('[Web] 连字符复合词查不到整词，也按末段后缀给出词性', () {
      final lib = _lib([
        vocabItem(
          word: 'taxpayer-funded',
          lemma: 'taxpayer-funded',
          meaning: '由纳税人出资的',
          status: VocabStatus.queried,
        ),
        vocabItem(
          id: 'v2',
          word: 'world-leading',
          lemma: 'world-leading',
          meaning: '世界领先的',
          status: VocabStatus.queried,
        ),
      ]);
      final out = enrichWithDict(lib, _dict(), now: _now);

      expect(out.library.items[0].partOfSpeech, 'adj.');
      expect(out.library.items[1].partOfSpeech, 'adj.');
      // 推出来的词性不冒充词典 / AI 的结论。
      expect(
        out.library.items[0].fieldSources?[VocabField.partOfSpeech],
        isNull,
      );
    });

    test('[Web] 判不出来的复合词（末段是普通名词）不硬标词性', () {
      final lib = _lib([
        vocabItem(
          word: 'waiting-times',
          lemma: 'waiting-times',
          status: VocabStatus.unqueried,
        ),
      ]);
      final out = enrichWithDict(lib, _dict(), now: _now);
      expect(out.library.items.single.partOfSpeech, isNull);
    });

    test('[Web] 已有释义时不补词性：词典给的是词头首义，会和语境释义打架', () {
      final lib = _lib([
        vocabItem(
          word: 'consort',
          lemma: 'consort',
          meaning: '交往；厮混',
          fieldSources: const <VocabField, VocabFieldSource>{
            VocabField.meaning: VocabFieldSource.ai,
          },
        ),
      ]);
      final out = enrichWithDict(lib, _dict(), now: _now);

      final it = out.library.items.single;
      expect(it.meaning, '交往；厮混');
      expect(it.partOfSpeech, isNull);
    });

    test('[Web] 手动清空的字段不再被词典补回（只锁该字段，别的照补）', () {
      final lib = _lib([
        vocabItem(
          word: 'hobble',
          lemma: 'hobble',
          meaning: null,
          fieldSources: const <VocabField, VocabFieldSource>{
            VocabField.meaning: VocabFieldSource.manual,
          },
          status: VocabStatus.edited,
        ),
      ]);
      final out = enrichWithDict(lib, _dict(), now: _now);

      final it = out.library.items.single;
      expect(it.meaning, isNull);
      expect(it.phonetic, "/'hɒbl/");
      expect(it.fieldSources?[VocabField.meaning], VocabFieldSource.manual);
      expect(it.fieldSources?[VocabField.phonetic], VocabFieldSource.dict);
    });

    test('[Dart] 词典里查不到、也不是复合词：原样返回', () {
      final item = vocabItem(word: 'zzzz', lemma: 'zzzz');
      final lib = _lib([item]);
      final out = enrichWithDict(lib, _dict(), now: _now);
      expect(identical(out.library.items.single, item), isTrue);
      expect(out.filled, 0);
    });
  });
}
