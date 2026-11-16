/// 朗读引擎真机体检：**只打印，不假装通过**。
///
/// 为什么要有这个文件：用户反馈「离线神经朗读点试听直接闪退」「Edge 在线朗读
/// 换音色听不出区别」。这两件事都是**原生侧**的事（ONNX 引擎、WebSocket 合成），
/// 桌面上的单元测试全用假实现，什么都验不出来。真机跑一遍、把异常原文打出来，
/// 才知道是模型没起来、还是合成被拒、还是静默退回了系统朗读。
///
/// 跑法（模拟器或真机都行，需要联网）：
/// ```bash
/// flutter test integration_test/tts_engine_test.dart -d emulator-5554
/// ```
/// 原生崩溃（OOM / ONNX abort）会让整个测试进程消失 —— 那本身就是结论，
/// 配合 `adb logcat` 看 tombstone。
library;

import 'dart:async';
import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_edge_tts/flutter_edge_tts.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';

import 'package:dlaoshi_app/core/tts_provider.dart';
import 'package:dlaoshi_app/services/edge_speech.dart';
import 'package:dlaoshi_app/services/kitten_speech.dart';
import 'package:dlaoshi_app/services/kokoro_speech.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  const String line = 'Reading makes perfect.';

  /// 这条路要么成功，要么抛出并打印原文 —— 不用 expect 断言成败：
  /// 这个文件的用处是「取证」，不是门禁。
  Future<void> probe(String tag, Future<void> Function() run) async {
    final watch = Stopwatch()..start();
    try {
      await run().timeout(const Duration(seconds: 90));
      // ignore: avoid_print
      print('[tts] $tag ok, ${watch.elapsedMilliseconds}ms');
    } catch (e) {
      // ignore: avoid_print
      print('[tts] $tag FAILED after ${watch.elapsedMilliseconds}ms: $e');
    }
  }

  testWidgets('离线神经朗读：模型在不在 + 起引擎 + 读一句', (tester) async {
    await tester.runAsync(() async {
      final has = await KittenSpeech.modelsPresent();
      // ignore: avoid_print
      print('[tts] kitten modelsPresent=$has');
      final speech = KittenSpeech();
      addTearDown(speech.dispose);
      await probe('kitten speak', () => speech.speak(line));
    });
  });

  testWidgets('Kokoro 离线朗读：模型在不在 + 起引擎 + 读一句', (tester) async {
    await tester.runAsync(() async {
      final has = await KokoroSpeech.modelsPresent();
      // ignore: avoid_print
      print('[tts] kokoro modelsPresent=$has');
      final speech = KokoroSpeech();
      addTearDown(speech.dispose);
      await probe('kokoro speak', () => speech.speak(line));
      final dir = await getTemporaryDirectory();
      final path = '${dir.path}/kokoro_probe.wav';
      await probe(
        'kokoro synthesizeToFile',
        () => speech.synthesizeToFile(line, path),
      );
      final file = File(path);
      // ignore: avoid_print
      print(
        '[tts] kokoro wav bytes='
        '${await file.exists() ? await file.length() : -1}',
      );
      if (await file.exists()) {
        final player = AudioPlayer();
        try {
          final done = Completer<void>();
          final sub = player.onPlayerComplete.listen((_) {
            if (!done.isCompleted) done.complete();
          });
          await player.play(DeviceFileSource(path));
          await done.future.timeout(const Duration(seconds: 30));
          // ignore: avoid_print
          print('[tts] kokoro wav playback ok');
          await sub.cancel();
        } catch (e) {
          // ignore: avoid_print
          print('[tts] kokoro wav playback FAILED: $e');
        } finally {
          await player.dispose();
        }
      }
    });
  });

  testWidgets('Edge：六个音色各合成一次，比对产物指纹', (tester) async {
    await tester.runAsync(() async {
      final dir = await getTemporaryDirectory();
      for (final voice in edgeVoiceOptions) {
        final path = '${dir.path}/probe_${voice.id}.mp3';
        final watch = Stopwatch()..start();
        try {
          final client = FlutterEdgeTts(voice: voice.id);
          final result = await client.synthesizeToFile(
            line,
            audioFilePath: path,
            prosody: const EdgeTtsProsody(rate: '+0%'),
          );
          await client.close();
          final f = File(result.audioFilePath);
          final bytes = await f.readAsBytes();
          // 便宜的指纹：长度 + 每 97 字节取一个和。同一段话不同音色
          // 合成出来的 mp3 长度/内容一定不同；完全相同说明音色没进请求。
          var sum = 0;
          for (var i = 0; i < bytes.length; i += 97) {
            sum = (sum + bytes[i]) & 0x7fffffff;
          }
          // ignore: avoid_print
          print('[tts] edge(${voice.id}) len=${bytes.length} sum=$sum '
              '${watch.elapsedMilliseconds}ms');
          await f.delete();
        } catch (e) {
          // ignore: avoid_print
          print('[tts] edge(${voice.id}) FAILED ${watch.elapsedMilliseconds}ms: $e');
        }
      }
    });
  });

  testWidgets('EdgeSpeech 那一层：换音色后 client 是不是真的重建了', (tester) async {
    await tester.runAsync(() async {
      final edge = EdgeSpeech(voice: 'en-US-AriaNeural');
      addTearDown(edge.dispose);
      // ignore: avoid_print
      print('[tts] A voiceId=${edge.voiceId}');
      await edge.setVoice('en-GB-RyanNeural');
      // ignore: avoid_print
      print('[tts] B voiceId=${edge.voiceId}');
      await probe('edge speak after setVoice', () => edge.speak(line));
    });
  });
}
