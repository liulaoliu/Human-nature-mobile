import 'dart:typed_data';

import 'package:dlaoshi_app/core/tts_audio_adts.dart';
import 'package:flutter_test/flutter_test.dart';

/// 造一个合法的 AAC-LC ADTS 帧：7 字节头 + [payload] 个 `0x5A`。
Uint8List _frame({int payload = 100, int rateIndex = 3, int channel = 1}) {
  final length = 7 + payload;
  final header = <int>[
    0xFF,
    0xF1,
    (1 << 6) | (rateIndex << 2) | (channel >> 2),
    ((channel & 0x3) << 6) | ((length >> 11) & 0x3),
    (length >> 3) & 0xFF,
    ((length & 0x7) << 5) | 0x1F,
    0xFC,
  ];
  final bytes = Uint8List(length);
  bytes.setRange(0, 7, header);
  bytes.fillRange(7, length, 0x5A);
  return bytes;
}

void main() {
  group('scanAdts', () {
    test('几个连续帧能完整走完，时长按 1024 采样/帧算', () {
      final builder = BytesBuilder();
      for (var i = 0; i < 10; i++) {
        builder.add(_frame());
      }
      final scan = scanAdts(builder.toBytes());
      expect(scan.ok, isTrue);
      expect(scan.frames.length, 10);
      expect(scan.sampleRate, 48000);
      expect(scan.channels, 1);
      expect(scan.payloadBytes, 1000);
      // 10 帧 × 1024 采样 ÷ 48000Hz ≈ 213ms
      expect(scan.durationMs, 213);
    });

    test('帧长字段被写坏（少算 1 字节）能被抓出来', () {
      // 这是旧编码器的典型症状：把编码器输出缓冲当单帧、长度算错，
      // 下一帧就会从载荷中间的某个字节被当成同步字。
      final good = _frame();
      final broken = Uint8List.fromList(good);
      // 把 frameLength 改小 1：header[3] 的低 2 位是长度高位。
      final length = good.length - 1;
      broken[3] = ((broken[1 + 2] & 0x1) << 6) |
          (((broken[2] >> 2) & 0xF) << 2) |
          0; // 保持 channel 位不变
      broken[3] = (broken[3] & 0xFC) | ((length >> 11) & 0x3);
      broken[4] = (length >> 3) & 0xFF;
      broken[5] = ((length & 0x7) << 5) | 0x1F;

      final builder = BytesBuilder()
        ..add(broken)
        ..add(_frame())
        ..add(_frame());
      final scan = scanAdts(builder.toBytes());
      expect(scan.ok, isFalse);
      expect(scan.frames.length, 1);
      expect(scan.problems.first, contains('找不到同步字'));
    });

    test('文件被截断（最后一帧长度不够）能报出来', () {
      final builder = BytesBuilder()
        ..add(_frame())
        ..add(_frame());
      final full = builder.toBytes();
      final truncated = Uint8List.sublistView(full, 0, full.length - 30);
      final scan = scanAdts(truncated);
      expect(scan.ok, isFalse);
      expect(scan.frames.length, 1);
      expect(scan.problems.first, contains('文件被截断'));
    });

    test('采样率突然变化 = 帧头错位', () {
      final builder = BytesBuilder()
        ..add(_frame(rateIndex: 3)) // 48000
        ..add(_frame(rateIndex: 6)); // 24000
      final scan = scanAdts(builder.toBytes());
      expect(scan.ok, isFalse);
      expect(scan.problems.first, contains('采样率变成 24000Hz'));
    });

    test('不是 AAC-LC 会被指出来', () {
      final good = _frame();
      final other = Uint8List.fromList(good);
      // profile 字段置 0（AAC Main）。
      other[2] = other[2] & 0x3F;
      final scan = scanAdts(other);
      expect(scan.ok, isFalse);
      expect(scan.problems.first, contains('不是 AAC-LC'));
    });

    test('空文件报「一个帧都没有」', () {
      final scan = scanAdts(Uint8List(0));
      expect(scan.ok, isFalse);
      expect(scan.problems.single, contains('一个帧都没有'));
    });

    test('尾部多出 1–2 字节填充不影响整体判定之外的信息', () {
      final builder = BytesBuilder()
        ..add(_frame())
        ..add(<int>[0x00]);
      final scan = scanAdts(builder.toBytes());
      // 有填充算问题（结构不干净），但已经扫到的帧保留。
      expect(scan.frames.length, 1);
      expect(scan.problems.single, contains('尾部剩 1 字节'));
    });

    test('summary 一句话能同时给出帧数 / 采样率 / 时长', () {
      final scan = scanAdts(_frame());
      expect(scan.summary, contains('frames=1'));
      expect(scan.summary, contains('48000Hz'));
      expect(scan.summary, contains('duration=21ms'));
    });
  });
}
