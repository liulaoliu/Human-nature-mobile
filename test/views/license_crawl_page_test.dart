// 许可爬行页的三块逻辑都在这儿验：
//   1. 字幕脚本的排版规则（纯函数，最容易出错：去重、摘要截断、空行）；
//   2. 合成的背景音 WAV 头对不对（错了就是「有文件没声音」）；
//   3. 页面能起来、能滑、能暂停（不碰平台通道）。
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/foundation.dart'
    show LicenseEntry, LicenseEntryWithLineBreaks, LicenseRegistry;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:dlaoshi_app/services/license_script.dart';
import 'package:dlaoshi_app/services/space_music.dart';
import 'package:dlaoshi_app/views/license_crawl_page.dart';

void main() {
  // 测试环境的 LicenseRegistry 基本上是空的（只够排出片头那几行），凑不满
  // 一屏就没有「继续往上爬」的余地，拖动用例会永远是 0。这里注册一批条目，
  // 让爬行页有真内容可翻。（正文会被 crawlExcerptChars 截断，所以靠条数
  // 而不是靠单条长度撑高度。）
  LicenseRegistry.addLicense(() async* {
    for (var i = 0; i < 60; i++) {
      yield LicenseEntryWithLineBreaks([
        'fixture-pkg-$i',
      ], '第 $i 条许可正文，用来撑出可以滚动的长度。');
    }
  });

  group('字幕脚本', () {
    test('开头顶上片名与总数，结尾引导去看全文', () {
      final lines = buildLicenseScript(
        [_entry('alpha', ['MIT License', 'Copyright 2026 Someone'])],
        appName: '测试App',
      );
      expect(lines.first.kind, CrawlKind.title);
      expect(lines.first.text, contains('许'));
      final flat = lines.map((l) => l.text).join('\n');
      expect(flat, contains('测试App 随包第三方组件'));
      expect(flat, contains('共 1 项'));
      expect(flat, contains('许可全文'));
    });

    test('一个包一条，重复出现的包名只留第一次', () {
      final lines = buildLicenseScript([
        _entry('alpha', ['A 的正文']),
        _entry('alpha', ['A 的第二段']),
        _entry('beta', ['B 的正文']),
      ]);
      final names = lines
          .where((l) => l.kind == CrawlKind.packageName)
          .map((l) => l.text)
          .toList();
      expect(names, ['alpha', 'beta']);
      final bodies = lines
          .where((l) => l.kind == CrawlKind.body)
          .map((l) => l.text)
          .toList();
      expect(bodies.any((b) => b.contains('A 的正文')), isTrue);
    });

    test('一条许可挂多个包名时，每个包名各占一行', () {
      final lines = buildLicenseScript([
        _entry(['alpha', 'beta'], ['同一个许可']),
      ]);
      final names = lines
          .where((l) => l.kind == CrawlKind.packageName)
          .map((l) => l.text)
          .toList();
      expect(names, ['alpha', 'beta']);
    });

    test('长正文截断并加省略号，空白折叠成单空格', () {
      final long = List.filled(400, 'word').join('\n   \n');
      final lines = buildLicenseScript([_entry('long', [long])]);
      final body = lines.firstWhere((l) => l.kind == CrawlKind.body).text;
      expect(body.length, lessThanOrEqualTo(crawlExcerptChars + 1));
      expect(body.endsWith('…'), isTrue);
      expect(body.contains('  '), isFalse, reason: '空白没折叠');
    });

    test('没有正文时给个占位，不留空行', () {
      final lines = buildLicenseScript([
        LicenseEntryWithLineBreaks(['empty'], ''),
      ]);
      final body = lines.firstWhere((l) => l.kind == CrawlKind.body).text;
      expect(body, '（没有正文）');
    });

    test('空包名被跳过，不留一行空白标题', () {
      final lines = buildLicenseScript([
        LicenseEntryWithLineBreaks(['alpha', '  '], '正文'),
      ]);
      final names = lines
          .where((l) => l.kind == CrawlKind.packageName)
          .map((l) => l.text)
          .toList();
      expect(names, ['alpha']);
    });
  });

  group('合成的背景音', () {
    test('WAV 头合法：RIFF/WAVE、16 位单声道、长度与采样数对得上', () {
      final bytes = SpaceDroneMusic.synthesizeWav();
      final bd = ByteData.view(bytes.buffer);
      String ascii(int at) => String.fromCharCodes(bytes.sublist(at, at + 4));

      expect(ascii(0), 'RIFF');
      expect(ascii(8), 'WAVE');
      expect(ascii(12), 'fmt ');
      expect(bd.getUint16(20, Endian.little), 1, reason: '不是 PCM');
      expect(bd.getUint16(22, Endian.little), 1, reason: '不是单声道');
      expect(bd.getUint32(24, Endian.little), SpaceDroneMusic.sampleRate);
      expect(bd.getUint16(34, Endian.little), 16, reason: '不是 16 位');

      final expected = SpaceDroneMusic.loopLength.inMilliseconds *
          SpaceDroneMusic.sampleRate ~/
          1000;
      final dataBytes = bd.getUint32(40, Endian.little);
      expect(dataBytes, expected * 2);
      expect(bytes.length, 44 + dataBytes);
    });

    test('首尾各有一小段静音（淡入淡出），中间不静音也不削波', () {
      final bytes = SpaceDroneMusic.synthesizeWav();
      final bd = ByteData.view(bytes.buffer);
      int at(int i) => bd.getInt16(44 + i * 2, Endian.little);

      // 头 500 个采样点：淡入刚开始，振幅很小。
      var headPeak = 0;
      for (var i = 0; i < 500; i++) {
        final v = at(i).abs();
        if (v > headPeak) headPeak = v;
      }
      expect(headPeak, lessThan(2000), reason: '淡入没生效，起手就是大声');

      // 中段：确实有声音。
      final total = SpaceDroneMusic.loopLength.inMilliseconds *
          SpaceDroneMusic.sampleRate ~/
          1000;
      final mid = total ~/ 2;
      var midPeak = 0;
      for (var i = mid; i < mid + 2000; i++) {
        final v = at(i).abs();
        if (v > midPeak) midPeak = v;
      }
      expect(midPeak, greaterThan(1000), reason: '中段是静音，合成没算对');
      expect(midPeak, lessThan(32767), reason: '削波了');
    });
  });

  group('页面', () {
    testWidgets('能起来：星空 + 字幕 + 按钮都在', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: LicenseCrawlPage(music: SilentMusic(), leadIn: Duration.zero),
        ),
      );
      await tester.pump();

      expect(find.byKey(const ValueKey<String>('crawl-back')), findsOneWidget);
      expect(
        find.byKey(const ValueKey<String>('crawl-full-text')),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey<String>('crawl-music')), findsOneWidget);
      // 星空是 CustomPaint，别退化成空白。
      expect(find.byType(CustomPaint), findsWidgets);

      // 等字幕加载完（要读 LicenseRegistry，给几轮真实异步）。
      for (var i = 0; i < 12; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)),
        );
        await tester.pump();
      }
    });

    testWidgets('暂停按钮切图标，再点回播放', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: LicenseCrawlPage(music: SilentMusic(), leadIn: Duration.zero),
        ),
      );
      for (var i = 0; i < 12; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)),
        );
        await tester.pump();
      }
      final play = find.byKey(const ValueKey<String>('crawl-play'));
      if (play.evaluate().isEmpty) return;
      await tester.tap(play);
      await tester.pump();
      expect(find.byIcon(Icons.play_arrow), findsOneWidget);
      await tester.tap(play);
      await tester.pump();
      expect(find.byIcon(Icons.pause), findsOneWidget);
    });

    // 回归：2026-11-21 的「黄色/白色异形」。
    // 根因是给整棵滚动子树套透视 Transform：Impeller 会把子树先光栅化成一张
    // 大图再采样，约三分之一的帧甩出一大块黄白梯形盖住字幕；补 filterQuality
    // 只是把那张图缩小（几何跟着错，「没占满屏」）。现在改成逐行 affine 画，
    // 这条用例锁的是「别退回去」。
    testWidgets('字幕由逐行仿射的 CrawlPainter 画，不再套透视 Transform', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: LicenseCrawlPage(music: SilentMusic(), leadIn: Duration.zero),
        ),
      );
      for (var i = 0; i < 12; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)),
        );
        await tester.pump();
      }
      final painter = _crawlPainter(tester);
      expect(painter.lines, isNotEmpty, reason: '字幕没排出来');
      expect(painter.geometry.viewport, greaterThan(0));
      expect(
        find.ancestor(
          of: find.byWidgetPredicate(
            (w) => w is CustomPaint && w.painter is CrawlPainter,
          ),
          matching: find.byType(Transform),
        ),
        findsNothing,
        reason: '透视 Transform 会招来 Impeller 的亮色梯形',
      );
      expect(find.byType(Scrollable), findsNothing, reason: '不再是滚动视图了');
    });

    testWidgets('上下拖动不会抛异常，且能改变爬行深度', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: LicenseCrawlPage(music: SilentMusic(), leadIn: Duration.zero),
        ),
      );
      for (var i = 0; i < 15; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)),
        );
        await tester.pump();
      }
      // 先暂停，否则动画自己也在动，比不出「拖动改变了深度」。
      final play = find.byKey(const ValueKey<String>('crawl-play'));
      if (play.evaluate().isNotEmpty) {
        await tester.tap(play);
        await tester.pump();
      }
      final position = _crawlPainter(tester).position;
      final before = position.value;
      await tester.drag(find.byType(LicenseCrawlPage), const Offset(0, -160));
      await tester.pump();
      expect(position.value, isNot(before));
      expect(position.value, greaterThan(before), reason: '往上拖应该往前爬');
    });
  });

  group('爬行几何', () {
    test('平面刚好铺满一屏：上沿缩放是 farScale，下沿是 cosθ', () {
      final geo = CrawlPlaneGeometry(viewport: 780);
      expect(geo.topDepth, closeTo(geo.coverPlane, 1e-6));
      expect(geo.project(-geo.topDepth), closeTo(-780, 1e-6));
      expect(geo.scaleAt(-geo.topDepth), closeTo(crawlFarScale, 1e-6));
      expect(geo.project(0), closeTo(0, 1e-9));
      expect(geo.scaleAt(0), closeTo(math.cos(crawlTiltAngle), 1e-9));
    });

    test('深度越大越靠上、越小', () {
      final geo = CrawlPlaneGeometry(viewport: 780);
      expect(
        geo.project(-geo.topDepth * 0.5),
        greaterThan(geo.project(-geo.topDepth)),
      );
      expect(
        geo.scaleAt(-geo.topDepth * 0.5),
        greaterThan(geo.scaleAt(-geo.topDepth)),
      );
    });
  });

  group('逐行绘制', () {
    test('空行只占高度，文字行深度单调递增', () {
      final laid = layoutCrawlLines(const [
        CrawlLine('标题', CrawlKind.title),
        CrawlLine('', CrawlKind.gap),
        CrawlLine('正文', CrawlKind.body),
      ], width: 400);
      expect(laid.length, 2, reason: '空行不该产生一行字');
      expect(laid[0].height, greaterThan(0));
      expect(
        laid[1].depth,
        greaterThan(laid[0].depth + laid[0].height + crawlGapHeight - 1e-9),
      );
    });

    testWidgets('可见行贴在屏幕上下沿之间，越靠下越大', (tester) async {
      final geo = CrawlPlaneGeometry(viewport: 780);
      final laid = layoutCrawlLines([
        for (var i = 0; i < 80; i++) CrawlLine('第 $i 行正文', CrawlKind.body),
      ], width: 400);
      final position = ValueNotifier<double>(0);
      final painter = CrawlPainter(
        lines: laid,
        position: position,
        geometry: geo,
      );

      final first = painter.visibleLines(const Size(400, 780));
      expect(first, isNotEmpty);
      // 第一行自己是正文，带 5dp 的上边距，所以行顶落在屏幕顶下面一点点。
      expect(first.first.y, lessThan(10), reason: '开头那行要贴着屏幕上沿');
      // 缩放取的是行中点，比行顶那一处略大一点。
      expect(first.first.scale, closeTo(crawlFarScale, 0.02));
      expect(first.last.y, greaterThan(700), reason: '一屏要铺到底');
      expect(first.last.scale, greaterThan(first.first.scale));

      // 往回看：露出来的第一行更靠后、位置更靠上（部分已经在屏幕外）。
      position.value = 300;
      final later = painter.visibleLines(const Size(400, 780));
      expect(later.first.line.depth, greaterThan(first.first.line.depth));
      expect(later.first.y, lessThan(first.first.y + 1));
    });
  });
}

/// 找到那个画字幕的 painter（全树只有一个 [CrawlPainter]）。
CrawlPainter _crawlPainter(WidgetTester tester) {
  return tester
      .widgetList<CustomPaint>(find.byType(CustomPaint))
      .map((c) => c.painter)
      .whereType<CrawlPainter>()
      .single;
}

/// 造一条最简单的许可条目。
LicenseEntry _entry(Object packages, List<String> paragraphs) {
  return LicenseEntryWithLineBreaks(
    packages is String ? [packages] : packages as List<String>,
    paragraphs.join('\n\n'),
  );
}
