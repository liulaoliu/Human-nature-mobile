import 'package:dlaoshi_app/data/tatoeba_loader.dart';
import 'package:flutter_test/flutter_test.dart';

/// 真·资源文件冒烟：确认 `assets/tatoeba/tatoeba-en.tsv` 打进包、
/// 抽取逻辑吃得下（6.5MB，跑一次约 1 秒）。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('从 assets 抽真例句：命中词有英文，部分带中文', () async {
    final out = await loadTatoebaExamples(
      {'mitigate', 'have'},
      background: false,
    );
    expect(out['mitigate'], isNotNull, reason: 'assets/tatoeba 没打进包或格式不对');
    expect(out['mitigate']!.first.en, isNotEmpty);
    expect(out['have'], isNotNull);
    expect(out['have']!.first.zh, isNotEmpty);
  });
}
