// 一键处理 ViewModel：词典加载、单步 / 全跑、忙碌守卫、错误提示。
import 'dart:async';

import 'package:dlaoshi_app/core/ecdict.dart';
import 'package:dlaoshi_app/data/dictionary_loader.dart' show resetDictionary;
import 'package:dlaoshi_app/services/dict_tools_service.dart';
import 'package:dlaoshi_app/viewmodels/dict_tools_view_model.dart';
import 'package:flutter_test/flutter_test.dart';

const String _words =
    'run\trʌn\tv\tmove fast\tv. 跑\tcet4\t3\t1\t100\t100\n';
Ecdict _dict() => parseEcdict(_words, '');

class _FakeRunner implements DictToolsRunner {
  final List<String> calls = <String>[];
  DictStepOutcome Function(String id)? respond;
  Completer<void>? gate;

  @override
  Future<DictStepOutcome> run(
    String stepId, {
    required Ecdict? dict,
    String? articleId,
    EcdictLevel level = EcdictLevel.cet6,
  }) async {
    calls.add(stepId);
    final g = gate;
    if (g != null) await g.future;
    return respond?.call(stepId) ??
        DictStepOutcome(
          stepId: stepId,
          status: DictStepStatus.ok,
          message: '$stepId 完成',
          count: 1,
        );
  }

  @override
  Future<List<DictStepOutcome>> runAll({
    required Ecdict? dict,
    String? articleId,
    EcdictLevel level = EcdictLevel.cet6,
  }) async =>
      [for (final id in ['pick', 'enrich', 'examples', 'lemma', 'confuse']) await run(id, dict: dict)];
}

void main() {
  setUp(resetDictionary);
  tearDown(resetDictionary);

  ({DictToolsViewModel vm, _FakeRunner runner}) make({
    Future<bool> Function()? loadDict,
    bool examplesReady = true,
  }) {
    final runner = _FakeRunner();
    final vm = DictToolsViewModel(
      service: runner,
      loadDict: loadDict ?? () async => true,
      dictionaryOf: _dict,
      examplesReady: examplesReady,
    );
    return (vm: vm, runner: runner);
  }

  test('bootstrap：词典没加载就去加载，加载完依赖词典的步骤可点', () async {
    var loaded = false;
    final t = make(loadDict: () async {
      loaded = true;
      return true;
    });
    expect(t.vm.dictionaryReady, isFalse);
    expect(t.vm.enabled('enrich', hasArticle: true), isFalse);

    await t.vm.bootstrap();

    expect(loaded, isTrue);
    expect(t.vm.dictionaryReady, isTrue);
    expect(t.vm.enabled('enrich', hasArticle: true), isTrue);
    expect(t.vm.enabled('examples', hasArticle: false), isTrue);
    t.vm.dispose();
  });

  test('没选文章：只有 pick 禁用', () async {
    final t = make();
    await t.vm.bootstrap();
    expect(t.vm.enabled('pick', hasArticle: false), isFalse);
    expect(t.vm.enabled('enrich', hasArticle: false), isTrue);
    t.vm.dispose();
  });

  test('runStep：跑完留下结果与提示，busy 复位', () async {
    final t = make();
    await t.vm.bootstrap();
    final out = await t.vm.runStep('enrich', articleId: 'a1');

    expect(out!.status, DictStepStatus.ok);
    expect(t.runner.calls, ['enrich']);
    expect(t.vm.outcomeOf('enrich')?.message, 'enrich 完成');
    expect(t.vm.notice, 'enrich 完成');
    expect(t.vm.busy, isFalse);
    expect(t.vm.runningStep, isNull);
    t.vm.dispose();
  });

  test('runStep：词典加载失败 → 不调用服务，给错误提示', () async {
    final t = make(loadDict: () async => false);
    final out = await t.vm.runStep('enrich');
    expect(out, isNull);
    expect(t.runner.calls, isEmpty);
    expect(t.vm.error, contains('词典'));
    t.vm.dispose();
  });

  test('runAll：按五步顺序跑，每步结果都记下来', () async {
    final t = make();
    final out = await t.vm.runAll(articleId: 'a1');
    expect(t.runner.calls, ['pick', 'enrich', 'examples', 'lemma', 'confuse']);
    expect(out, hasLength(5));
    expect(t.vm.outcomeOf('confuse'), isNotNull);
    expect(t.vm.notice, contains('完成'));
    t.vm.dispose();
  });

  test('服务返回 failed：界面拿到 error', () async {
    final t = make();
    t.runner.respond = (id) => DictStepOutcome(
          stepId: id,
          status: DictStepStatus.failed,
          message: '保存失败：磁盘满了',
        );
    await t.vm.runStep('enrich');
    expect(t.vm.error, '保存失败：磁盘满了');
    t.vm.dispose();
  });

  test('忙碌守卫：跑的时候再点不会并发', () async {
    final t = make();
    final gate = Completer<void>();
    t.runner.gate = gate;
    final first = t.vm.runStep('enrich');
    await Future<void>.delayed(Duration.zero);
    expect(t.vm.busy, isTrue);
    expect(await t.vm.runStep('lemma'), isNull);
    expect(t.runner.calls, ['enrich']);

    gate.complete();
    await first;
    expect(t.vm.busy, isFalse);
    t.vm.dispose();
  });

  test('setLevel：换水平只影响后续挑词', () {
    final t = make();
    expect(t.vm.level, EcdictLevel.cet6);
    t.vm.setLevel(EcdictLevel.ielts65);
    expect(t.vm.level, EcdictLevel.ielts65);
    t.vm.dispose();
  });
}
