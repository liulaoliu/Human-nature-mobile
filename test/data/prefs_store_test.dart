import 'package:flutter_test/flutter_test.dart';

import 'package:dlaoshi_app/core/ai_config.dart';
import 'package:dlaoshi_app/core/drill_sentence_draft.dart';
import 'package:dlaoshi_app/core/entry_kind.dart';
import 'package:dlaoshi_app/core/import_ledger.dart';
import 'package:dlaoshi_app/core/study_pool.dart';
import 'package:dlaoshi_app/core/study_prefs.dart';
import 'package:dlaoshi_app/core/writing.dart';
import 'package:dlaoshi_app/core/writing_draft.dart';
import 'package:dlaoshi_app/core/speed_read.dart' show defaultWpm, maxWpm, speedCursorKey;
import 'package:dlaoshi_app/core/speed_read_prefs.dart';
import 'package:dlaoshi_app/data/prefs_store.dart';

void main() {
  test('没存过：读回默认', () {
    final store = PrefsStore.memory();
    expect(store.loadStudyPrefs(), defaultStudyPrefs);
  });

  test('存了再读：字段都回来', () async {
    final store = PrefsStore.memory();
    const prefs = StudyPrefs(
      scope: StudyScope.lapses,
      deck: StudyDeck.collocation,
      groupSize: 30,
      newLimit: 12,
      newToday: 3,
      newTodayDay: '2026-11-08',
    );
    await store.saveStudyPrefs(prefs);
    expect(store.loadStudyPrefs(), prefs);
  });

  test('存坏了的 JSON：回默认，不抛', () async {
    final store = PrefsStore.memory({studyPrefsKey: '{oops'});
    expect(store.loadStudyPrefs(), defaultStudyPrefs);
  });

  test('存了但字段全是脏值：逐字段回默认', () async {
    final store = PrefsStore.memory({
      studyPrefsKey: '{"scope":"nope","newLimit":-5}',
    });
    final prefs = store.loadStudyPrefs();
    expect(prefs.scope, defaultStudyPrefs.scope);
    expect(prefs.newLimit, defaultStudyPrefs.newLimit);
  });

  test('空串当没存过', () {
    final store = PrefsStore.memory({studyPrefsKey: ''});
    expect(store.loadStudyPrefs(), defaultStudyPrefs);
  });

  test('后写的覆盖先写的', () async {
    final store = PrefsStore.memory();
    await store.saveStudyPrefs(const StudyPrefs(newLimit: 5));
    await store.saveStudyPrefs(const StudyPrefs(newLimit: 8));
    expect(store.loadStudyPrefs().newLimit, 8);
  });

  group('仿写草稿', () {
    test('没存过：回空草稿', () {
      expect(PrefsStore.memory().loadWritingDraft().isEmpty, isTrue);
    });

    test('存了再读：范句 / 作答 / 任务 / 必须用上的词都回来', () async {
      final store = PrefsStore.memory();
      const draft = WritingDraft(
        model: 'I will follow up with the client.',
        text: 'I will follow up with him tomorrow.',
        mustUse: <String>['follow up'],
        task: ImitationTask(task: '写一句关于跟进的话', model: 'm'),
      );
      await store.saveWritingDraft(draft);
      final back = store.loadWritingDraft();
      expect(back.model, draft.model);
      expect(back.text, draft.text);
      expect(back.mustUse, <String>['follow up']);
      expect(back.task?.task, '写一句关于跟进的话');
    });

    test('存坏了的 JSON：回空草稿，不抛', () {
      final store = PrefsStore.memory({writingDraftKey: '{oops'});
      expect(store.loadWritingDraft().isEmpty, isTrue);
    });

    test('空串当没存过', () {
      final store = PrefsStore.memory({writingDraftKey: ''});
      expect(store.loadWritingDraft().isEmpty, isTrue);
    });
  });

  group('拷打造句草稿', () {
    test('没存过：回空草稿', () {
      expect(
        PrefsStore.memory().loadDrillSentenceDraft().isEmpty,
        isTrue,
      );
    });

    test('存了再读：批次身份 / 停在哪题 / 各题作答与批改都回来', () async {
      final store = PrefsStore.memory();
      final draft = emptyDrillSentenceDraft
          .copyWith(batchId: 'drill:memory:abc', activeIndex: 2)
          .withAnswer(
            'drill:memory:1',
            const DrillAnswerDraft(
              answer: 'I will follow up with him.',
              feedback: <String, Object?>{'version': 2, 'total': 80},
            ),
          );
      await store.saveDrillSentenceDraft(draft);
      final back = store.loadDrillSentenceDraft();
      expect(back.batchId, 'drill:memory:abc');
      expect(back.activeIndex, 2);
      expect(back.answerOf('drill:memory:1').answer,
          'I will follow up with him.');
      expect(back.answerOf('drill:memory:1').feedback?['total'], 80);
    });

    test('存坏了的 JSON：回空草稿，不抛', () {
      final store = PrefsStore.memory({drillSentenceDraftKey: '{oops'});
      expect(store.loadDrillSentenceDraft().isEmpty, isTrue);
    });

    test('空串当没存过', () {
      final store = PrefsStore.memory({drillSentenceDraftKey: ''});
      expect(store.loadDrillSentenceDraft().isEmpty, isTrue);
    });
  });

  group('导入账本', () {
    test('没存过：回空表', () {
      expect(PrefsStore.memory().loadImportedBackups(), isEmpty);
    });

    test('存了再读：指纹按顺序留着', () async {
      final store = PrefsStore.memory();
      await store.saveImportedBackups(<String>['a', 'b']);
      expect(store.loadImportedBackups(), <String>['a', 'b']);
    });

    test('去重交给 rememberImport：重复指纹不会堆在账本里', () async {
      final store = PrefsStore.memory();
      var ledger = store.loadImportedBackups();
      for (final fp in <String>['a', 'b', 'a']) {
        ledger = rememberImport(ledger, fp);
        await store.saveImportedBackups(ledger);
      }
      expect(store.loadImportedBackups(), <String>['a', 'b']);
    });

    test('存坏了的 JSON：回空表，不抛', () {
      final store = PrefsStore.memory({importedBackupsKey: 'not json'});
      expect(store.loadImportedBackups(), isEmpty);
    });

    test('超过 20 条自动截断（只留最近的）', () async {
      final store = PrefsStore.memory();
      await store.saveImportedBackups(
        List<String>.generate(30, (i) => 'fp$i'),
      );
      final back = store.loadImportedBackups();
      expect(back, hasLength(importLedgerLimit));
      expect(back.first, 'fp0');
    });
  });

  group('AI 跑批设置', () {
    test('没存过：回默认（key 空）', () {
      expect(PrefsStore.memory().loadAiConfig(), defaultAiConfig);
    });

    test('存了再读：四个字段都回来', () async {
      final store = PrefsStore.memory();
      const config = AiConfig(
        baseUrl: 'https://api.example.com',
        apiKey: 'sk-test-key',
        model: 'deepseek-reasoner',
        temperature: 0.9,
      );
      await store.saveAiConfig(config);
      expect(store.loadAiConfig(), config);
    });

    test('坏 JSON 回默认，不把 key 泄漏出去', () {
      final store = PrefsStore.memory({aiConfigKey: 'not json'});
      expect(store.loadAiConfig(), defaultAiConfig);
      expect(store.loadAiConfig().hasApiKey, isFalse);
    });
  });

  group('速读偏好', () {
    test('没存过：语速回默认、自动拷打开、游标 0', () {
      final store = PrefsStore.memory();
      expect(store.loadSpeedWpm(), defaultWpm);
      expect(store.loadSpeedAutoDrill(), isTrue);
      expect(store.loadSpeedCursor('doc:1@abc'), 0);
    });

    test('存了再读：三个值都回来', () async {
      final store = PrefsStore.memory();
      await store.saveSpeedWpm(180);
      await store.saveSpeedAutoDrill(false);
      await store.saveSpeedCursor('doc:1@abc', 7);
      expect(store.loadSpeedWpm(), 180);
      expect(store.loadSpeedAutoDrill(), isFalse);
      expect(store.loadSpeedCursor('doc:1@abc'), 7);
    });

    test('游标按篇分开，换篇不串', () async {
      final store = PrefsStore.memory();
      await store.saveSpeedCursor('a@1', 3);
      expect(store.loadSpeedCursor('b@2'), 0);
      expect(store.loadSpeedCursor('a@1'), 3);
    });

    test('脏值不炸：语速夹回范围、游标回 0', () {
      final store = PrefsStore.memory({
        speedWpmKey: '9999',
        speedAutoDrillKey: 'off',
        speedCursorKey('a@1'): 'abc',
      });
      expect(store.loadSpeedWpm(), maxWpm);
      expect(store.loadSpeedAutoDrill(), isTrue);
      expect(store.loadSpeedCursor('a@1'), 0);
    });
  });
}
