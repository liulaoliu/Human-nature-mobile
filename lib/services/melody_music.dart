/// 《Some Unknown Main Theme》——按用户给的音符骨架合成的一段主题曲。
///
/// 规格来自用户（2026-11-20）：C 大调三句、四分音符为一拍、乐句间留 1 拍，
/// 移调 +2~+4 半音、96–100 BPM，音色是 fSaw + 低通 + 轻混响（明确不要八音盒）。
///
/// **和 [SpaceDroneMusic] 的区别**：那个是几个正弦叠出来的无旋律铺底，这个是
/// 有音高有节奏的曲子。许可页现在（2026-11-20 起）默认放的是随包的
/// `AssetMusic`（用户给的音频文件），这一首留作合成兜底 —— 换素材时手里还有
/// 一段法律上干净的替代品，改 `license_crawl_page.dart` 里 `widget.music ?? ...`
/// 那一行就能换回来。
///
/// 合成全程离线算采样点（不用 AudioTrack 逐音源调度），所以「每个音符独立
/// 音源实例」这条要求在这里体现为：**每个音符从自己的相位 0 起算、带自己的
/// 包络**，绝不共用一个振荡器反复改频率（那样会有相位跳变的咔哒声）。
library;

import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';

import 'space_music.dart' show CrawlMusic;

/// 一个音符：MIDI 音高 + 时值（拍）。`midi == -1` 表示休止。
class MelodyNote {
  const MelodyNote(this.midi, this.beats);

  /// 休止符（乐句之间那一拍）。
  const MelodyNote.rest(this.beats) : midi = -1;

  final int midi;
  final double beats;

  bool get isRest => midi < 0;

  @override
  String toString() => isRest ? 'rest($beats)' : 'note($midi, $beats)';
}

/// 速度。用户给的区间是 96–100，取中音 98。
const double themeBpm = 98;

/// 移调半音数。用户建议 +2~+4，取 +3：C 大调骨架升到 ♭E 大调，弦乐味更足，
/// 又没高到发尖。
const int themeTranspose = 3;

/// 低通截止频率。用户要求 2–3kHz，取 2.6kHz。
const double themeCutoffHz = 2600;

/// 整段重复几遍。
///
/// 用户写的是「三句约 30–35 秒，重复两遍≈70 秒」，但按 98 BPM 算，三句其实
/// 只有 36.5 拍 ≈ 22.3 秒（一拍 = 60/98 = 0.612 秒），两遍才 45 秒。这里以
/// 「循环 ≈70 秒」为准取三遍（109.5 拍 ≈ 67 秒），速度仍按用户给的 98 BPM。
/// 想要两遍就把这个常量改成 2。
const int themeRepeats = 3;

/// 第一句（9.5 拍）。
const List<MelodyNote> themePhraseOne = <MelodyNote>[
  MelodyNote(67, 0.5), // G4
  MelodyNote(67, 0.5),
  MelodyNote(67, 0.5),
  MelodyNote(72, 1.5), // C5
  MelodyNote(79, 1.5), // G5
  MelodyNote(76, 0.5), // E5
  MelodyNote(72, 1.5), // C5
  MelodyNote(79, 1.5), // G5
  MelodyNote(77, 0.5), // F5
  MelodyNote(74, 0.5), // D5
  MelodyNote(72, 0.5), // C5
];

/// 第二句（14 拍）：前半与第一句相同，后半落到 Bb4–F4–D4 再挂回 G4。
///
/// Bb4 是 MIDI 70（不是 B4 的 71）。用户提示「若原曲是 B4 需改」—— 这里保留
/// ♭7，因为它在 C 大调里是特征音（混合利底亚色彩），比 B4 更像这类太空主题。
/// 真要改就这一个数字。
const List<MelodyNote> themePhraseTwo = <MelodyNote>[
  MelodyNote(67, 0.5), // G4
  MelodyNote(67, 0.5),
  MelodyNote(67, 0.5),
  MelodyNote(72, 1.5), // C5
  MelodyNote(79, 1.5), // G5
  MelodyNote(76, 0.5), // E5
  MelodyNote(72, 1.5), // C5
  MelodyNote(79, 1.5), // G5
  MelodyNote(77, 0.5), // F5
  MelodyNote(74, 0.5), // D5
  MelodyNote(70, 1.5), // Bb4
  MelodyNote(65, 1.5), // F4
  MelodyNote(62, 0.5), // D4
  MelodyNote(67, 1.5), // G4
];

