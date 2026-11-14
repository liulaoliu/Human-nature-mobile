/// 考试（检验掌握效果）的出题与判分逻辑。纯函数，不碰界面，方便单测。
///
/// 题型：
///   - spell 拼写：给中文释义，拼出英文单词（最基础）
///   - cloze 例句填空：把例句 / 来源句里的目标词挖空，要求填回来（考语境）
///   - usage 搭配填空：把「用法/搭配」里的目标词挖空（考使用方式）
///   - listen 听力填空：朗读句子、隐藏文本，听音填词
///   - choice 词形辨析：给释义，从形近/音近选项里选词（快）
///   - meaning 看词选义：给单词，从中文释义里选
///   - ear 听音拼词：只放音，拼出单词
///   - 精读专用：define / defineChoice（英英释义）、collocation（搭配默写）、
///     prep（介词填空）、mark（语法标记判断）、idiom（习语填空）
///
/// 判分对大小写、首尾标点、常见词形变化宽容。
///
/// 状态（2026-11-14 更新）：拷打页已经在用它了 —— `drill_prep.dart` + `quiz_pool.dart`
/// 走 `makeQuestion` / `buildQuizQuestions` / `countQuestions` / `isCorrect`；
/// 只剩 `isArticleKind`（`makeQuestion` 内部判文章级题型用）与 `makeDictationQuestion`
/// （听写专用，产品还没有听写入口）没有外部调用。
/// - 「整卷 / 题型考试」仍没做：组卷一次抽 N 题、交卷出报告、结果落库这三层编排还没有，
///   见 `docs/PLAN.md` P7。
/// 刻意不标 `@visibleForTesting`：这些是给产品功能用的，不是测试专用。
library;

import '../models/vocab.dart';
import 'quiz_parts.dart';
import 'vocab/word.dart';

export 'quiz_parts.dart'
    show
        blankParticle,
        blankWord,
        canonical,
        formatAnswerInput,
        maskAnswer,
        normalizeAnswer,
        particles,
        pickDistractors,
        pickMeaningDistractors,
        shuffleQuiz;

/// 词级题型（按生词出题，现有考试）。
enum VocabQuizKind {
  spell,
  cloze,
  usage,
  listen,
  choice,
  meaning,
  ear,
  // 精读专用（更细、更针对）：
  define, // 英英释义 → 写单词
  defineChoice, // 英英释义 → 选单词
  collocation, // 搭配默写：写出一条该词的搭配/词组
  prep, // 介词/小品词填空：搭配里挖掉 on/in/to…，选一个
  mark, // 语法标记判断：可数/不可数、及物/不及物、可分级/不可分级
  idiom, // 习语填空：习语里挖掉目标词，写回来
}

/// 文章级题型（按句子/段落出题，考理解与结构）。
enum ArticleQuizKind {
  translate,
  translate2,
  functionWord,
  ordering,
  grammar,
  phraseBlank, // 词组/习语填空：把句中的词组/习语挖空，选回去
}

/// 全部题型（词级 + 文章级）。
enum QuizKind {
  // 词级
  spell,
  cloze,
  usage,
  listen,
  choice,
  meaning,
  ear,
  define,
  defineChoice,
  collocation,
  prep,
  mark,
  idiom,
  // 文章级
  translate,
  translate2,
  functionWord,
  ordering,
  grammar,
  phraseBlank;

  /// 是不是「文章级」题型（英译中 / 排序 / 结构语法…）。词级考试要把它筛掉。
  bool get isArticle => const <QuizKind>{
        QuizKind.translate,
        QuizKind.translate2,
        QuizKind.functionWord,
        QuizKind.ordering,
        QuizKind.grammar,
        QuizKind.phraseBlank,
      }.contains(this);
}

/// 词级题型清单（顺序即 UI 里的展示顺序）。
const List<QuizKind> vocabKinds = <QuizKind>[
  QuizKind.spell,
  QuizKind.cloze,
  QuizKind.usage,
  QuizKind.listen,
  QuizKind.choice,
  QuizKind.meaning,
  QuizKind.ear,
  QuizKind.define,
  QuizKind.defineChoice,
  QuizKind.collocation,
  QuizKind.prep,
  QuizKind.mark,
  QuizKind.idiom,
];

