// 真机（模拟器）上跑 AI 真请求 —— 验的是**网络栈**，不是模型回答质量。
//
// 桌面 `flutter test` 里 AI 客户端只被 `MockClient` 验过，从没在手机上真发过
// 一个 HTTPS 请求。而手机侧最容易出问题、桌面又测不出来的正好是这一段：
// DNS、TLS 证书链、系统代理、明文/加密流量策略（`usesCleartextTraffic`）。
//
// 所以这一例分两段，**第一段不需要真 key**：
//   1. 用一个明显假的 key 真发一次请求。服务端会回 401，客户端把它归成
//      `AiErrorKind.unauthorized`。只要拿到的是 unauthorized 而不是 network，
//      就说明 DNS + TLS + 证书链 + 代理 + 出网全都通 —— 这是本轮要验的东西。
//   2. 有真 key 时（`--dart-define=DLAOSHI_E2E_KEY=...`）跑完整链路：
//      真请求 → 拿到模型正文 → 断言非空。
//
// 跑法（要先起模拟器）：
//   flutter test integration_test/ai_network_test.dart -d emulator-5554
//   # 带真 key（key 从命令行传，不落文件、不进仓库）：
//   flutter test integration_test/ai_network_test.dart -d emulator-5554 `
//     --dart-define=DLAOSHI_E2E_KEY=sk-xxxx
//
// 说明：集成测试跑在**设备**上，宿主机的环境变量传不进去，所以这里读的是
// `--dart-define`（`String.fromEnvironment`），和 test/e2e 那套读
// `Platform.environment` 的区别就在这里。
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:dlaoshi_app/core/ai_config.dart';
import 'package:dlaoshi_app/services/ai_client.dart';

/// 从命令行传进来的真 key；没有就是空串（第一段不需要它）。
const String _realKey = String.fromEnvironment('DLAOSHI_E2E_KEY');

/// 明显假的 key：格式像样但不可能是真的，服务端会回 401。
const String _fakeKey = 'sk-dlaoshi-network-probe-not-a-real-key';

AiConfig _config(String key) => AiConfig(
      apiKey: key,
      baseUrl: defaultAiBaseUrl,
      model: defaultAiModel,
    );

const String _prompt = '只回复两个字：通了';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    '[net] 真机上 DNS / TLS / 出网都通：假 key 拿到的是 401，不是网络错误',
    (WidgetTester tester) async {
      // 真发网络请求要走真实时钟，不套 runAsync 会被假时钟卡死。
      await tester.runAsync(() async {
        final client = AiClient(timeout: const Duration(seconds: 30));
        addTearDown(client.close);

        final sw = Stopwatch()..start();
        final reply = await client.complete(_config(_fakeKey), _prompt);
        sw.stop();

        // ignore: avoid_print
        print('[net] 假 key 请求耗时 ${sw.elapsedMilliseconds} ms，'
            'kind=${reply.errorKind}，error=${reply.error}');

        // 这是本用例的核心断言：拿到 401 才算「网络栈通」。
        // 如果这里拿到 network，说明手机的 DNS / TLS / 出网有问题，
        // 那真 key 也一样跑不通 —— 这正是桌面测不出来的部分。
        expect(
          reply.errorKind,
          AiErrorKind.unauthorized,
          reason: '没拿到 401 而是 ${reply.errorKind}：${reply.error}。'
              '说明手机这边 DNS / TLS / 出网不通，先查网络再查 key。',
        );
        expect(reply.isOk, isFalse);
        // 文案要能指路，不能只说「请求失败」。
        expect(reply.error, contains('key'));
      });
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );

  testWidgets(
    '[net] 真 key：真发一次请求，拿回模型正文',
    (WidgetTester tester) async {
      await tester.runAsync(() async {
        final client = AiClient(timeout: const Duration(seconds: 60));
        addTearDown(client.close);

        final sw = Stopwatch()..start();
        final reply = await client.complete(_config(_realKey), _prompt);
        sw.stop();

        // ignore: avoid_print
        print('[net] 真 key 请求耗时 ${sw.elapsedMilliseconds} ms，'
            'ok=${reply.isOk}，正文=${reply.text}');

        expect(
          reply.isOk,
          isTrue,
          reason: '真请求失败（${reply.errorKind}）：${reply.error}',
        );
        expect(reply.text.trim(), isNotEmpty, reason: '模型没给回内容');
      });
    },
    // 没传 key 就跳过，默认行为（和 test/e2e 那套一致）。
    // 注意 testWidgets 的 skip 只收 bool?，不像 test() 能塞一句跳过理由。
    skip: _realKey.isEmpty,
    timeout: const Timeout(Duration(minutes: 3)),
  );
}
