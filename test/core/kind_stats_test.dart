import 'package:dlaoshi_app/core/kind_stats.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('KindStat：plus 累加、== 比值不比引用', () {
    const a = KindStat(total: 2, correct: 1);
    expect(a.plus(), a);
    expect(a.plus(total: 1, correct: 1), const KindStat(total: 3, correct: 2));
    expect(a.plus().hashCode, a.hashCode);
    expect(a, isNot(const KindStat(total: 2, correct: 2)));
  });

  test('emptyKindStats 每次给新 Map', () {
    final a = emptyKindStats();
    final b = emptyKindStats();
    expect(a, isEmpty);
    expect(identical(a, b), isFalse);
    a['art'] = {'cloze': const KindStat(total: 1)};
    expect(b, isEmpty);
  });

  test('kindStatOf：命中取值，未命中给 0/0 且不建键', () {
    final stats = KindStats();
    stats['art'] = {'cloze': const KindStat(total: 2, correct: 1)};
    expect(kindStatOf(stats, 'art', 'cloze'), const KindStat(total: 2, correct: 1));
    expect(kindStatOf(stats, 'art', 'spell'), const KindStat());
    expect(stats['art']!.containsKey('spell'), isFalse);
    expect(kindStatOf(stats, 'nope', 'cloze'), const KindStat());
  });
}
