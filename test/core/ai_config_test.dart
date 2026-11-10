import 'package:dlaoshi_app/core/ai_config.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('默认与序列化', () {
    test('默认值是 DeepSeek 官方地址 + chat 模型 + 低温', () {
      const config = defaultAiConfig;
      expect(config.baseUrl, defaultAiBaseUrl);
      expect(config.model, defaultAiModel);
      expect(config.temperature, defaultAiTemperature);
      expect(config.hasApiKey, isFalse);
      expect(config.maskedApiKey, '（未填写）');
    });

    test('toJson → normalize 往返不丢字段', () {
      const config = AiConfig(
        baseUrl: 'https://api.example.com',
        apiKey: 'sk-abcdefghijklmnop',
        model: 'deepseek-reasoner',
        temperature: 1.25,
      );
      final back = normalizeAiConfig(aiConfigToJson(config));
      expect(back, config);
      expect(back.hasApiKey, isTrue);
    });

    test('copyWith 只改传入的字段', () {
      const base = AiConfig();
      final next = base.copyWith(apiKey: 'sk-123', temperature: 0.7);
      expect(next.baseUrl, defaultAiBaseUrl);
      expect(next.model, defaultAiModel);
      expect(next.apiKey, 'sk-123');
      expect(next.temperature, 0.7);
      expect(base.hasApiKey, isFalse);
    });

    test('maskedApiKey 不回显完整 key', () {
      const config = AiConfig(apiKey: 'sk-abcdefghijklmnop');
      expect(config.maskedApiKey, 'sk-a****mnop');
      expect(config.maskedApiKey, isNot(contains('bcdefghijkl')));
      expect(config.toString(), isNot(contains('bcdefghijkl')));
      expect(AiConfig(apiKey: 'short').maskedApiKey, 's****');
    });
  });

  group('normalizeAiConfig 守卫', () {
    test('非 Map / 空 Map 回默认', () {
      expect(normalizeAiConfig(null), defaultAiConfig);
      expect(normalizeAiConfig('oops'), defaultAiConfig);
      expect(normalizeAiConfig(42), defaultAiConfig);
      expect(normalizeAiConfig(const <String, Object?>{}), defaultAiConfig);
    });

    test('坏 baseUrl 回默认；合法地址去掉末尾斜杠', () {
      expect(
        normalizeAiConfig(const <String, Object?>{'baseUrl': '不是网址'})
            .baseUrl,
        defaultAiBaseUrl,
      );
      expect(
        normalizeAiConfig(const <String, Object?>{'baseUrl': 'ftp://x.com'})
            .baseUrl,
        defaultAiBaseUrl,
      );
      expect(
        normalizeAiConfig(
                const <String, Object?>{'baseUrl': 'https://x.com/v1///'})
            .baseUrl,
        'https://x.com/v1',
      );
    });

    test('apiKey / model 只认非空字符串', () {
      final config = normalizeAiConfig(const <String, Object?>{
        'apiKey': 123,
        'model': '  deepseek-reasoner  ',
      });
      expect(config.hasApiKey, isFalse);
      expect(config.model, 'deepseek-reasoner');
      expect(
        normalizeAiConfig(const <String, Object?>{'model': '   '}).model,
        defaultAiModel,
      );
    });

    test('temperature：非数字 / NaN / 越界都归位或 clamp', () {
      expect(
        normalizeAiConfig(const <String, Object?>{'temperature': '0.7'})
            .temperature,
        defaultAiTemperature,
      );
      expect(
        normalizeAiConfig(const <String, Object?>{'temperature': -3})
            .temperature,
        minAiTemperature,
      );
      expect(
        normalizeAiConfig(const <String, Object?>{'temperature': 99})
            .temperature,
        maxAiTemperature,
      );
      expect(
        normalizeAiConfig(const <String, Object?>{'temperature': 0.8})
            .temperature,
        0.8,
      );
    });

    test('字段全坏时依然是个能用的配置', () {
      final config = normalizeAiConfig(const <String, Object?>{
        'baseUrl': null,
        'apiKey': <String>[],
        'model': <String, Object?>{},
        'temperature': double.nan,
      });
      expect(config.baseUrl, defaultAiBaseUrl);
      expect(config.model, defaultAiModel);
      expect(config.temperature, defaultAiTemperature);
      expect(config.hasApiKey, isFalse);
    });
  });
}
