// 逐条翻自 Web 版 `src/core/tatoeba.test.ts`（4 例）+ 一条 isolate 抽取用例。
import 'package:dlaoshi_app/core/tatoeba.dart';
import 'package:flutter_test/flutter_test.dart';

const String _tsv = 'mitigate\tThe drug can mitigate the pain.\t这种药能减轻疼痛。\n'
    'mitigate\tWe must mitigate the risks.\t我们必须降低风险。\n'
    'risk\tSmoking increases the risk of cancer.\t吸烟增加患癌风险。\n'
    '风险\t这是中文句子（应被忽略）\t中文';

void main() {
  group('parseTatoeba / examplesFor', () {
    test('[Web] 按词索引例句（英文 + 中文）', () {
      final t = parseTatoeba(_tsv);
      expect(examplesFor(t, 'mitigate'), const [
        TatoebaExample(en: 'The drug can mitigate the pain.', zh: '这种药能减轻疼痛。'),
        TatoebaExample(en: 'We must mitigate the risks.', zh: '我们必须降低风险。'),
      ]);
    });

    test('[Web] 查不到返回空；按词形优先、再原形', () {
      final t = parseTatoeba('run\tI run every day.\t我每天跑步。');
      expect(examplesFor(t, 'running', lemma: 'run'), const [
        TatoebaExample(en: 'I run every day.', zh: '我每天跑步。'),
      ]);
      expect(examplesFor(t, 'zzz'), isEmpty);
    });

    test('[Web] 每词最多 cap 条、去重', () {
      final t = parseTatoeba(
        ['a\tOne.\t一', 'a\tOne.\t一', 'a\tTwo.\t二', 'a\tThree.\t三'].join('\n'),
        cap: 2,
      );
      expect(
        examplesFor(t, 'a').map((x) => x.en),
        ['One.', 'Two.'],
      );
    });

    test('[Web] 缺列 / 空行跳过', () {
      expect(parseTatoeba('\nfoo\tbar\n\n').byWord, isEmpty);
    });

    test('懒加载只抽需要的词（大小写不敏感，原形也带上）', () {
      final out = examplesForWords(
        _tsv,
        {'MITIGATE', 'run'},
        cap: 1,
      );
      expect(out.keys, ['mitigate']);
      expect(out['mitigate'], hasLength(1));
      expect(out['mitigate']!.single.en, 'The drug can mitigate the pain.');
    });
  });
}
