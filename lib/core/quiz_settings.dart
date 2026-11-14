/// 整卷考试的设置：模式 / 范围 / 题型 / 题量 / 三个开关，以及它们的存取口径。
///
/// 为什么单开一个文件：设置要落盘（`shared_preferences`），坏数据要回默认值，
/// 而默认值只能有一份 —— 让 ViewModel 直接读 Map 迟早会写出第二份默认值。
/// 对应 Web 版 `src/reader/hooks/useQuizSettings.ts`。
library;

import 'quiz.dart' show QuizKind, articleKinds, vocabKinds;
import 'quiz_pool.dart'
    show
        QuizMode,
        QuizScope,
        defaultQuizArticleKinds,
        defaultQuizLimit,
        defaultQuizVocabKinds,
        normalizeQuizLimit,
        parseQuizScope;

/// 反复鞭打的轮次上限（含第一轮），防止「永远考不完」。
const int maxQuizDrillRounds = 3;

/// 自动切题的延迟：答对快切、答错多停一会儿看答案。
const Duration quizAutoAdvanceCorrect = Duration(milliseconds: 650);
const Duration quizAutoAdvanceWrong = Duration(milliseconds: 1400);

/// 一份考试设置。
class QuizSettings {
  const QuizSettings({
    this.mode = QuizMode.vocab,
    this.scope = QuizScope.article,
    this.vocabKinds = defaultQuizVocabKinds,
    this.articleKinds = defaultQuizArticleKinds,
    this.limit = defaultQuizLimit,
    this.auto = false,
    this.speakAfter = true,
    this.loopWrong = false,
    this.unique = true,
  });

  final QuizMode mode;
  final QuizScope scope;

  /// 词级卷勾中的题型。
  final List<QuizKind> vocabKinds;

  /// 文章卷勾中的题型。
  final List<QuizKind> articleKinds;

  /// 题量；`0` = 不限。
  final int limit;

  /// 答完自动切下一题。
  final bool auto;

  /// 判分后朗读答案。
  final bool speakAfter;

  /// 交卷后还有错题就自动重练（最多 [maxQuizDrillRounds] 轮）。
  final bool loopWrong;

  /// 每个词最多出一题（关掉则允许同词多题型）。
  final bool unique;

  /// 当前模式对应的题型表。
  ///
  /// 听写固定只有「听力填空」一种；混合卷 = 词级 + 文章级的并集。
  /// 这两种模式不支持逐题型勾选（`toggleKind` 直接忽略）。
  List<QuizKind> get kindsForMode => switch (mode) {
        QuizMode.vocab => vocabKinds,
        QuizMode.article => articleKinds,
        QuizMode.dictation => const <QuizKind>[QuizKind.listen],
        QuizMode.mixed => <QuizKind>[...vocabKinds, ...articleKinds],
      };

  /// 这个模式的题型能不能手动勾选。
  bool get kindsEditable =>
      mode == QuizMode.vocab || mode == QuizMode.article;

  QuizSettings copyWith({
    QuizMode? mode,
    QuizScope? scope,
    List<QuizKind>? vocabKinds,
    List<QuizKind>? articleKinds,
    int? limit,
    bool? auto,
    bool? speakAfter,
    bool? loopWrong,
    bool? unique,
  }) =>
      QuizSettings(
        mode: mode ?? this.mode,
        scope: scope ?? this.scope,
        vocabKinds: vocabKinds ?? this.vocabKinds,
        articleKinds: articleKinds ?? this.articleKinds,
        limit: limit ?? this.limit,
        auto: auto ?? this.auto,
        speakAfter: speakAfter ?? this.speakAfter,
        loopWrong: loopWrong ?? this.loopWrong,
        unique: unique ?? this.unique,
      );

  /// 换模式时把该模式的题型重置成默认（两套题型互不相干）。
  QuizSettings withMode(QuizMode next) => next == mode
      ? this
      : copyWith(
          mode: next,
          vocabKinds:
              next == QuizMode.vocab ? defaultQuizVocabKinds : vocabKinds,
          articleKinds:
              next == QuizMode.article ? defaultQuizArticleKinds : articleKinds,
        );
}