/// 第三句（11 拍）：收束到 C5 长音。
///
/// 用户提示「第三句收束可能应为 F5–E5–C5」。这里保留骨架写的 F5–D5–C5（D5 是
/// 经过音，落到 C 更稳）；要试另一个版本，把倒数第二个音 74 改成 76 即可。
const List<MelodyNote> themePhraseThree = <MelodyNote>[
  MelodyNote(67, 0.5), // G4
  MelodyNote(67, 0.5),
  MelodyNote(67, 0.5),
  MelodyNote(72, 1.5), // C5
  MelodyNote(79, 1.5), // G5
  MelodyNote(76, 0.5), // E5
  MelodyNote(72, 1.5), // C5
  MelodyNote(79, 1.5), // G5
  MelodyNote(77, 0.5), // F5
  MelodyNote(74, 0.5), // D5
  MelodyNote(72, 2.0), // C5
];

/// 拼出整段：三句之间各留 1 拍，段落之间再多留 1 拍（换气）。
List<MelodyNote> buildThemeNotes({int repeats = themeRepeats}) {
  const List<MelodyNote> phraseGap = <MelodyNote>[MelodyNote.rest(1)];
  const List<MelodyNote> repeatGap = <MelodyNote>[MelodyNote.rest(2)];
  final out = <MelodyNote>[];
  for (var pass = 0; pass < repeats; pass++) {
    if (pass > 0) out.addAll(repeatGap);
    out
      ..addAll(themePhraseOne)
      ..addAll(phraseGap)
      ..addAll(themePhraseTwo)
      ..addAll(phraseGap)
      ..addAll(themePhraseThree);
  }
  return out;
}

/// 整段多少拍（不含尾巴的混响余响）。
double themeBeats({int repeats = themeRepeats}) {
  var beats = 0.0;
  for (final note in buildThemeNotes(repeats: repeats)) {
    beats += note.beats;
  }
  return beats;
}

/// 整段多少秒（不含混响尾巴）。
double themeSeconds({double bpm = themeBpm, int repeats = themeRepeats}) =>
    themeBeats(repeats: repeats) * 60 / bpm;

/// 合成出来的主题曲。用法与 [SpaceDroneMusic] 完全一致。
class MainThemeMusic implements CrawlMusic {
  MainThemeMusic({this.volume = 0.40});

  /// 播放音量。用户给的区间是 0.3–0.5，取 0.40：许可页的字幕要读，音乐不能抢。
  final double volume;

  /// 采样率。22050 够用（最高音 G5 移调后约 940Hz，谐波全在 2.6kHz 以内）。
  static const int sampleRate = 22050;

  /// 混响尾巴多长。曲子结束后留这么长的余响，再接回开头。
  static const double tailSeconds = 2.4;

  AudioPlayer? _player;
  String? _path;

  /// 整段循环一次多长（含混响尾巴）。
  static Duration get loopLength => Duration(
    milliseconds: ((themeSeconds() + tailSeconds) * 1000).round(),
  );

  /// 把 WAV 写到缓存目录（只写一次），返回路径。
  static Future<String> prepare() async {
    final dir = Directory('${Directory.systemTemp.path}/dlaoshi_crawl');
    if (!await dir.exists()) await dir.create(recursive: true);
    final file = File('${dir.path}/main_theme.wav');
    if (await file.exists() && await file.length() > 1024) return file.path;
    await file.writeAsBytes(synthesizeWav(), flush: true);
    return file.path;
  }