/// 文章级题型清单。
const List<QuizKind> articleKinds = <QuizKind>[
  QuizKind.translate,
  QuizKind.translate2,
  QuizKind.functionWord,
  QuizKind.ordering,
  QuizKind.grammar,
  QuizKind.phraseBlank,
];

/// 全部题型。
const List<QuizKind> allQuizKinds = <QuizKind>[...vocabKinds, ...articleKinds];

const Map<QuizKind, String> quizKindLabel = <QuizKind, String>{
  QuizKind.spell: '拼写',
  QuizKind.cloze: '例句填空',
  QuizKind.usage: '搭配填空',
  QuizKind.listen: '听力填空',
  QuizKind.choice: '词形辨析',
  QuizKind.meaning: '看词选义',
  QuizKind.ear: '听音拼词',
  QuizKind.define: '英英释义（写）',
  QuizKind.defineChoice: '英英释义（选）',
  QuizKind.collocation: '搭配默写',
  QuizKind.prep: '介词填空',
  QuizKind.mark: '语法标记',
  QuizKind.idiom: '习语填空',
  QuizKind.translate: '英译中',
  QuizKind.translate2: '中译英',
  QuizKind.functionWord: '功能词填空',
  QuizKind.ordering: '句子排序',
  QuizKind.grammar: '结构 / 语法',
  QuizKind.phraseBlank: '词组/习语填空',
};

/// 宽容解析：字符串（`'spell'`）或枚举都能认。
QuizKind? parseQuizKind(Object? value) {
  if (value is QuizKind) return value;
  if (value is! String) return null;
  for (final k in allQuizKinds) {
    if (k.name == value) return k;
  }
  return null;
}

/// 是不是「文章级」题型。等价于 [QuizKind.isArticle]，给外部按老签名调用。
bool isArticleKind(QuizKind k) => k.isArticle;

/// 这道题是不是文章级（文章题不写 SRS / 错题本）。
///
/// 不能只看 `source == 'article'`：词级题的 `source` 是 null，
/// 而文章题的 kind 一定在 [articleKinds] 里，两条任一成立都算。
bool isArticleQuestion(QuizQuestion q) =>
    q.source == 'article' || q.kind.isArticle;

/// 一道题。
class QuizQuestion {
  const QuizQuestion({
    required this.id,
    required this.itemId,
    required this.lemma,
    required this.kind,
    this.source,
    required this.word,
    required this.prompt,
    this.meaning,
    this.partOfSpeech,
    this.phonetic,
    this.context,
    this.translation,
    this.audioText,
    this.options,
    required this.answer,
    required this.accept,
  });

  /// 题目唯一 id（词条 + 题型）
  final String id;
  final String itemId;
  final String lemma;
  final QuizKind kind;

  /// 来源：词级考试 / 文章级测验（文章题不写 SRS）。
  final String? source;

  /// 目标词（显示形式）
  final String word;

  /// 题干：拼写=释义；填空=挖空后的句子 / 搭配
  final String prompt;
  final String? meaning;
  final String? partOfSpeech;
  final String? phonetic;

  /// 未挖空的原文（答完后展示完整语境）
  final String? context;

  /// 例句中文翻译（若来源例句带）
  final String? translation;

  /// 听力填空：要朗读的完整句子
  final String? audioText;

  /// 词形辨析：选项（含正确答案）
  final List<String>? options;

  /// 标准答案（原句里出现的词形）
  final String answer;

  /// 可接受答案（归一化后）
  final List<String> accept;
}

