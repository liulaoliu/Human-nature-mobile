/// 录音实现：`record` 包，录到临时文件。
///
/// 为什么临时文件在 `stop()` 之后还留一会儿：用户要能当场回放自己刚读的那一遍
/// —— 这是 2026-11-12 报上来的问题（「录音后不能播放」）。所以 `stop()` 只停不删，
/// 再由上层调 `clearTake()`（换句 / 放弃 / 退出页面 / 下次开录时）删掉。
/// **音频绝不上传、不进存储**，跟读记录里只有时长。
library;

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

import '../core/ports.dart';

/// 基于 `record` 的录音器。
class DeviceRecorder implements RecorderPort {
  DeviceRecorder({this.encoder = AudioEncoder.wav});

  /// `record` 的实例**懒创建**：`AudioRecorder()` 一构造就去碰平台通道
  /// （`com.llfbandit.record/messages` 的 `create`），widget 测试里没有插件实现
  /// 会直接抛 `MissingPluginException`。而这个类在「只打开跟读页、还没录音」
  /// 的时候完全不需要平台能力，所以拖到真正要录的时候再建。
  AudioRecorder? _recorderInstance;

  AudioRecorder get _recorder => _recorderInstance ??= AudioRecorder();

  /// 输出编码。默认 wav（无损、各平台都认；临时文件听完就删）。
  final AudioEncoder encoder;

  String? _path;
  DateTime? _startedAt;
  bool _recording = false;

  /// 当前临时文件路径（排错用；正常流程不用关心）。
  String? get path => _path;

  @override
  String? get lastPath => _path;

  bool get isRecording => _recording;

  @override
  Future<bool> ensurePermission() async {
    try {
      return await _recorder.hasPermission();
    } catch (e) {
      debugPrint('麦克风权限检查失败：$e');
      return false;
    }
  }

  Future<String> _tempPath() async {
    final dir = await getTemporaryDirectory();
    final stamp = DateTime.now().millisecondsSinceEpoch;
    return '${dir.path}/shadowing-$stamp.${_ext()}';
  }

  String _ext() => switch (encoder) {
        AudioEncoder.wav => 'wav',
        AudioEncoder.flac => 'flac',
        AudioEncoder.opus => 'opus',
        _ => 'm4a',
      };

  @override
  Future<void> start() async {
    if (_recording) return;
    // 上一遍的临时文件先删掉，免得攒一堆（每次只留最后一遍）。
    await clearTake();
    final path = await _tempPath();
    await _recorder.start(
      RecordConfig(
        encoder: encoder,
        sampleRate: 16000,
        numChannels: 1,
        // 三个都关掉：跟读要听的是「你自己读得怎么样」，
        // 降噪会把气口和连读一起抹平，反而不利于发现问题。
        autoGain: false,
        echoCancel: false,
        noiseSuppress: false,
      ),
      path: path,
    );
    _path = path;
    _startedAt = DateTime.now();
    _recording = true;
  }

  @override
  Future<double> amplitude() async {
    if (!_recording) return 0;
    try {
      final amp = await _recorder.getAmplitude();
      // record 给的是 dBFS（负值），换算成 0–1 的线性电平：
      // -60dB 当静音，0dB 当满格。
      final db = amp.current;
      if (!db.isFinite) return 0;
      return ((db + 60) / 60).clamp(0.0, 1.0);
    } catch (e) {
      debugPrint('取电平失败：$e');
      return 0;
    }
  }

  @override
  Future<int?> stop() async {
    if (!_recording) return null;
    _recording = false;
    final startedAt = _startedAt;
    _startedAt = null;
    try {
      await _recorder.stop();
    } catch (e) {
      debugPrint('停止录音失败：$e');
    }
    // 临时文件留着给回放用，由 `clearTake()` 删。
    if (startedAt == null) return null;
    // 时长按「从 start 到现在」算：record 不直接给时长，
    // 而这个数只用于「读得快/慢」的判断，秒级误差无所谓。
    return DateTime.now().difference(startedAt).inMilliseconds;
  }

  @override
  Future<void> clearTake() => _deleteTemp();

  @override
  Future<void> discard() async {
    final wasRecording = _recording;
    _recording = false;
    _startedAt = null;
    final rec = _recorderInstance;
    // 没建过实例就说明从没录过，别为了 cancel 去碰平台通道。
    if (rec != null && wasRecording) {
      try {
        await rec.cancel();
      } catch (e) {
        debugPrint('放弃录音失败：$e');
      }
    }
    await _deleteTemp();
  }

  Future<void> _deleteTemp() async {
    final path = _path;
    _path = null;
    if (path == null) return;
    try {
      final f = File(path);
      if (await f.exists()) await f.delete();
    } catch (e) {
      debugPrint('删临时录音失败：$e');
    }
  }

  /// 页面销毁时调。
  Future<void> dispose() async {
    await discard();
    final rec = _recorderInstance;
    if (rec == null) return;
    _recorderInstance = null;
    try {
      await rec.dispose();
    } catch (e) {
      debugPrint('释放录音器失败：$e');
    }
  }
}
