/// 拷打造句的草稿：一批题共一份，按题存「写到一半的句子」与「已经粘回的批改」。
///
/// 为什么按题存而不是整批一个字符串：换题、刷新、退回背单词再进来都不该丢
/// 别的题的字；而批改结果要跟着题走，不然切回来就不知道这题批过没有。
///
/// 与仿写草稿（`writing_draft.dart`）的区别：那边一次只做一道题，草稿就是
/// 那一道；这边一轮有多道题，所以草稿是一张「题 id → 作答」的表。
library;

import 'writing.dart' show ImitationTask;
import 'writing_record.dart' show WritingRecord;

/// 一道题的作答与批改（批改原样存 JSON，读回时再走守卫）。
class DrillAnswerDraft {
  const DrillAnswerDraft({this.answer = '', this.feedback});

  final String answer;

  /// v2 批改的原始 JSON（读回时过 `writingFeedbackFromJson`）。
  final Map<String, Object?>? feedback;

  bool get isEmpty => answer.trim().isEmpty && feedback == null;

  DrillAnswerDraft copyWith({
    String? answer,
    Map<String, Object?>? Function()? feedback,
  }) =>
      DrillAnswerDraft(
        answer: answer ?? this.answer,
        feedback: feedback != null ? feedback() : this.feedback,
      );

  Map<String, Object?> toJson() => <String, Object?>{
        'answer': answer,
        if (feedback != null) 'feedback': feedback,
      };

  @override
  String toString() => 'DrillAnswerDraft(${answer.length} 字符)';
}

/// 一整批的草稿。
class DrillSentenceDraft {
  const DrillSentenceDraft({
    this.batchId = '',
    this.activeIndex = 0,
    this.answers = const <String, DrillAnswerDraft>{},
  });

  /// 这一批的稳定身份（`drillSentenceId` 算出来的）。
  final String batchId;

  /// 上次停在第几题。
  final int activeIndex;

  /// 题 id（= 任务 focus）→ 作答。
  final Map<String, DrillAnswerDraft> answers;

  bool get isEmpty => batchId.isEmpty && answers.isEmpty;

  DrillAnswerDraft answerOf(String taskId) =>
      answers[taskId] ?? const DrillAnswerDraft();

  DrillSentenceDraft withAnswer(String taskId, DrillAnswerDraft value) {
    final next = Map<String, DrillAnswerDraft>.of(answers);
    if (value.isEmpty) {
      next.remove(taskId);
    } else {
      next[taskId] = value;
    }
    return DrillSentenceDraft(
      batchId: batchId,
      activeIndex: activeIndex,
      answers: next,
    );
  }

  DrillSentenceDraft copyWith({String? batchId, int? activeIndex}) =>
      DrillSentenceDraft(
        batchId: batchId ?? this.batchId,
        activeIndex: activeIndex ?? this.activeIndex,
        answers: answers,
      );

  Map<String, Object?> toJson() => <String, Object?>{
        'batchId': batchId,
        'activeIndex': activeIndex,
        'answers': <String, Object?>{
          for (final MapEntry<String, DrillAnswerDraft> e in answers.entries)
            e.key: e.value.toJson(),
        },
      };

  @override
  String toString() =>
      'DrillSentenceDraft($batchId, ${answers.length} 题)';
}

/// 空草稿。
const DrillSentenceDraft emptyDrillSentenceDraft = DrillSentenceDraft();

/// 读回草稿：坏数据一律回空（宁可重写一遍，也不要让界面拿到半截结构）。
DrillSentenceDraft normalizeDrillSentenceDraft(Object? raw) {
  if (raw is! Map) return emptyDrillSentenceDraft;
  final batchId = raw['batchId'];
  final index = raw['activeIndex'];
  final answersRaw = raw['answers'];
  final answers = <String, DrillAnswerDraft>{};
  if (answersRaw is Map) {
    for (final MapEntry<Object?, Object?> e in answersRaw.entries) {
      final key = e.key;
      if (key is! String || key.isEmpty) continue;
      final value = e.value;
      if (value is! Map) continue;
      final answer = value['answer'];
      final feedback = value['feedback'];
      answers[key] = DrillAnswerDraft(
        answer: answer is String ? answer : '',
        feedback: feedback is Map
            ? <String, Object?>{
                for (final MapEntry<Object?, Object?> f in feedback.entries)
                  if (f.key is String) f.key! as String: f.value,
              }
            : null,
      );
    }
  }
  return DrillSentenceDraft(
    batchId: batchId is String ? batchId : '',
    activeIndex: index is int && index >= 0 ? index : 0,
    answers: answers,
  );
}

/// 一条造句记录该用的任务 id（= 任务上的 `focus`）。
String drillTaskIdOf(ImitationTask task) => task.focus ?? '';

/// 从记录反查题 id（旧记录没有 focus 时退回空串）。
String drillTaskIdOfRecord(WritingRecord rec) {
  final task = rec.task;
  if (task == null) return '';
  return drillTaskIdOf(task);
}