/// 由词条 + 题型出一道题；数据不够（无释义 / 无句子）返回 null。
QuizQuestion? makeQuestion(VocabItem it, QuizKind kind, [List<VocabItem> pool = const <VocabItem>[]]) {
  // 文章级题型要整篇 doc（句子/段落），这里（词级）出不了
  if (kind.isArticle) return null;
  final word = it.word.trim();
  if (word.isEmpty) return null;

  QuizQuestion base({
    required String id,
    required String prompt,
    String? meaning,
    String? partOfSpeech,
    String? phonetic,
    String? context,
    String? translation,
    String? audioText,
    List<String>? options,
    required String answer,
    required List<String> accept,
  }) =>
      QuizQuestion(
        id: '$id:${kind.name}',
        itemId: it.id,
        lemma: it.lemma,
        kind: kind,
        word: word,
        prompt: prompt,
        meaning: meaning,
        partOfSpeech: partOfSpeech,
        phonetic: phonetic,
        context: context,
        translation: translation,
        audioText: audioText,
        options: options,
        answer: answer,
        accept: accept,
      );

  switch (kind) {
    case QuizKind.spell:
      final meaning = it.meaning;
      if (meaning == null || meaning.isEmpty) return null;
      return base(
        id: it.id,
        prompt: meaning,
        meaning: meaning,
        partOfSpeech: it.partOfSpeech,
        phonetic: it.phonetic,
        answer: word,
        accept: baseAccept(it, word),
      );

    case QuizKind.ear:
      // 听音拼词：只放音、不给任何文字提示
      return base(
        id: it.id,
        prompt: '',
        phonetic: it.phonetic,
        audioText: word,
        answer: word,
        accept: baseAccept(it, word),
      );

    case QuizKind.choice:
      final meaning = it.meaning;
      if (meaning == null || meaning.isEmpty) return null;
      final distractors = pickDistractors(it, pool, 3);
      if (distractors.isEmpty) return null;
      return base(
        id: it.id,
        prompt: meaning,
        meaning: meaning,
        partOfSpeech: it.partOfSpeech,
        phonetic: it.phonetic,
        options: shuffleQuiz(<String>[word, ...distractors]),
        answer: word,
        accept: baseAccept(it, word),
      );

    case QuizKind.meaning:
      final meaning = it.meaning;
      if (meaning == null || meaning.isEmpty) return null;
      final distractors = pickMeaningDistractors(it, pool, 3);
      if (distractors.isEmpty) return null;
      return base(
        id: it.id,
        // 题干是英文单词，选项是中文释义
        prompt: word,
        meaning: meaning,
        partOfSpeech: it.partOfSpeech,
        phonetic: it.phonetic,
        options: shuffleQuiz(<String>[meaning, ...distractors]),
        answer: meaning,
        accept: <String>[normalizeAnswer(meaning)],
      );

    case QuizKind.cloze:
    case QuizKind.listen:
      final contexts = <({String text, String? translation})>[
        for (final e in it.examples) (text: e.text, translation: e.translation),
        (text: it.source?.sentenceText ?? '', translation: null),
      ].where((c) => c.text.trim().isNotEmpty && c.text.trim().toLowerCase() != word.toLowerCase());
      for (final ctx in contexts) {
        final b = blankWord(ctx.text, it.lemma);
        if (b == null) continue;
        return base(
          id: it.id,
          // 听力填空不显示句子（靠听），其余显示挖空句
          prompt: kind == QuizKind.listen ? '' : b.blanked,
          meaning: it.meaning,
          partOfSpeech: it.partOfSpeech,
          phonetic: it.phonetic,
          context: ctx.text,
          translation: ctx.translation,
          audioText: kind == QuizKind.listen ? ctx.text : null,
          answer: b.surface,
          accept: baseAccept(it, b.surface),
        );
      }
      return null;

    // 英英释义 → 写单词（考「用英文理解英文」）
    case QuizKind.define:
      final def = (it.definition ?? '').trim();
      if (def.isEmpty) return null;
      return base(
        id: it.id,
        prompt: def,
        meaning: it.meaning,
        partOfSpeech: it.partOfSpeech,
        phonetic: it.phonetic,
        answer: word,
        accept: baseAccept(it, word),
      );

    // 英英释义 → 选单词（同上，选择题版）
    case QuizKind.defineChoice:
      final def = (it.definition ?? '').trim();
      if (def.isEmpty) return null;
      final distractors = pickDistractors(it, pool, 3);
      if (distractors.isEmpty) return null;
      return base(
        id: it.id,
        prompt: def,
        meaning: it.meaning,
        partOfSpeech: it.partOfSpeech,
        phonetic: it.phonetic,
        options: shuffleQuiz(<String>[word, ...distractors]),
        answer: word,
        accept: baseAccept(it, word),
      );

    // 搭配默写：给单词 + 中文，写出一条它的搭配 / 词组
    case QuizKind.collocation:
      final chunks = chunkList(it);
      if (chunks.isEmpty) return null;
      return base(
        id: it.id,
        prompt: word,
        meaning: it.meaning,
        partOfSpeech: it.partOfSpeech,
        phonetic: it.phonetic,
        context: chunks.join('；'),
        answer: chunks.first,
        accept: <String>{for (final c in chunks) normalizeAnswer(c)}.toList(),
      );

    // 介词 / 小品词填空：从搭配里挖掉 on/in/to…，选一个
    case QuizKind.prep:
      for (final c in chunkList(it)) {
        final b = blankParticle(c);
        if (b == null) continue;
        final answer = b.particle.toLowerCase();
        final others =
            shuffleQuiz(particles.where((p) => p != answer).toList()).take(3).toList();
        return base(
          id: it.id,
          prompt: b.blanked,
          meaning: it.meaning,
          partOfSpeech: it.partOfSpeech,
          phonetic: it.phonetic,
          context: c,
          options: shuffleQuiz(<String>[answer, ...others]),
          answer: answer,
          accept: <String>[normalizeAnswer(answer)],
        );
      }
      return null;

    // 语法标记判断：可数/不可数、及物/不及物、可分级/不可分级
    case QuizKind.mark:
      final m = markQuestion(it);
      if (m == null) return null;
      return base(
        id: it.id,
        prompt: m.label,
        meaning: it.meaning,
        partOfSpeech: it.partOfSpeech,
        phonetic: it.phonetic,
        context: it.meaning == null ? word : '$word — ${it.meaning}',
        options: shuffleQuiz(m.options),
        answer: m.answer,
        accept: <String>[normalizeAnswer(m.answer)],
      );

    // 习语填空：习语里挖掉目标词
    case QuizKind.idiom:
      for (final s in it.idioms ?? const <String>[]) {
        final b = blankWord(s, it.lemma);
        if (b == null) continue;
        return base(
          id: it.id,
          prompt: b.blanked,
          meaning: it.meaning,
          partOfSpeech: it.partOfSpeech,
          phonetic: it.phonetic,
          context: s,
          answer: b.surface,
          accept: baseAccept(it, b.surface),
        );
      }
      return null;

    // usage
    case QuizKind.usage:
      for (final u in it.usage) {
        final b = blankWord(u, it.lemma);
        if (b == null) continue;
        return base(
          id: it.id,
          prompt: b.blanked,
          meaning: it.meaning,
          partOfSpeech: it.partOfSpeech,
          phonetic: it.phonetic,
          context: u,
          answer: b.surface,
          accept: baseAccept(it, b.surface),
        );
      }
      return null;

    default:
      return null;
  }
}

