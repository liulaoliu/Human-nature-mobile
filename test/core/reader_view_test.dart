import 'package:dlaoshi_app/core/reader_view.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const base = ReaderViewFlagsInput();

  test('没有任何会话时是纯阅读', () {
    expect(
      readerViewFlags(base),
      const ReaderViewFlags(examActive: false, readingView: true),
    );
  });

  test('任一整页会话都算 examActive，并关掉阅读工具栏', () {
    expect(
      readerViewFlags(base.copyWith(goldenOpen: true)),
      const ReaderViewFlags(examActive: true, readingView: false),
    );
    expect(
      readerViewFlags(base.copyWith(productionOpen: true)),
      const ReaderViewFlags(examActive: true, readingView: false),
    );
    expect(readerViewFlags(base.copyWith(speedReadOpen: true)).readingView,
        isFalse);
    expect(
        readerViewFlags(base.copyWith(listenOpen: true)).examActive, isTrue);
  });

  test('背单词 / 仿写 / 生词浏览也关工具栏，但不算 examActive', () {
    expect(
      readerViewFlags(base.copyWith(studyOpen: true)),
      const ReaderViewFlags(examActive: false, readingView: false),
    );
    expect(
      readerViewFlags(base.copyWith(writingOpen: true)),
      const ReaderViewFlags(examActive: false, readingView: false),
    );
    expect(
      readerViewFlags(base.copyWith(browseAll: true)),
      const ReaderViewFlags(examActive: false, readingView: false),
    );
    expect(
      readerViewFlags(base.copyWith(browseArticle: true)),
      const ReaderViewFlags(examActive: false, readingView: false),
    );
  });

  test('每一个考试类会话都单独算数（漏一个就是工具栏挂着）', () {
    for (final input in <ReaderViewFlagsInput>[
      base.copyWith(quizSetupOpen: true),
      base.copyWith(quizQueue: true),
      base.copyWith(quizWarmup: true),
      base.copyWith(quickQueue: true),
      base.copyWith(dictQueue: true),
      base.copyWith(listenOpen: true),
      base.copyWith(backOpen: true),
      base.copyWith(goldenOpen: true),
      base.copyWith(productionOpen: true),
      base.copyWith(speedReadOpen: true),
    ]) {
      final flags = readerViewFlags(input);
      expect(flags.examActive, isTrue);
      expect(flags.readingView, isFalse);
    }
  });

  test('不开会话时 readingView 为真（哪怕其它字段是默认值）', () {
    expect(readerViewFlags(base).readingView, isTrue);
    expect(readerViewFlags(base).examActive, isFalse);
  });

  test('copyWith 不改原对象', () {
    final changed = base.copyWith(studyOpen: true);
    expect(base.studyOpen, isFalse);
    expect(changed.studyOpen, isTrue);
    expect(changed.goldenOpen, isFalse);
  });
}
