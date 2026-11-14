/// 考试会话的序列化：`QuizQuestion` ↔ JSON，以及「这一卷考到哪了」的快照。
///
/// 为什么单开一个文件：`QuizQuestion` 有 17 个字段（其中 9 个可空、2 个是列表），
/// 序列化写在 ViewModel 里既过不了上帝类门禁，也没法单测坏数据。
/// 恢复会话时不重算题面 —— 题库 / 词库在两次启动之间可能已经变了，
/// 重算会换掉题、把「答过一半」的卷变成另一张。
library;

import 'quiz.dart' show QuizQuestion, parseQuizKind;
import 'quiz_pool.dart' show QuizMode, QuizScope, parseQuizScope;

/// 一道题的答题结果（与 `DrillResult` 同形，但只存恢复会话要用的字段）。
class QuizAnswerSnapshot {
  const QuizAnswerSnapshot({
    required this.question,
    required this.input,
    required this.correct,
  });

  final QuizQuestion question;
  final String input;
  final bool correct;
}

/// 一张考到一半的卷。
class QuizSession {
  const QuizSession({
    required this.mode,
    required this.scope,
    required this.questions,
    required this.index,
    this.results = const <QuizAnswerSnapshot>[],
    this.seconds = 0,
    this.articleId,
    this.drillRound = 1,
    this.recorded = false,
  });

  final QuizMode mode;
  final QuizScope scope;
  final List<QuizQuestion> questions;

  /// 当前停在第几题（0 起；等于 `questions.length` 表示已交卷）。
  final int index;
  final List<QuizAnswerSnapshot> results;
  final int seconds;
  final String? articleId;

  /// 反复鞭打跑到第几轮。
  final int drillRound;

  /// 这一轮是否已经记过成绩（重练错题时保持 true，不重复记）。
  final bool recorded;

  /// 恢复出来是不是「真的能接着答」：没题、或者停位越界都不算。
  bool get resumable =>
      questions.isNotEmpty && index >= 0 && index < questions.length;
}

Map<String, Object?> _questionToJson(QuizQuestion q) => <String, Object?>{
      'id': q.id,
      'itemId': q.itemId,
      'lemma': q.lemma,
      'kind': q.kind.name,
      'source': q.source,
      'word': q.word,
      'prompt': q.prompt,
      'meaning': q.meaning,
      'partOfSpeech': q.partOfSpeech,
      'phonetic': q.phonetic,
      'context': q.context,
      'translation': q.translation,
      'audioText': q.audioText,
      'options': q.options == null ? null : [...q.options!],
      'answer': q.answer,
      'accept': [...q.accept],
    };

/// 认不出题型就返回 null（整题丢掉，不让一张卷因为一条坏数据废掉）。
QuizQuestion? parseQuizQuestion(Object? raw) {
  if (raw is! Map) return null;
  final kind = parseQuizKind(raw['kind']);
  if (kind == null) return null;
  final id = _str(raw['id']);
  final itemId = _str(raw['itemId']);
  final answer = _str(raw['answer']);
  if (id.isEmpty || itemId.isEmpty || answer.isEmpty) return null;

  final options = raw['options'];
  return QuizQuestion(
    id: id,
    itemId: itemId,
    lemma: _str(raw['lemma']),
    kind: kind,
    source: _nullableStr(raw['source']),
    word: _str(raw['word']),
    prompt: _str(raw['prompt']),
    meaning: _nullableStr(raw['meaning']),
    partOfSpeech: _nullableStr(raw['partOfSpeech']),
    phonetic: _nullableStr(raw['phonetic']),
    context: _nullableStr(raw['context']),
    translation: _nullableStr(raw['translation']),
    audioText: _nullableStr(raw['audioText']),
    options: options is List
        ? [for (final o in options) if (o is String) o]
        : null,
    answer: answer,
    accept: _strList(raw['accept']),
  );
}

Map<String, Object?> quizSessionToJson(QuizSession s) => <String, Object?>{
      'mode': s.mode.name,
      'scope': s.scope.storage,
      'index': s.index,
      'seconds': s.seconds,
      'articleId': s.articleId,
      'drillRound': s.drillRound,
      'recorded': s.recorded,
      'questions': [for (final q in s.questions) _questionToJson(q)],
      'results': [
        for (final r in s.results)
          <String, Object?>{
            'input': r.input,
            'correct': r.correct,
            'question': _questionToJson(r.question),
          },
      ],
    };

/// 宽容解析：认不出的整卷作废（回 null），不让半张坏卷挡住开新卷。
QuizSession? parseQuizSession(Object? raw) {
  if (raw is! Map) return null;
  final mode = switch (raw['mode']) {
    'article' => QuizMode.article,
    'dictation' => QuizMode.dictation,
    'mixed' => QuizMode.mixed,
    'vocab' => QuizMode.vocab,
    _ => null,
  };
  if (mode == null) return null;

  final questions = <QuizQuestion>[];
  final rawQuestions = raw['questions'];
  if (rawQuestions is List) {
    for (final e in rawQuestions) {
      final q = parseQuizQuestion(e);
      if (q != null) questions.add(q);
    }
  }
  if (questions.isEmpty) return null;

  final results = <QuizAnswerSnapshot>[];
  final rawResults = raw['results'];
  if (rawResults is List) {
    for (final e in rawResults) {
      if (e is! Map) continue;
      final q = parseQuizQuestion(e['question']);
      if (q == null) continue;
      results.add(
        QuizAnswerSnapshot(
          question: q,
          input: _str(e['input']),
          correct: e['correct'] == true,
        ),
      );
    }
  }

  final session = QuizSession(
    mode: mode,
    scope: parseQuizScope(raw['scope']),
    questions: questions,
    index: _int(raw['index']),
    results: results,
    seconds: _int(raw['seconds']),
    articleId: _nullableStr(raw['articleId']),
    drillRound: _int(raw['drillRound'], fallback: 1),
    recorded: raw['recorded'] == true,
  );
  return session.resumable ? session : null;
}

String _str(Object? raw) => raw is String ? raw : '';

String? _nullableStr(Object? raw) {
  if (raw is! String) return null;
  return raw.isEmpty ? null : raw;
}

int _int(Object? raw, {int fallback = 0}) => switch (raw) {
      int v => v,
      double v => v.toInt(),
      String v => int.tryParse(v) ?? fallback,
      _ => fallback,
    };

List<String> _strList(Object? raw) {
  if (raw is! List) return const <String>[];
  return [for (final e in raw) if (e is String) e];
}