/// 根据选中的题型，为一组词条出题（每个词条每种题型最多一题）。
List<QuizQuestion> buildQuizQuestions(List<VocabItem> items, List<QuizKind> kinds) {
  final out = <QuizQuestion>[];
  for (final it in items) {
    for (final kind in kinds) {
      final q = makeQuestion(it, kind, items);
      if (q != null) out.add(q);
    }
  }
  return out;
}

/// 「大概能出多少题」的**廉价**计数：不生成干扰项 / 例句，只判断词条是否具备条件。
/// 用于设置面板提示与统计，避免 O(N²) 的 buildQuizQuestions。
/// （默认「每词一题」模式下，约等于可选词条数。）
int countQuestions(List<VocabItem> items, List<QuizKind> kinds) {
  final wantEar = kinds.contains(QuizKind.ear);
  final wantMeaningKinds =
      kinds.contains(QuizKind.spell) || kinds.contains(QuizKind.choice) || kinds.contains(QuizKind.meaning);
  final wantCtx = kinds.contains(QuizKind.cloze) || kinds.contains(QuizKind.listen);
  final wantUsage = kinds.contains(QuizKind.usage);
  final wantDefine = kinds.contains(QuizKind.define) || kinds.contains(QuizKind.defineChoice);
  final wantChunk = kinds.contains(QuizKind.collocation) || kinds.contains(QuizKind.prep);
  final wantMark = kinds.contains(QuizKind.mark);
  final wantIdiom = kinds.contains(QuizKind.idiom);
  var n = 0;
  for (final it in items) {
    if (it.word.trim().isEmpty) continue;
    final hasMeaning = (it.meaning ?? '').isNotEmpty;
    final hasCtx = it.examples.any((e) => e.text.trim().isNotEmpty) ||
        (it.source?.sentenceText ?? '').isNotEmpty;
    final hasUsage = it.usage.isNotEmpty;
    final hasDefine = (it.definition ?? '').isNotEmpty;
    final hasChunk = chunkList(it).isNotEmpty;
    final hasMark = markQuestion(it) != null;
    final hasIdiom = (it.idioms ?? const <String>[]).any((s) => blankWord(s, it.lemma) != null);
    if (wantEar ||
        (wantMeaningKinds && hasMeaning) ||
        (wantCtx && hasCtx) ||
        (wantUsage && hasUsage) ||
        (wantDefine && hasDefine) ||
        (wantChunk && hasChunk) ||
        (wantMark && hasMark) ||
        (wantIdiom && hasIdiom)) {
      n += 1;
    }
  }
  return n;
}

