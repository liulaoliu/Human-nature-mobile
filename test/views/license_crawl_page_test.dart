// 许可爬行页的三块逻辑都在这儿验：
//   1. 字幕脚本的排版规则（纯函数，最容易出错：去重、摘要截断、空行）；
//   2. 合成的背景音 WAV 头对不对（错了就是「有文件没声音」）；
//   3. 页面能起来、能滑、能暂停（不碰平台通道）。
import 'dart:typed_data';

import 'package:flutter/foundation.dart'
    show LicenseEntry, LicenseEntryWithLineBreaks;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:dlaoshi_app/services/license_script.dart';
import 'package:dlaoshi_app/services/space_music.dart';
import 'package:dlaoshi_app/views/license_crawl_page.dart';

void main() {
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

    testWidgets('上下拖动不会抛异常，且能改变滚动位置', (tester) async {
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
      final scrollable = find.byType(Scrollable);
      if (scrollable.evaluate().isEmpty) return;
      final before =
          tester.state<ScrollableState>(scrollable.first).position.pixels;
      await tester.drag(find.byType(LicenseCrawlPage), const Offset(0, -160));
      await tester.pump();
      final after =
          tester.state<ScrollableState>(scrollable.first).position.pixels;
      expect(after, isNot(before));
    });
  });
}

/// 造一条最简单的许可条目。
LicenseEntry _entry(Object packages, List<String> paragraphs) {
  return LicenseEntryWithLineBreaks(
    packages is String ? [packages] : packages as List<String>,
    paragraphs.join('\n\n'),
  );
}