/// 宽容解析：认不出的一律回默认值，绝不抛。
///
/// 题型表里混进非法值只丢那一个；整表都非法才回默认（空表出不了卷）。
QuizSettings parseQuizSettings(Object? raw) {
  const fallback = QuizSettings();
  if (raw is! Map) return fallback;

  final mode = switch (raw['mode']) {
    'article' => QuizMode.article,
    'dictation' => QuizMode.dictation,
    'mixed' => QuizMode.mixed,
    'vocab' => QuizMode.vocab,
    _ => fallback.mode,
  };

  return QuizSettings(
    mode: mode,
    scope: parseQuizScope(raw['scope']),
    vocabKinds: _parseKinds(raw['vocabKinds'], defaultQuizVocabKinds, vocabKinds),
    articleKinds:
        _parseKinds(raw['articleKinds'], defaultQuizArticleKinds, articleKinds),
    limit: normalizeQuizLimit(raw['limit']),
    auto: _parseBool(raw['auto'], fallback.auto),
    speakAfter: _parseBool(raw['speakAfter'], fallback.speakAfter),
    loopWrong: _parseBool(raw['loopWrong'], fallback.loopWrong),
    unique: _parseBool(raw['unique'], fallback.unique),
  );
}

Map<String, Object?> quizSettingsToJson(QuizSettings s) => <String, Object?>{
      'mode': s.mode.name,
      'scope': s.scope.storage,
      'vocabKinds': [for (final k in s.vocabKinds) k.name],
      'articleKinds': [for (final k in s.articleKinds) k.name],
      'limit': s.limit,
      'auto': s.auto,
      'speakAfter': s.speakAfter,
      'loopWrong': s.loopWrong,
      'unique': s.unique,
    };

/// 只留 [allowed] 里的题型；一个都不剩就回 [fallback]。
List<QuizKind> _parseKinds(Object? raw, List<QuizKind> fallback, List<QuizKind> allowed) {
  if (raw is! List) return fallback;
  final out = <QuizKind>[];
  for (final e in raw) {
    if (e is! String) continue;
    for (final k in allowed) {
      if (k.name == e && !out.contains(k)) {
        out.add(k);
        break;
      }
    }
  }
  return out.isEmpty ? fallback : out;
}

bool _parseBool(Object? raw, bool fallback) => switch (raw) {
      bool b => b,
      'true' => true,
      'false' => false,
      _ => fallback,
    };

/// 判分后要不要自动切题、隔多久切；`null` = 不切。
///
/// 拼写错要先确认（词已经排进重学队尾），自动切会把确认卡闪掉。
Duration? quizAutoAdvanceDelay({
  required bool auto,
  required bool correct,
  required bool spellingMiss,
}) {
  if (!auto) return null;
  if (!correct && spellingMiss) return null;
  return correct ? quizAutoAdvanceCorrect : quizAutoAdvanceWrong;
}

/// 交卷后要不要自动重练错题。
///
/// 拷打（[drill]）不自动重练：结算页的造句才是那一轮的落点。
bool quizShouldLoopWrong({
  required bool loopWrong,
  required bool drill,
  required int wrong,
  required int round,
}) =>
    loopWrong && !drill && wrong > 0 && round < maxQuizDrillRounds;

/// 判分后该朗读什么；`null` = 不读。
///
/// 语法标记的答案是「可数 / 不可数」这类中文标签，读出来像在念选项。
String? quizSpeakText({
  required bool speakAfter,
  required QuizKind kind,
  required String word,
  required String answer,
}) {
  if (!speakAfter) return null;
  if (kind == QuizKind.mark) return null;
  final text = kind == QuizKind.meaning ? word : answer;
  return text.trim().isEmpty ? null : text;
}

/// 题型在不在当前模式的合法表里（防止设置里塞错模式的值）。
bool quizKindAllowed(QuizKind kind, QuizMode mode) => switch (mode) {
      QuizMode.vocab => vocabKinds.contains(kind),
      QuizMode.article => articleKinds.contains(kind),
      QuizMode.dictation => kind == QuizKind.listen,
      QuizMode.mixed => vocabKinds.contains(kind) || articleKinds.contains(kind),
    };
