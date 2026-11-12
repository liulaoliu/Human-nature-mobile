/// 热重载守护：前台挂着 `flutter run`，我在后台改完代码写一个触发文件就重载。
///
/// 为什么需要它：`flutter run` 靠 **stdin** 收 'r'（热重载）/ 'R'（热重启）。
/// Windows 上没有 POSIX 的 SIGUSR1（`--pid-file` 那套只在 Unix 有效），
/// 而后台任务拿不到交互式 stdin，所以由本进程持有子进程的 stdin 并代发。
///
/// 用法：
///   dart run tool/hmr_daemon.dart [deviceId]
///   然后 `echo r > .hmr-trigger` 触发热重载；`echo R > .hmr-trigger` 触发热重启。
///
/// 只对 Dart 代码改动有效。改 pubspec（新依赖）、AndroidManifest、assets 之后
/// 热重载不会生效，必须重新 `flutter run`。
///
/// 日志写 `build/hmr.log`（原始字节，UTF-8），尾部就是最近一次重载结果。
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

const String _triggerName = '.hmr-trigger';

Future<void> main(List<String> args) async {
  final device = args.isNotEmpty ? args[0] : 'emulator-5554';
  final root = Directory.current.path;
  final trigger = File('$root/$_triggerName');
  final log = File('$root/build/hmr.log');

  await log.parent.create(recursive: true);
  await log.writeAsString('');

  final logHandle = log.openSync(mode: FileMode.append);

  void say(String line) {
    final stamp = DateTime.now().toIso8601String().substring(11, 19);
    // 同步写：日志量小，不会拖慢 flutter；异步 sink 在 Windows 上
    // 一旦 flush 就会「bound to a stream」，别再用 openWrite。
    logHandle.writeStringSync('[$stamp] $line\n');
  }

  say('启动 flutter run -d $device');
  final proc = await Process.start(
    r'I:\tools\flutter\bin\flutter.bat',
    <String>['run', '-d', device, '--debug', '--no-pub'],
    workingDirectory: root,
    runInShell: true,
  );

  var ready = false;

  void onChunk(List<int> bytes) {
    // flutter 输出是 UTF-8；写原始字节，免得经过系统代码页转一次变成乱码。
    logHandle.writeFromSync(bytes);
    final text = utf8.decode(bytes, allowMalformed: true);
    if (!ready &&
        (text.contains('Flutter run key commands') ||
            text.contains('A Dart VM Service'))) {
      ready = true;
      say('已就绪：可以热重载了');
    }
  }

  proc.stdout.listen(onChunk);
  proc.stderr.listen(onChunk);

  var lastStamp = trigger.existsSync() ? trigger.lastModifiedSync() : null;
  Timer.periodic(const Duration(milliseconds: 400), (timer) {
    if (!trigger.existsSync()) return;
    final stat = trigger.statSync();
    if (lastStamp != null && !stat.modified.isAfter(lastStamp!)) return;
    lastStamp = stat.modified;
    final raw = trigger.readAsStringSync().trim();
    if (raw.isEmpty) return;
    final cmd = raw[0];
    if (cmd == 'r' || cmd == 'R') {
      if (!ready) {
        say('还没就绪，丢掉这次 $cmd');
        return;
      }
      proc.stdin.write(cmd);
      say(cmd == 'R' ? '→ 热重启' : '→ 热重载');
    } else if (cmd == 'q') {
      say('→ 退出');
      proc.stdin.write('q');
      timer.cancel();
    }
  });

  final code = await proc.exitCode;
  say('flutter run 退出，code=$code');
  logHandle.closeSync();
  if (trigger.existsSync()) trigger.deleteSync();
  exit(code);
}
