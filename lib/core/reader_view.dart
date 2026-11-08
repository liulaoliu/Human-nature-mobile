/// 阅读页「现在是不是在看正文」的唯一判定。
///
/// 视图只读结果，不许自己拼一长串布尔 —— Web 版之所以把这个判定抽出来，
/// 就是因为当初 `examActive || writingOpen || browseAll ...` 在三个组件里各写了一份，
/// 加了「速读」之后漏改其中一处，工具栏在速读时还挂着。
library;

/// 输入：阅读页当前开着哪些东西（每个面板一个布尔）。
class ReaderViewFlagsInput {
  const ReaderViewFlagsInput({
    this.studyOpen = false,
    this.quizSetupOpen = false,
    this.quizQueue = false,
    this.quizWarmup = false,
    this.quickQueue = false,
    this.dictQueue = false,
    this.listenOpen = false,
    this.backOpen = false,
    this.goldenOpen = false,
    this.productionOpen = false,
    this.speedReadOpen = false,
    this.writingOpen = false,
    this.browseAll = false,
    this.browseArticle = false,
  });

  /// 背单词（学习模式）。
  final bool studyOpen;

  /// 出题设置页。
  final bool quizSetupOpen;

  /// 考试队列（正式作答中）。
  final bool quizQueue;

  /// 温习队列（考前过一遍）。
  final bool quizWarmup;

  /// 快刷队列。
  final bool quickQueue;

  /// 词典快刷队列。
  final bool dictQueue;

  /// 听写 / 听力。
  final bool listenOpen;

  /// 回译。
  final bool backOpen;

  /// 金句课（D老师小课堂）。
  final bool goldenOpen;

  /// 产出训练。
  final bool productionOpen;

  /// 速读。
  final bool speedReadOpen;

  /// 仿写。
  final bool writingOpen;

  /// 生词浏览（全库）。
  final bool browseAll;

  /// 生词浏览（本篇）。
  final bool browseArticle;

  ReaderViewFlagsInput copyWith({
    bool? studyOpen,
    bool? quizSetupOpen,
    bool? quizQueue,
    bool? quizWarmup,
    bool? quickQueue,
    bool? dictQueue,
    bool? listenOpen,
    bool? backOpen,
    bool? goldenOpen,
    bool? productionOpen,
    bool? speedReadOpen,
    bool? writingOpen,
    bool? browseAll,
    bool? browseArticle,
  }) {
    return ReaderViewFlagsInput(
      studyOpen: studyOpen ?? this.studyOpen,
      quizSetupOpen: quizSetupOpen ?? this.quizSetupOpen,
      quizQueue: quizQueue ?? this.quizQueue,
      quizWarmup: quizWarmup ?? this.quizWarmup,
      quickQueue: quickQueue ?? this.quickQueue,
      dictQueue: dictQueue ?? this.dictQueue,
      listenOpen: listenOpen ?? this.listenOpen,
      backOpen: backOpen ?? this.backOpen,
      goldenOpen: goldenOpen ?? this.goldenOpen,
      productionOpen: productionOpen ?? this.productionOpen,
      speedReadOpen: speedReadOpen ?? this.speedReadOpen,
      writingOpen: writingOpen ?? this.writingOpen,
      browseAll: browseAll ?? this.browseAll,
      browseArticle: browseArticle ?? this.browseArticle,
    );
  }
}

/// 输出：两条结论，视图直接用。
class ReaderViewFlags {
  const ReaderViewFlags({required this.examActive, required this.readingView});

  /// 考试 / 快刷 / 听写 / 听力 / 金句 / 速读：隐藏正文。
  final bool examActive;

  /// 纯阅读视图：否则隐藏精读工具栏。
  final bool readingView;

  @override
  bool operator ==(Object other) =>
      other is ReaderViewFlags &&
      other.examActive == examActive &&
      other.readingView == readingView;

  @override
  int get hashCode => Object.hash(examActive, readingView);

  @override
  String toString() =>
      'ReaderViewFlags(examActive: $examActive, readingView: $readingView)';
}

/// 阅读页「现在是不是在看正文」的唯一判定。
ReaderViewFlags readerViewFlags(ReaderViewFlagsInput input) {
  final examActive = input.quizSetupOpen ||
      input.quizQueue ||
      input.quizWarmup ||
      input.quickQueue ||
      input.dictQueue ||
      input.listenOpen ||
      input.backOpen ||
      input.goldenOpen ||
      input.productionOpen ||
      input.speedReadOpen;
  final readingView = !input.studyOpen &&
      !examActive &&
      !input.writingOpen &&
      !input.browseAll &&
      !input.browseArticle;
  return ReaderViewFlags(examActive: examActive, readingView: readingView);
}
