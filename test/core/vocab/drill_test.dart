import 'package:dlaoshi_app/core/vocab/drill.dart';
import 'package:flutter_test/flutter_test.dart';

const idle = DrillInput(active: true);

void main() {
  group('shouldDrill：锤炼的触发条件', () {
    test('什么都没发生 → 不锤炼', () {
      expect(shouldDrill(idle), isFalse);
    });

    test('没在背 / 拼错判定 / 释义关进行中 → 不锤炼', () {
      expect(shouldDrill(const DrillInput(active: false, timedOut: true)), isFalse);
      expect(shouldDrill(const DrillInput(active: true, spellMiss: true, timedOut: true)), isFalse);
      expect(shouldDrill(const DrillInput(active: true, learnPhase: true, timedOut: true)), isFalse);
    });

    test('卡停超时 → 锤炼', () {
      expect(shouldDrill(const DrillInput(active: true, timedOut: true)), isTrue);
    });

    test('重学卡正要评分 → 锤炼（评分门禁）', () {
      expect(shouldDrill(const DrillInput(active: true, relearnScoring: true)), isTrue);
    });

    test('已判完停在卡上等「下一词」时，超时或重学都不抢（否则看不到单词卡）', () {
      expect(shouldDrill(const DrillInput(active: true, parked: true, timedOut: true)), isFalse);
      expect(
        shouldDrill(const DrillInput(active: true, parked: true, relearnScoring: true)),
        isFalse,
      );
    });

    test('本轮已经锤炼过 → 不再拦（重学卡摊开过就一直是摊开，否则面板原地重开退不出去）', () {
      expect(
        shouldDrill(const DrillInput(active: true, cleared: true, relearnScoring: true)),
        isFalse,
      );
      expect(shouldDrill(const DrillInput(active: true, cleared: true, timedOut: true)), isFalse);
    });
  });

  group('drillReason：两种锤炼的来路要分得开', () {
    test('没触发 → null', () {
      expect(drillReason(idle), isNull);
    });

    test('卡停超时 → timeout（界面写「超时锤炼」）', () {
      expect(drillReason(const DrillInput(active: true, timedOut: true)), DrillReason.timeout);
    });

    test('重学卡正要评分 → relearn（界面写「重学补考」）', () {
      expect(
        drillReason(const DrillInput(active: true, relearnScoring: true)),
        DrillReason.relearn,
      );
    });

    test('两条同时成立 → 报 timeout（更早发生、更好解释）', () {
      expect(
        drillReason(const DrillInput(active: true, timedOut: true, relearnScoring: true)),
        DrillReason.timeout,
      );
    });

    test('被前置条件挡住时不管哪条触发都返回 null', () {
      const blocked = [
        DrillInput(active: false, timedOut: true),
        DrillInput(active: true, spellMiss: true, relearnScoring: true),
        DrillInput(active: true, learnPhase: true, timedOut: true),
        DrillInput(active: true, parked: true, relearnScoring: true),
        DrillInput(active: true, cleared: true, timedOut: true),
      ];
      for (final input in blocked) {
        expect(drillReason(input), isNull);
      }
    });
  });
}
