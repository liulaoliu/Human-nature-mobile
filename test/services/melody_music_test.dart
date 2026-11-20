/// [MainThemeMusic] 的合成测：音高、长度、包络、削波。
///
/// 这些断言不看「好不好听」（那个只能真机听），只钉住几条会悄悄坏掉的硬指标：
/// 音高算错、时间轴串了、峰值削顶、休止符漏音。
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:dlaoshi_app/services/melody_music.dart';
import 'package:flutter_test/flutter_test.dart';

/// 从 16 位 PCM 里取一段的过零次数，换算成频率。
///
/// 低通后的 fSaw 仍是单极性的周期信号，每周期过零 2 次，所以
/// `频率 ≈ 过零次数 / (2 × 时长)`。这比做 FFT 简单，够判「音高对没对」。
double _zeroCrossFreq(Int16List pcm, {required int from, required int count}) {
  var crossings = 0;
  var prev = pcm[from];
  for (var i = 1; i < count; i++) {
    final cur = pcm[from + i];
    if ((prev < 0 && cur >= 0) || (prev >= 0 && cur < 0)) crossings++;
    prev = cur;
  }
  return crossings / (2 * count / MainThemeMusic.sampleRate);
}

Int16List _pcmOf(Uint8List wav) {
  final bd = ByteData.view(wav.buffer, wav.offsetInBytes, wav.lengthInBytes);
  final dataBytes = bd.getUint32(40, Endian.little);
  final pcm = Int16List(dataBytes ~/ 2);
  for (var i = 0; i < pcm.length; i++) {
    pcm[i] = bd.getInt16(44 + i * 2, Endian.little);
  }
  return pcm;
}

