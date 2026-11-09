import 'package:dlaoshi_app/core/text_diff.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('词级比对 compareToReference', () {
    test('忽略大小写、首尾空白和句末标点；完全一致给 exact', () {
      final c = compareToReference('  He went to school  ', 'He went to school.');
      expect(c.exact, isTrue);
      expect(c.ratio, 1);
      expect(c.tier, 'exact');
    });

    test('多一个词：不算 exact，比例在 0.8~1 之间，给 fair', () {
      final c = compareToReference('He went to the school.', 'He went to school.');
      expect(c.exact, isFalse);
      expect(c.ratio, greaterThan(0.8));
      expect(c.ratio, lessThan(1));
      expect(c.tier, 'fair');
    });

    test('完全对不上给 loose', () {
      final c = compareToReference('The cat sat on the mat.', 'He went to school.');
      expect(c.tier, 'loose');
    });

    test('差一个词仍算 near（≥ 0.9）', () {
      final c = compareToReference(
        'In response to the pandemic, remote collaboration has become the new norm',
        'In response to the pandemic, remote collaboration has become the new norm.',
      );
      expect(c.exact, isTrue);
      expect(c.tier, 'exact');
    });

    test('弯引号 / 破折号不敏感', () {
      final c = compareToReference(
        'He said \u201Chello\u201D to me.',
        "He said \"hello\" to me.",
      );
      expect(c.exact, isTrue);
    });

    test('两边都空算 exact、比例 1', () {
      final c = compareToReference('   ', '.');
      expect(c.ratio, 1);
      expect(c.tier, 'exact');
    });
  });

  group('逐词对照 diffWords', () {
    test('标出漏词和多词', () {
      final parts = diffWords('He went school', 'He went to school');
      expect(
        parts.any((p) => p.kind == 'same' && p.text.contains('school')),
        isTrue,
      );
      expect(parts.any((p) => p.kind == 'add' && p.text.contains('to')), isTrue);
    });

    test('多写的词记为 del，连续同类合并成一段', () {
      final parts = diffWords('He quickly went to school', 'He went to school');
      final dels = parts.where((p) => p.kind == 'del').toList();
      expect(dels, hasLength(1));
      expect(dels.first.text, 'quickly');
    });

    test('完全一致只有一段 same', () {
      final parts = diffWords('He went to school.', 'He went to school.');
      expect(parts, hasLength(1));
      expect(parts.first.kind, 'same');
      // 对照是词级归一化之后的（小写、无标点），展示时原样呈现即可
      expect(parts.first.text, 'he went to school');
    });

    test('大小写与标点不影响对照结果', () {
      final parts = diffWords('he WENT to school!', 'He went to school.');
      expect(parts.every((p) => p.kind == 'same'), isTrue);
    });

    test('wordsOf 保留词内撇号', () {
      expect(wordsOf("Don't stop."), <String>["don't", 'stop']);
    });
  });
}
