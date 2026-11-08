import 'package:flutter_test/flutter_test.dart';

import 'package:dlaoshi_app/core/entry_kind.dart';
import 'package:dlaoshi_app/core/study_pool.dart';
import 'package:dlaoshi_app/core/study_prefs.dart';

void main() {
  group('默认值', () {
    test('范围「没掌握」、牌组「单词」、每组跟随、每天 20 个新词', () {
      const p = defaultStudyPrefs;
      expect(p.scope, StudyScope.unmastered);
      expect(p.deck, StudyDeck.word);
      expect(p.groupSize, 0);
      expect(p.newLimit, 20);
      expect(p.newToday, 0);
      expect(p.newTodayDay, '');
    });

    test('remainingNew：限额 20、已用 5 → 还能 15；限额 0 表示不限', () {
      expect(const StudyPrefs(newLimit: 20, newToday: 5).remainingNew, 15);
      expect(const StudyPrefs(newLimit: 20, newToday: 20).remainingNew, 0);
      expect(const StudyPrefs(newLimit: 20, newToday: 99).remainingNew, 0);
      expect(const StudyPrefs(newLimit: 0, newToday: 5).remainingNew, 0);
    });
  });

  group('跨天归零', () {
    test('同一天不动', () {
      const p = StudyPrefs(newToday: 5, newTodayDay: '2026-11-08');
      expect(p.rollOver('2026-11-08'), p);
    });

    test('换了一天：已引入归零，日期改成今天', () {
      const p = StudyPrefs(newToday: 5, newTodayDay: '2026-11-07');
      final next = p.rollOver('2026-11-08');
      expect(next.newToday, 0);
      expect(next.newTodayDay, '2026-11-08');
      expect(next.newLimit, p.newLimit, reason: '其它字段不动');
    });

    test('从没记过日期：补上今天，不清零（本来就是 0）', () {
      const p = StudyPrefs(newTodayDay: '');
      final next = p.rollOver('2026-11-08');
      expect(next.newToday, 0);
      expect(next.newTodayDay, '2026-11-08');
    });

    test('bumpNewToday 跨天时会先归零再加一', () {
      const p = StudyPrefs(newToday: 19, newTodayDay: '2026-11-07');
      final next = p.bumpNewToday('2026-11-08');
      expect(next.newToday, 1);
      expect(next.newTodayDay, '2026-11-08');
    });

    test('bumpNewToday 同一天累加', () {
      const p = StudyPrefs(newToday: 3, newTodayDay: '2026-11-08');
      expect(p.bumpNewToday('2026-11-08').newToday, 4);
    });
  });

  group('序列化与守卫', () {
    test('往返一致', () {
      const p = StudyPrefs(
        scope: StudyScope.lapses,
        deck: StudyDeck.collocation,
        groupSize: 30,
        newLimit: 10,
        newToday: 4,
        newTodayDay: '2026-11-08',
      );
      expect(parseStudyPrefs(studyPrefsToJson(p)), p);
    });

    test('脏输入回默认：非 Map / 认不出的枚举 / 负数 / 非数字', () {
      expect(parseStudyPrefs(null), defaultStudyPrefs);
      expect(parseStudyPrefs('x'), defaultStudyPrefs);
      final p = parseStudyPrefs({
        'scope': 'nope',
        'deck': 42,
        'groupSize': -3,
        'newLimit': 'abc',
        'newToday': -1,
        'newTodayDay': 7,
      });
      expect(p, defaultStudyPrefs);
    });

    test('字符串数字也认（旧版本可能存成文本）', () {
      final p = parseStudyPrefs({'newLimit': '15', 'newToday': '3'});
      expect(p.newLimit, 15);
      expect(p.newToday, 3);
    });

    test('小数取整', () {
      expect(parseStudyPrefs({'newLimit': 12.6}).newLimit, 13);
    });

    test('copyWith 只改给的字段', () {
      const p = StudyPrefs(newLimit: 20, groupSize: 10);
      final next = p.copyWith(scope: StudyScope.all);
      expect(next.scope, StudyScope.all);
      expect(next.groupSize, 10);
      expect(next.newLimit, 20);
    });

    test('== / hashCode 按字段比', () {
      const a = StudyPrefs(newLimit: 10);
      const b = StudyPrefs(newLimit: 10);
      const c = StudyPrefs(newLimit: 11);
      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(a == c, isFalse);
    });
  });
}
