import 'package:dlaoshi_app/data/tatoeba_loader.dart';
import 'package:flutter_test/flutter_test.dart';

const String _tsv = 'mitigate\tThe drug can mitigate the pain.\t这种药能减轻疼痛。\n'
    'run\tI run every day.\t我每天跑步。\n';

void main() {
  group('loadTatoebaExamples', () {
    test('只返回要的词（大小写不敏感）', () async {
      final out = await loadTatoebaExamples(
        {'MITIGATE'},
        loader: () async => _tsv,
        background: false,
      );
      expect(out.keys, ['mitigate']);
      expect(out['mitigate']!.single.zh, '这种药能减轻疼痛。');
    });

    test('词集合为空：直接返回，不去读 asset', () async {
      var read = false;
      final out = await loadTatoebaExamples(
        <String>{},
        loader: () async {
          read = true;
          return _tsv;
        },
        background: false,
      );
      expect(out, isEmpty);
      expect(read, isFalse);
    });

    test('asset 缺失 / 空串：返回空 Map，不抛错', () async {
      expect(
        await loadTatoebaExamples({'x'}, loader: () async => null,
            background: false),
        isEmpty,
      );
      expect(
        await loadTatoebaExamples({'x'}, loader: () async => '  \n',
            background: false),
        isEmpty,
      );
    });
  });
}
