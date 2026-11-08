import 'package:dlaoshi_app/core/dictionary.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('inDictionary：连字符断词判断', () {
    test('常见词（含大小写）在词典里', () {
      expect(inDictionary('compared'), isTrue);
      expect(inDictionary('Company'), isTrue);
      expect(inDictionary('BETWEEN'), isTrue);
    });

    test('查不到的词 → false（调用方据此保留连字符）', () {
      expect(inDictionary('co-founder'), isFalse);
      expect(inDictionary('zzzz'), isFalse);
      expect(inDictionary(''), isFalse);
    });
  });
}