/// 听写专用题：用给定句子（按原文顺序）做听力填空。
/// 与 `makeQuestion('listen')` 不同，这里强制用传入的句子，保证听写顺序 = 文章顺序。
QuizQuestion? makeDictationQuestion(VocabItem it, String sentenceText) {
  final word = it.word.trim();
  if (word.isEmpty || sentenceText.trim().isEmpty) return null;
  final b = blankWord(sentenceText, it.lemma);
  if (b == null) return null;
  return QuizQuestion(
    id: '${it.id}:dictation',
    itemId: it.id,
    lemma: it.lemma,
    kind: QuizKind.listen,
    word: word,
    prompt: '',
    meaning: it.meaning,
    partOfSpeech: it.partOfSpeech,
    phonetic: it.phonetic,
    context: sentenceText,
    audioText: sentenceText,
    answer: b.surface,
    accept: baseAccept(it, b.surface),
  );
}

/// 这些题型考的是「能不能拼对」，不能用词形还原兜底（ran ≠ run）。
const Set<QuizKind> strictSpelling = <QuizKind>{
  QuizKind.spell,
  QuizKind.ear,
  QuizKind.define,
};

/// 判分：归一化后精确命中，或词形还原一致（run / running），
/// 且忽略连字符 / 撇号 / 空格（bad-temperedly = badtemperedly）。
///
/// 拼写题例外：只认答案本身的拼写，不把 ran / runs 当成 run —— 否则
/// 「拼写错」永远触发不了「判为不认识」。
bool isCorrect(QuizQuestion q, String input) {
  final n = normalizeAnswer(input);
  if (n.isEmpty) return false;
  if (q.accept.contains(n)) return true;
  final c = canonical(n);
  if (c.isNotEmpty && q.accept.any((a) => canonical(a) == c)) return true;
  if (strictSpelling.contains(q.kind)) return false;
  // 词形兜底（run / running）只在「标准答案本身就是该词」时生效；
  // 否则搭配默写写个光杆单词也算对。
  final answerIsWord = lemmaOf(q.answer) == q.lemma;
  if (answerIsWord && lemmaOf(n) == q.lemma) return true;
  if (answerIsWord && c.isNotEmpty && canonical(q.lemma) == c) return true;
  return false;
}
