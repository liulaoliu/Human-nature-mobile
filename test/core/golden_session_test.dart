import 'package:dlaoshi_app/core/golden_session.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('金句课会话位置', () {
    test('视图白名单', () {
      expect(isGoldenView('home'), isTrue);
      expect(isGoldenView('errors'), isTrue);
      expect(isGoldenView('nope'), isFalse);
      expect(isGoldenView(null), isFalse);
      expect(isGoldenView(3), isFalse);
      expect(goldenViews, hasLength(9));
    });

    test('正常位置解析', () {
      final s = parseGoldenSession(<String, Object?>{
        'view': 'drill',
        'index': 3,
        'recallIndex': 1,
      });
      expect(s, isNotNull);
      expect(s!.view, 'drill');
      expect(s.index, 3);
      expect(s.recallIndex, 1);
    });

    test('坏数据一律当没存过', () {
      expect(parseGoldenSession(null), isNull);
      expect(parseGoldenSession('drill'), isNull);
      expect(parseGoldenSession(<Object?>[]), isNull);
      expect(parseGoldenSession(<String, Object?>{'view': 'unknown'}), isNull);
      expect(parseGoldenSession(<String, Object?>{}), isNull);
    });

    test('缺字段 / 脏数字归 0，不抛异常', () {
      final s = parseGoldenSession(<String, Object?>{'view': 'plan'});
      expect(s!.index, 0);
      expect(s.recallIndex, 0);

      final dirty = parseGoldenSession(<String, Object?>{
        'view': 'bank',
        'index': -5,
        'recallIndex': 'abc',
      });
      expect(dirty!.index, 0);
      expect(dirty.recallIndex, 0);

      final decimal = parseGoldenSession(<String, Object?>{
        'view': 'bank',
        'index': 2.7,
        'recallIndex': '4',
      });
      expect(decimal!.index, 2);
      expect(decimal.recallIndex, 4);
    });

    test('存储键按文章分，没文章用空串', () {
      expect(goldenSessionKey('a1'), 'reader:goldenSession:a1');
      expect(goldenSessionKey(null), 'reader:goldenSession:');
    });

    test('toJson 能原样读回', () {
      const s = GoldenSession(view: 'recall', index: 2, recallIndex: 5);
      expect(parseGoldenSession(s.toJson()), s);
      expect(s.copyWith(view: 'summary').view, 'summary');
      expect(s.copyWith(index: 0).index, 0);
      expect(emptyGoldenSession, const GoldenSession());
    });
  });
}