void main() {
  group('音高换算', () {
    test('A4 = 440Hz，升八度翻倍', () {
      expect(midiToFreq(69), closeTo(440, 0.001));
      expect(midiToFreq(81), closeTo(880, 0.001));
      expect(midiToFreq(57), closeTo(220, 0.001));
    });

    test('中央 C 与用户骨架里的 G4 / C5 / G5', () {
      expect(midiToFreq(60), closeTo(261.63, 0.01));
      expect(midiToFreq(67), closeTo(392.00, 0.01)); // G4
      expect(midiToFreq(72), closeTo(523.25, 0.01)); // C5
      expect(midiToFreq(79), closeTo(783.99, 0.01)); // G5
    });
  });

  group('曲谱时间轴', () {
    test('三句之间各留 1 拍：9.5 + 1 + 14 + 1 + 11', () {
      final notes = buildThemeNotes(repeats: 1);
      final beats = notes.fold<double>(0, (sum, n) => sum + n.beats);
      expect(beats, closeTo(36.5, 1e-9));
      // 两个休止符把三句隔开。
      expect(notes.where((n) => n.isRest).length, 2);
    });

    test('重复之间再多留 1 拍，总拍数成倍且带间隔', () {
      expect(themeBeats(repeats: 2), closeTo(36.5 * 2 + 2, 1e-9));
      expect(themeBeats(repeats: 3), closeTo(36.5 * 3 + 4, 1e-9));
      expect(buildThemeNotes(repeats: 2).where((n) => n.isRest).length, 5);
    });

    test('98 BPM 下整段时长在「循环约 70 秒」这个量级', () {
      final seconds = themeSeconds();
      expect(seconds, greaterThan(60));
      expect(seconds, lessThan(75));
      expect(themeSeconds(bpm: 100), lessThan(seconds));
    });

    test('第二句的 Bb4 是 70（不是 B4 的 71）', () {
      expect(themePhraseTwo.map((n) => n.midi), contains(70));
      expect(themePhraseTwo.map((n) => n.midi), isNot(contains(71)));
    });
  });

  group('合成的波形', () {
    test('WAV 头字段与长度对得上，且长度 = 曲子 + 混响尾巴', () {
      final wav = MainThemeMusic.synthesizeWav();
      final bd = ByteData.view(wav.buffer, wav.offsetInBytes, wav.lengthInBytes);
      expect(bd.getUint32(24, Endian.little), MainThemeMusic.sampleRate);
      expect(bd.getUint16(34, Endian.little), 16);
      final dataBytes = bd.getUint32(40, Endian.little);
      expect(dataBytes, wav.length - 44);

      final expected =
          (themeSeconds() + MainThemeMusic.tailSeconds) *
          MainThemeMusic.sampleRate;
      expect((dataBytes ~/ 2) - expected, closeTo(0, 2));
    });

    test('不削波：峰值留了余量，也不是一声不响', () {
      final pcm = _pcmOf(MainThemeMusic.synthesizeWav());
      var peak = 0;
      for (final s in pcm) {
        final a = s.abs();
        if (a > peak) peak = a;
      }
      expect(peak, lessThan(32767), reason: '留 1.5dB 余量，别削顶');
      expect(peak, greaterThan(8000), reason: '合成出来得有声音');
    });

    test('休止符不发声', () {
      final pcm = _pcmOf(
        MainThemeMusic.synthesizeWav(
          notes: const <MelodyNote>[MelodyNote.rest(4)],
        ),
      );
      var peak = 0;
      for (final s in pcm) {
        final a = s.abs();
        if (a > peak) peak = a;
      }
      expect(peak, 0);
    });

    test('音高真的对：单个长音的过零频率≈移调后的基频', () {
      // 只放一个 C5（72），移调 +3 → 75（♭E5，311.13Hz）。
      final pcm = _pcmOf(
        MainThemeMusic.synthesizeWav(
          notes: const <MelodyNote>[MelodyNote(72, 4)],
        ),
      );
      // 取中段（跳过起手包络与尾巴混响），量 0.4 秒。
      final from = (MainThemeMusic.sampleRate * 0.5).round();
      final count = (MainThemeMusic.sampleRate * 0.4).round();
      final freq = _zeroCrossFreq(pcm, from: from, count: count);
      final expected = midiToFreq(72 + themeTranspose);
      expect(
        (freq - expected).abs() / expected,
        lessThan(0.08),
        reason: '量到 $freq Hz，期望约 $expected Hz',
      );
    });

    test('移调改了音高，不只是改了字节', () {
      Int16List atTranspose(int t) => _pcmOf(
        MainThemeMusic.synthesizeWav(
          notes: const <MelodyNote>[MelodyNote(72, 4)],
          transpose: t,
        ),
      );
      final from = (MainThemeMusic.sampleRate * 0.5).round();
      final count = (MainThemeMusic.sampleRate * 0.4).round();
      final low = _zeroCrossFreq(atTranspose(0), from: from, count: count);
      final high = _zeroCrossFreq(atTranspose(12), from: from, count: count);
      expect(high / low, closeTo(2.0, 0.15));
    });

    test('低通越低越闷：高频能量占比下降', () {
      double brightness(double cutoff) {
        final pcm = _pcmOf(
          MainThemeMusic.synthesizeWav(
            notes: const <MelodyNote>[MelodyNote(72, 4)],
            cutoff: cutoff,
          ),
        );
        final from = (MainThemeMusic.sampleRate * 0.5).round();
        final count = (MainThemeMusic.sampleRate * 0.4).round();
        // 用相邻样本的一阶差分当「高频含量」的代理：越亮，差分的均方根越大。
        var diffSq = 0.0;
        var sigSq = 0.0;
        for (var i = 1; i < count; i++) {
          final d = (pcm[from + i] - pcm[from + i - 1]) / 32768.0;
          final s = pcm[from + i] / 32768.0;
          diffSq += d * d;
          sigSq += s * s;
        }
        return math.sqrt(diffSq / math.max(sigSq, 1e-12));
      }

      expect(brightness(1200), lessThan(brightness(6000)));
    });

    test('loopLength 与曲子长度一致', () {
      final expected =
          (themeSeconds() + MainThemeMusic.tailSeconds) * 1000;
      expect(
        (MainThemeMusic.loopLength.inMilliseconds - expected).abs(),
        lessThan(2),
      );
    });
  });
}
