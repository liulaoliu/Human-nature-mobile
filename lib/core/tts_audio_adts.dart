/// ADTS（AAC-LC）裸流的帧结构校验。
///
/// 为什么需要：2026-11-16 第一版预生成朗读写出的 `.aac` 在桌面 ffmpeg 上
/// 解码报 `Invalid data` —— 根因是**帧边界错位**（编码器把多个 access unit
/// 合并进一个输出缓冲，旧代码仍只套一个 7 字节 ADTS 头）。这种文件在手机上
/// 用 `audioplayers` 播起来「好像正常」，耳朵很难发现，但一旦拿去转码或跨设备
/// 播放就露馅。
///
/// 这个扫描器把「每个 ADTS 帧的同步字、13 位长度字段、采样率索引是否前后一致」
/// 全走一遍，任何一个字节错位都会被抓出来。纯 Dart、不碰文件系统，可以单测。
library;

import 'dart:typed_data';

/// 一帧 ADTS 的位置与长度。
class AdtsFrame {
  const AdtsFrame({
    required this.offset,
    required this.length,
    required this.payloadLength,
  });

  /// 帧起点（含 7 字节头）。
  final int offset;

  /// 整帧字节数（头 + 载荷）。
  final int length;

  /// 载荷字节数（= [length] - 7）。
  final int payloadLength;
}

/// 扫描结果。坏数据不抛异常，而是记在 [problems] 里 —— 上层要能一边播一边报。
class AdtsScan {
  const AdtsScan({
    required this.frames,
    required this.sampleRate,
    required this.channels,
    required this.problems,
  });

  final List<AdtsFrame> frames;
  final int sampleRate;
  final int channels;

  /// 人话版的问题列表；空表示这份流结构干净。
  final List<String> problems;

  bool get ok => problems.isEmpty && frames.isNotEmpty;

  /// 总时长（毫秒）。AAC-LC 每帧固定 1024 个采样。
  int get durationMs {
    if (frames.isEmpty || sampleRate <= 0) return 0;
    return frames.length * 1024 * 1000 ~/ sampleRate;
  }

  /// 所有帧载荷的总字节数（不含 ADTS 头）。
  int get payloadBytes =>
      frames.fold<int>(0, (sum, frame) => sum + frame.payloadLength);

  /// 给人看的一句话总结，日志里直接打这个。
  String get summary =>
      'frames=${frames.length} rate=${sampleRate}Hz ch=$channels '
      'duration=${durationMs}ms payload=$payloadBytes'
      '${problems.isEmpty ? '' : ' problems=${problems.length}'}';
}

const List<int> _adtsSampleRates = <int>[
  96000,
  88200,
  64000,
  48000,
  44100,
  32000,
  24000,
  22050,
  16000,
  12000,
  11025,
  8000,
  7350,
];

/// 逐帧走一遍 ADTS 裸流。
///
/// [bytes] 是落盘的 `.aac` 内容。结构坏到无法继续走时提前返回，已扫到的帧
/// 仍然保留（日志能看出「第几帧开始崩的」）。
AdtsScan scanAdts(Uint8List bytes) {
  final frames = <AdtsFrame>[];
  final problems = <String>[];
  var sampleRate = 0;
  var channels = 0;
  var offset = 0;

  while (offset < bytes.length) {
    // 尾部可能有 1–2 字节填充；不足 7 字节就收工。
    if (bytes.length - offset < 7) {
      if (bytes.length - offset > 0) {
        problems.add('尾部剩 ${bytes.length - offset} 字节，凑不出一个帧头');
      }
      break;
    }
    // 同步字：12 个 1。
    if (bytes[offset] != 0xFF || (bytes[offset + 1] & 0xF0) != 0xF0) {
      problems.add(
        '第 ${frames.length + 1} 帧在偏移 $offset 处找不到同步字 '
        '(0x${bytes[offset].toRadixString(16)}, '
        '0x${bytes[offset + 1].toRadixString(16)})',
      );
      break;
    }

    final profile = (bytes[offset + 2] >> 6) & 0x3;
    final rateIndex = (bytes[offset + 2] >> 2) & 0xF;
    final channelConfig =
        ((bytes[offset + 2] & 0x1) << 2) | ((bytes[offset + 3] >> 6) & 0x3);
    final frameLength = ((bytes[offset + 3] & 0x3) << 11) |
        (bytes[offset + 4] << 3) |
        ((bytes[offset + 5] >> 5) & 0x7);

    if (rateIndex >= _adtsSampleRates.length) {
      problems.add('第 ${frames.length + 1} 帧采样率索引 $rateIndex 越界');
      break;
    }
    final rate = _adtsSampleRates[rateIndex];
    if (frames.isEmpty) {
      sampleRate = rate;
      channels = channelConfig;
    } else if (rate != sampleRate) {
      problems.add(
        '第 ${frames.length + 1} 帧采样率变成 ${rate}Hz（前面是 ${sampleRate}Hz），'
        '说明帧头已经错位',
      );
      break;
    }
    if (profile != 1) {
      // profile 字段存的是 object type - 1，AAC-LC = 2 → 存 1。
      problems.add('第 ${frames.length + 1} 帧不是 AAC-LC（profile=$profile）');
    }
    if (frameLength < 7) {
      problems.add('第 ${frames.length + 1} 帧长度字段 $frameLength < 7，非法');
      break;
    }
    if (offset + frameLength > bytes.length) {
      problems.add(
        '第 ${frames.length + 1} 帧声明 $frameLength 字节，但只剩 '
        '${bytes.length - offset} 字节（文件被截断）',
      );
      break;
    }

    frames.add(
      AdtsFrame(
        offset: offset,
        length: frameLength,
        payloadLength: frameLength - 7,
      ),
    );
    offset += frameLength;
  }

  if (frames.isEmpty && problems.isEmpty) {
    problems.add('一个帧都没有（空文件）');
  }

  return AdtsScan(
    frames: frames,
    sampleRate: sampleRate,
    channels: channels,
    problems: problems,
  );
}
