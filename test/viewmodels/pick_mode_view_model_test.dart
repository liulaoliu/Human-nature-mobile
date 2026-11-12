import 'package:dlaoshi_app/core/vocab_stats.dart' show PickSession;
import 'package:dlaoshi_app/models/vocab.dart' show VocabItemKind;
import 'package:dlaoshi_app/viewmodels/pick_mode_view_model.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late DateTime clock;
  PickModeViewModel make() => PickModeViewModel(now: () => clock);

  setUp(() {
    clock = DateTime(2026, 11, 12, 10);
  });

  test('默认关着，点了也不选中', () {
    final vm = make();
    expect(vm.enabled, isFalse);
    expect(vm.toggle('s1', 0, 'run'), isFalse);
    expect(vm.count, 0);
  });

  test('打开后点词能选中、再点取消', () {
    final vm = make();
    vm.setEnabled(true);
    expect(vm.toggle('s1', 0, 'run'), isTrue);
    expect(vm.count, 1);
    vm.toggle('s1', 0, 'run');
    expect(vm.count, 0);
  });

  test('关掉选词模式会清空选中', () {
    final vm = make();
    vm.setEnabled(true);
    vm.toggle('s1', 0, 'run');
    vm.setEnabled(false);
    expect(vm.count, 0);
    expect(vm.state.isEmpty, isTrue);
  });

  test('开 → 关 会通知监听者，重复设置同一个值不通知', () {
    final vm = make();
    var n = 0;
    vm.addListener(() => n++);
    vm.setEnabled(true);
    expect(n, 1);
    vm.setEnabled(true);
    expect(n, 1);
    vm.setEnabled(false);
    expect(n, 2);
  });

  test('toggleEnabled 来回切', () {
    final vm = make();
    vm.toggleEnabled();
    expect(vm.enabled, isTrue);
    vm.toggleEnabled();
    expect(vm.enabled, isFalse);
  });

  test('takeSession：不到 1 秒且没选词就不记', () {
    final vm = make();
    vm.setEnabled(true);
    clock = clock.add(const Duration(milliseconds: 300));
    expect(vm.takeSession(), isNull);
  });

  test('takeSession：选了词就记，秒数按开关打开算', () {
    final vm = make();
    vm.setEnabled(true);
    vm.toggle('s1', 0, 'run');
    clock = clock.add(const Duration(seconds: 7));
    final PickSession? s = vm.takeSession();
    expect(s, isNotNull);
    expect(s!.seconds, 7);
    expect(s.picked, 1);
    expect(s.at, DateTime(2026, 11, 12, 10).toIso8601String());
  });

  test('takeSession 之后计时从头算', () {
    final vm = make();
    vm.setEnabled(true);
    clock = clock.add(const Duration(seconds: 5));
    expect(vm.takeSession()!.seconds, 5);
    clock = clock.add(const Duration(seconds: 3));
    expect(vm.takeSession()!.seconds, 3);
  });

  test('没打开过选词模式时 takeSession 什么都不给', () {
    final vm = make();
    clock = clock.add(const Duration(minutes: 2));
    expect(vm.takeSession(), isNull);
  });

  group('多选开关', () {
    test('默认关着（单选），点第二个词会顶掉第一个', () {
      final vm = make();
      vm.setEnabled(true);
      expect(vm.multi, isFalse);
      vm.toggle('s1', 0, 'run');
      vm.toggle('s1', 5, 'sharp');
      expect(vm.count, 1);
      expect(vm.state.contains('s1', 5), isTrue);
      expect(vm.state.contains('s1', 0), isFalse);
    });

    test('打开多选后能连点，相邻的词合成一条词组', () {
      final vm = make();
      vm.setEnabled(true);
      vm.setMulti(true);
      vm.toggle('s1', 2, 'keep');
      vm.toggle('s1', 3, 'up');
      expect(vm.count, 2);
      expect(vm.entryCount, 1);
      final e = vm.state.entries.single;
      expect(e.word, 'keep up');
      expect(e.count, 2);
      expect(e.kind, VocabItemKind.phrase);
    });

    test('单个词不标类型（与 Web 一致）', () {
      final vm = make();
      vm.setEnabled(true);
      vm.toggle('s1', 0, 'run');
      expect(vm.state.entries.single.kind, isNull);
      expect(vm.state.entries.single.isPhrase, isFalse);
    });

    test('从多选切回单选：只留最后点的那个', () {
      final vm = make();
      vm.setEnabled(true);
      vm.setMulti(true);
      vm.toggle('s1', 0, 'run');
      vm.toggle('s1', 5, 'sharp');
      expect(vm.count, 2);
      vm.setMulti(false);
      expect(vm.count, 1);
      expect(vm.state.contains('s1', 5), isTrue);
    });

    test('设置同一个值不通知，切换会通知', () {
      final vm = make();
      var n = 0;
      vm.addListener(() => n++);
      vm.setMulti(false);
      expect(n, 0);
      vm.toggleMulti();
      expect(vm.multi, isTrue);
      expect(n, 1);
    });

    test('单选下再点同一个词是取消（不是留着一个）', () {
      final vm = make();
      vm.setEnabled(true);
      vm.toggle('s1', 0, 'run');
      vm.toggle('s1', 0, 'run');
      expect(vm.count, 0);
      expect(vm.entryCount, 0);
    });
  });
}
