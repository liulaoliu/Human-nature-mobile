/// 许可爬行页的背景铺底音。
///
/// **不是《星球大战》原声**——那段音乐有版权，不能随包分发，也不能拿它的旋律
/// 做「听感相似」的仿写。这里是自己合成的一段太空氛围：几个低频正弦叠在一起
/// 缓慢呼吸，听感是「空旷、悬停」，跟画面配得上，法律上也干净。
///
/// 做法：启动时才合成一个 24 秒的 WAV 落到缓存目录，然后循环播放。合成是
/// 纯算术（52 万个采样点），手机上大约几十毫秒，所以不预先生成、也不进仓库。
///
/// 想换成自己的音频：把 [SpaceDroneMusic.assetPath] 改成你的 asset 路径，
/// 并把 [SpaceDroneMusic.prepare] 里的合成换成 `rootBundle.load` 即可；页面
/// 那边不用动。
library;

import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';

/// 背景音的抽象：页面只认这三个方法，测试里给一个空实现就不会碰平台通道。
abstract class CrawlMusic {
  Future<void> start();

  Future<void> stop();

  Future<void> dispose();
}

/// 什么也不做的实现，给测试和「音乐关掉」用。
class SilentMusic implements CrawlMusic {
  const SilentMusic();

  @override
  Future<void> start() async {}

  @override
  Future<void> stop() async {}

  @override
  Future<void> dispose() async {}
}

/// 合成出来的太空铺底音。
class SpaceDroneMusic implements CrawlMusic {
  SpaceDroneMusic({this.volume = 0.55});

  /// 播放音量。这是背景，不该盖过用户在想的事，但也不能小到听不见
  /// （0.35 在真机上配合 220–440Hz 的主音偏轻，抬到 0.55）。
  final double volume;

  /// 循环一次多长。
  static const Duration loopLength = Duration(seconds: 24);

  /// 采样率。22050 对这种低频素材足够，文件只有 44.1kHz 的一半。
  static const int sampleRate = 22050;

  AudioPlayer? _player;
  String? _path;

  /// 把 WAV 写到缓存目录（只写一次），返回路径。
  static Future<String> prepare() async {
    final dir = Directory('${Directory.systemTemp.path}/dlaoshi_crawl');
    if (!await dir.exists()) await dir.create(recursive: true);
    final file = File('${dir.path}/space_drone.wav');
    if (await file.exists() && await file.length() > 1024) return file.path;
    final bytes = synthesizeWav();
    await file.writeAsBytes(bytes, flush: true);
    return file.path;
  }

  /// 合成整段 WAV（44 字节头 + 16 位单声道 PCM）。
  ///
  /// 公开是为了能单测：不需要播，只需要验「长度对得上、没有削波」。
  static Uint8List synthesizeWav() {
    final samples = loopLength.inMilliseconds * sampleRate ~/ 1000;
    final pcm = Int16List(samples);

    // 频段分布（这条是踩出来的）：
    //   手机扬声器基本发不出 200Hz 以下 —— 最早只写 55/82.5/110Hz，真机上
    //   图标是「音量开」但一点声都听不见（用户 2026-11-20 报的）。所以低频只
    //   留一点点当「体感」，出声主力抬到 220/330/440Hz。
    //   55Hz 打底，82.5Hz 给厚度，110Hz 带 +0.5Hz 失谐造缓慢拍频；
    //   220Hz 与 330Hz 各带自己的慢速幅度起伏（相位错开），听感像远处和声在飘。
    const a1 = 55.0;
    const e2 = 82.5;
    const a2 = 110.0;
    const detune = 0.5;
    const a3 = 220.0;
    const e4 = 330.0;
    const a4 = 440.0;

    for (var i = 0; i < samples; i++) {
      final t = i / sampleRate;
      // 12 秒一轮的呼吸，正好是 24 秒循环的两半，接缝处相位对齐。
      // 下限不能压到接近 0：最早写 `0.55 + 0.45·sin`，谷底只剩 10%，那两秒
      // 听感是「声音没了」，单测也在谷底量到 761（低于「不是静音」的阈值）。
      final swell = 0.70 + 0.30 * math.sin(2 * math.pi * t / 12 - math.pi / 2);
      // 高两个八度的音各自缓慢起伏，两个周期都是 24 的约数，循环接得回去。
      final driftA = 0.5 + 0.5 * math.sin(2 * math.pi * t / 8);
      final driftB = 0.5 + 0.5 * math.sin(2 * math.pi * t / 24 + 1.9);
      var v = 0.0;
      v += 0.10 * math.sin(2 * math.pi * a1 * t);
      v += 0.06 * math.sin(2 * math.pi * e2 * t + 0.6);
      v += 0.05 * math.sin(2 * math.pi * a2 * t);
      v += 0.03 * math.sin(2 * math.pi * (a2 + detune) * t);
      v += 0.09 * driftA * math.sin(2 * math.pi * a3 * t);
      v += 0.06 * driftB * math.sin(2 * math.pi * e4 * t + 0.4);
      v += 0.03 * driftA * math.sin(2 * math.pi * a4 * t + 2.1);
      v *= swell;

      // 首尾各 1.5 秒淡入淡出：循环接缝处不会有咔哒声。
      const fade = 1.5;
      final at = t;
      final left = loopLength.inMilliseconds / 1000.0 - t;
      if (at < fade) v *= at / fade;
      if (left < fade) v *= (left / fade).clamp(0.0, 1.0);

      pcm[i] = (v.clamp(-1.0, 1.0) * 32767).round();
    }

    return _wrapWav(pcm);
  }

  /// 套一层最小的 RIFF/WAVE 头。
  static Uint8List _wrapWav(Int16List pcm) {
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

  @override
  Future<void> start() async {
    if (_player != null) {
      await _player!.resume();
      return;
    }
    _path ??= await prepare();
    final player = AudioPlayer(playerId: 'license_crawl_drone');
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
