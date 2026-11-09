import 'package:dlaoshi_app/core/import_ledger.dart';
import 'package:flutter_test/flutter_test.dart';

/// 导入账本：挡住「同一份备份点两次合并」。
///
/// 指纹必须与 Web 版逐位一致 —— 用户在浏览器里导入过的同一份文件，换到 App
/// 里也该被认出来；一旦算法差一个位，去重就形同虚设。所以前四个用例的期望值
/// 是拿 Web 版 `src/core/importLedger.ts` 跑出来的真值。
void main() {
  group('backupFingerprint', () {
    test('与 Web 版逐位一致（空串 / 单字符 / 单词 / JSON）', () {
      expect(backupFingerprint(''), 'ztntfp');
      expect(backupFingerprint('a'), '1r9wi7g');
      expect(backupFingerprint('hello'), 'm3bicr');
      expect(backupFingerprint('{"version":1}'), 'yrhscy');
    });

    test('同一份文本给同一个指纹，改一个字就变', () {
      const text = '{"version":1,"exportedAt":"2026-11-09T00:00:00.000Z"}';
      expect(backupFingerprint(text), backupFingerprint(text));
      expect(backupFingerprint(text), isNot(backupFingerprint('${text}x')));
    });

    test('不做 32 位截断就会溢出成另一个值（守 0xFFFFFFFF 这层）', () {
      // 长文本会走到乘法溢出那一位；这里只确认结果始终是 32 位以内的 36 进制串。
      final long = 'x' * 5000;
      final fp = backupFingerprint(long);
      expect(fp, isNotEmpty);
      expect(fp.length, lessThanOrEqualTo(7));
    });
  });

  group('账本', () {
    test('记进去的排在最前，重复的不新增', () {
      final once = rememberImport(const <String>[], 'aaa');
      expect(once, <String>['aaa']);
      final twice = rememberImport(once, 'bbb');
      expect(twice, <String>['bbb', 'aaa']);
      final again = rememberImport(twice, 'aaa');
      expect(again, <String>['aaa', 'bbb']);
    });

    test('最多留 20 个，最老的被挤掉', () {
      var ledger = const <String>[];
      for (var i = 0; i < 25; i++) {
        ledger = rememberImport(ledger, 'fp$i');
      }
      expect(ledger, hasLength(importLedgerLimit));
      expect(ledger.first, 'fp24');
      expect(hasImported(ledger, 'fp24'), isTrue);
      expect(hasImported(ledger, 'fp4'), isFalse);
    });

    test('空指纹不记账（坏数据不占位）', () {
      expect(rememberImport(<String>['a'], ''), <String>['a']);
      expect(hasImported(<String>['a'], ''), isFalse);
    });

    test('坏账本当空账本（不抛）', () {
      expect(parseImportLedger(null), isEmpty);
      expect(parseImportLedger('not a list'), isEmpty);
      expect(parseImportLedger(<Object?>[1, 'ok', null, '']), <String>['ok']);
      expect(
        parseImportLedger(<Object?>[for (var i = 0; i < 30; i++) 'fp$i']),
        hasLength(importLedgerLimit),
      );
    });
  });
}