  /// 合成整段 WAV（44 字节头 + 16 位单声道 PCM）。
  ///
  /// 公开是为了能单测：不需要播，只需要验音高、长度、有没有削波。
  static Uint8List synthesizeWav({
    List<MelodyNote>? notes,
    double bpm = themeBpm,
    int transpose = themeTranspose,
    double cutoff = themeCutoffHz,
  }) {
    final score = notes ?? buildThemeNotes();
    var beats = 0.0;
    for (final note in score) {
      beats += note.beats;
    }
    final bodySeconds = beats * 60 / bpm;
    final total = ((bodySeconds + tailSeconds) * sampleRate).round();
    final mix = Float64List(total);

    final secondsPerBeat = 60 / bpm;
    var at = 0.0;
    for (final note in score) {
      final dur = note.beats * secondsPerBeat;
      if (!note.isRest) {
        // 每个音符独立起算（自己的相位 0 + 自己的包络），对应「独立音源实例」。
        _renderNote(
          mix,
          startSample: (at * sampleRate).round(),
          durSeconds: dur,
          frequency: midiToFreq(note.midi + transpose),
          cutoff: cutoff,
        );
      }
      at += dur;
    }

    // fSaw 的「唇齿感」靠谐波滚降已经有了，这里只补一层轻混响把音符糊到
    // 一个空间里，不然三句听起来像电子琴练习。
    final wet = _reverb(mix);
    final out = Int16List(total);
    var peak = 0.0;
    for (var i = 0; i < total; i++) {
      final v = mix[i] * 0.78 + wet[i] * 0.30;
      final a = v.abs();
      if (a > peak) peak = a;
      out[i] = (v.clamp(-1.0, 1.0) * 32767).round();
    }
    // 峰值归一：留 1.5dB 余量，宁小不削。
    if (peak > 0.85) {
      final gain = 0.85 / peak;
      for (var i = 0; i < total; i++) {
        out[i] = (out[i] * gain).round();
      }
    }
    // 接缝：最后 0.12 秒淡出，循环回开头不会有咔哒。
    final fadeOut = (0.12 * sampleRate).round();
    for (var i = 0; i < fadeOut && i < total; i++) {
      final g = 1 - i / fadeOut;
      final idx = total - 1 - i;
      out[idx] = (out[idx] * g).round();
    }

    return wrapWav(out, sampleRate: sampleRate);
  }

  /// 把一个音符叠加进混音缓冲。
  ///
  /// 波形：fSaw。用**加性合成**逐谐波叠加，第 k 次谐波幅度
  /// `(1/k) / (1 + (k·f / cutoff)²)` —— 前半是锯齿的 1/k 谱，后半是一阶
  /// 低通的 12dB/oct 滚降，两者合在一起正好是「fSaw 过一个 2.6kHz 低通」，
  /// 还顺手把超过奈奎斯特的谐波限制掉了，不会有混叠。
  static void _renderNote(
    Float64List mix, {
    required int startSample,
    required double durSeconds,
    required double frequency,
    required double cutoff,
  }) {
    // 包络：起手 20ms（避免咔哒）、衰减到 0.72、收尾按音符长度给 0.35s 但
    // 不超过自身长度的一半（短音符不能被包络吃光）。
    const attack = 0.020;
    const decay = 0.12;
    const sustain = 0.72;
    final release = math.min(0.35, durSeconds * 0.5);
    final hold = durSeconds - release;

    final harmonics = math.max(1, math.min(24, (cutoff / frequency).floor()));
    final amps = Float64List(harmonics + 1);
    var norm = 0.0;
    for (var k = 1; k <= harmonics; k++) {
      final ratio = k * frequency / cutoff;
      final a = (1.0 / k) / (1.0 + ratio * ratio);
      amps[k] = a;
      norm += a;
    }
    if (norm <= 0) return;
    final invNorm = 1.0 / norm;

    final durSamples = ((durSeconds + release) * sampleRate).round();
    final w = 2 * math.pi * frequency / sampleRate;
    for (var n = 0; n < durSamples; n++) {
      final idx = startSample + n;
      if (idx >= mix.length) break;
      final t = n / sampleRate;
      double env;
      if (t < attack) {
        env = t / attack;
      } else if (t < attack + decay) {
        env = 1 - (1 - sustain) * (t - attack) / decay;
      } else if (t < durSeconds) {
        env = sustain;
      } else {
        final k = ((t - hold) / math.max(release, 1e-6)).clamp(0.0, 1.0);
        env = sustain * (1 - k);
      }
      if (env <= 0) continue;
      // 相位按「从本音符起点算」推进；每个谐波用 k*w 的倍数，起始相位都是 0。
      final phase = w * n;
      var v = 0.0;
      for (var k = 1; k <= harmonics; k++) {
        v += amps[k] * _sine(k * phase);
      }
      mix[idx] += v * invNorm * env;
    }
  }

