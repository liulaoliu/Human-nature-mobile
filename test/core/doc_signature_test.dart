import 'package:dlaoshi_app/core/doc_signature.dart';
import 'package:dlaoshi_app/models/document.dart';
import 'package:flutter_test/flutter_test.dart';

int _id = 0;

Sentence line(String text) {
  _id += 1;
  return Sentence(id: 's$_id', paraId: 'p01', text: text);
}

void main() {
  group('docSignature', () {
    test('同一份正文签名一样', () {
      expect(docSignature([line('Run fast.')]), docSignature([line('Run fast.')]));
    });

    test('改一个字签名就变', () {
      expect(docSignature([line('Run fast.')]), isNot(docSignature([line('Walk slow.')])));
    });

    test('句间有分隔：ab|c 与 a|bc 不撞签名', () {
      expect(docSignature([line('ab'), line('c')]), isNot(docSignature([line('a'), line('bc')])));
    });

    test('空正文也有稳定签名', () {
      expect(docSignature(const []), docSignature(const []));
      expect(docSignature(const []).isNotEmpty, isTrue);
    });

    test('签名是 36 进制字符串（只含 0-9a-z）', () {
      final sig = docSignature([line('We keep up with the news.')]);
      expect(RegExp(r'^[0-9a-z]+$').hasMatch(sig), isTrue);
    });
  });

  group('articleKey', () {
    test('格式是「标识@签名」', () {
      final key = articleKey('doc:1', [line('Run fast.')]);
      expect(key.startsWith('doc:1@'), isTrue);
      expect(key.split('@'), hasLength(2));
    });

    test('标识相同、正文不同 → 键不同（不串篇）', () {
      final a = articleKey('', [line('Run fast.')]);
      final b = articleKey('', [line('Walk slow.')]);
      expect(a, isNot(b));
    });

    test('正文相同、标识不同 → 键不同（不串篇）', () {
      expect(articleKey('a', [line('Same.')]), isNot(articleKey('b', [line('Same.')])));
    });

    test('同一篇重开键一样，能续上', () {
      final s = [line('Run fast.')];
      expect(articleKey('doc:1', s), articleKey('doc:1', s));
    });
  });
}
