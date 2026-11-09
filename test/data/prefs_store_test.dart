import 'package:flutter_test/flutter_test.dart';

import 'package:dlaoshi_app/core/entry_kind.dart';
import 'package:dlaoshi_app/core/study_pool.dart';
import 'package:dlaoshi_app/core/study_prefs.dart';
import 'package:dlaoshi_app/core/writing.dart';
import 'package:dlaoshi_app/core/writing_draft.dart';
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
}