  /// 正弦查表（4096 点 + 线性插值）。比逐点 `math.sin` 快一个数量级 ——
  /// 整段 70 秒要算上千万次，手机上直接调 sin 会拖到秒级。
  static final Float64List _sineTable = () {
    const size = 4096;
    final table = Float64List(size + 1);
    for (var i = 0; i <= size; i++) {
      table[i] = math.sin(2 * math.pi * i / size);
    }
    return table;
  }();

  static double _sine(double radians) {
    const size = 4096;
    final pos = (radians / (2 * math.pi)) % 1.0;
    final x = (pos < 0 ? pos + 1 : pos) * size;
    final i = x.floor();
    final frac = x - i;
    final a = _sineTable[i];
    final b = _sineTable[i + 1];
    return a + (b - a) * frac;
  }

  /// 简化的 Schroeder 混响：4 个梳状滤波器并联 + 2 个全通滤波器串联。
  ///
  /// 延迟长度按 44.1kHz 的经典 freeverb 调参表折半（本文件用 22050Hz），
  /// 得到的空间尺度才一样。
  static Float64List _reverb(Float64List dry, {double roomSize = 0.78, double damp = 0.30}) {
    const combTunings = <int>[778, 711, 638, 594];
    const allpassTunings = <int>[220, 112];
    final total = dry.length;
    final wet = Float64List(total);

    for (final delay in combTunings) {
      final buffer = Float64List(delay);
      var idx = 0;
      var store = 0.0;
      for (var i = 0; i < total; i++) {
        final output = buffer[idx];
        store = output * (1 - damp) + store * damp;
        buffer[idx] = dry[i] + store * roomSize;
        wet[i] += output * 0.25;
        idx++;
        if (idx >= delay) idx = 0;
      }
    }

    for (final delay in allpassTunings) {
      final buffer = Float64List(delay);
      var idx = 0;
      for (var i = 0; i < total; i++) {
        final buffered = buffer[idx];
        final output = buffered - wet[i];
        buffer[idx] = wet[i] + buffered * 0.5;
        wet[i] = output;
        idx++;
        if (idx >= delay) idx = 0;
      }
    }
    return wet;
  }

  @override
  Future<void> start() async {
    if (_player != null) {
      await _player!.resume();
      return;
    }
    _path ??= await prepare();
    final player = AudioPlayer(playerId: 'license_crawl_theme');
    await player.setReleaseMode(ReleaseMode.loop);
    await player.setVolume(volume);
    await player.play(DeviceFileSource(_path!));
    _player = player;
  }

  @override
  Future<void> stop() async {
    await _player?.pause();
  }

  @override
  Future<void> dispose() async {
    final player = _player;
    _player = null;
    await player?.dispose();
  }
}

/// MIDI 音高 → 频率。用户给的公式：440 × 2^((m-69)/12)。
double midiToFreq(int midi) => 440 * math.pow(2, (midi - 69) / 12).toDouble();

/// 套一层最小的 RIFF/WAVE 头（16 位单声道 PCM）。
Uint8List wrapWav(Int16List pcm, {int sampleRate = 22050}) {
  final dataBytes = pcm.length * 2;
  final out = Uint8List(44 + dataBytes);
  final bd = ByteData.view(out.buffer);

  void ascii(int offset, String s) {
    for (var i = 0; i < s.length; i++) {
      out[offset + i] = s.codeUnitAt(i);
    }
  }

  ascii(0, 'RIFF');
  bd.setUint32(4, 36 + dataBytes, Endian.little);
  ascii(8, 'WAVE');
  ascii(12, 'fmt ');
  bd.setUint32(16, 16, Endian.little); // fmt 块长度
  bd.setUint16(20, 1, Endian.little); // PCM
  bd.setUint16(22, 1, Endian.little); // 单声道
  bd.setUint32(24, sampleRate, Endian.little);
  bd.setUint32(28, sampleRate * 2, Endian.little); // 每秒字节数
  bd.setUint16(32, 2, Endian.little); // 块对齐
  bd.setUint16(34, 16, Endian.little); // 位深
  ascii(36, 'data');
  bd.setUint32(40, dataBytes, Endian.little);
  for (var i = 0; i < pcm.length; i++) {
    bd.setInt16(44 + i * 2, pcm[i], Endian.little);
  }
  return out;
}
